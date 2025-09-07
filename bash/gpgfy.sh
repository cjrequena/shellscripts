#!/bin/bash

# Filename: gpgfy.sh
# Description: Encrypts a file symmetrically, then asymmetrically with enhanced security and error handling.
#              Can also decrypt the result by reversing the steps.
# Version: 2.0

# Usage:
# Encrypt: ./gpgfy.sh encrypt input.txt recipient@example.com
# Decrypt: ./gpgfy.sh decrypt input.txt.asymmetric.gpg

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Configuration
readonly CIPHER_ALGO="AES256"
readonly DIGEST_ALGO="SHA512"
readonly COMPRESS_ALGO="2"  # ZLIB compression
readonly S2K_MODE="3"       # Iterated and salted S2K
readonly S2K_COUNT="65011712"  # High iteration count for key derivation

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}" >&2
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}" >&2
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}" >&2
}

log_error() {
    echo -e "${RED}❌ $1${NC}" >&2
}

# Cleanup function for temporary files
cleanup() {
    local temp_files=("$@")
    for file in "${temp_files[@]}"; do
        if [[ -f "$file" ]]; then
            log_info "Cleaning up temporary file: $file"
            shred -vfz -n 3 "$file" 2>/dev/null || rm -f "$file"
        fi
    done
}

# Validate GPG installation and configuration
validate_gpg() {
    if ! command -v gpg >/dev/null 2>&1; then
        log_error "GPG is not installed or not in PATH"
        exit 1
    fi

    local gpg_version
    gpg_version=$(gpg --version | head -n1 | cut -d' ' -f3)
    log_info "Using GPG version: $gpg_version"
}

# Check if recipient key exists
check_recipient_key() {
    local recipient="$1"

    log_info "Checking for recipient key: $recipient"
    if ! gpg --list-keys "$recipient" >/dev/null 2>&1; then
        log_error "No public key found for recipient: $recipient"
        log_info "Import the recipient's public key first:"
        log_info "  gpg --import recipient_pubkey.asc"
        exit 1
    fi

    # Check key validity
    local key_validity
    key_validity=$(gpg --list-keys --with-colons "$recipient" 2>/dev/null | awk -F: '/^pub:/ {print $2}')
    if [[ "$key_validity" == "r" ]]; then
        log_warning "Recipient key is revoked: $recipient"
    elif [[ "$key_validity" == "e" ]]; then
        log_warning "Recipient key is expired: $recipient"
    fi
}

# Validate file paths and permissions
validate_file() {
    local file="$1"
    local operation="$2"

    if [[ ! -f "$file" ]]; then
        log_error "File not found: $file"
        exit 1
    fi

    if [[ "$operation" == "read" && ! -r "$file" ]]; then
        log_error "Cannot read file: $file"
        exit 1
    fi

    if [[ "$operation" == "write" ]]; then
        local dir
        dir=$(dirname "$file")
        if [[ ! -w "$dir" ]]; then
            log_error "Cannot write to directory: $dir"
            exit 1
        fi
    fi
}

# Generate secure temporary filename
generate_temp_file() {
    local base="$1"
    local suffix="$2"
    echo "${base}.$(date +%s).${RANDOM}.${suffix}"
}

encrypt_file() {
    local input="$1"
    local recipient="$2"

    # Validation
    validate_file "$input" "read"
    check_recipient_key "$recipient"

    # Generate output filenames
    local sym_file final_file
    sym_file=$(generate_temp_file "$input" "symmetric.gpg")
    final_file="${input}.asymmetric.gpg"

    # Check if output file already exists
    if [[ -f "$final_file" ]]; then
        log_warning "Output file already exists: $final_file"
        read -p "Overwrite? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Operation cancelled"
            exit 0
        fi
    fi

    # Setup cleanup trap
    trap "cleanup '$sym_file'" EXIT INT TERM

    log_info "[1/2] Symmetric encryption of '$input' with $CIPHER_ALGO..."

    # Symmetric encryption with enhanced security parameters
    if ! gpg \
        --batch \
        --yes \
        --quiet \
        --symmetric \
        --cipher-algo "$CIPHER_ALGO" \
        --digest-algo "$DIGEST_ALGO" \
        --compress-algo "$COMPRESS_ALGO" \
        --s2k-mode "$S2K_MODE" \
        --s2k-count "$S2K_COUNT" \
        --output "$sym_file" \
        "$input"; then
        log_error "Symmetric encryption failed"
        exit 1
    fi

    log_info "[2/2] Asymmetric encryption for recipient: $recipient..."

    # Asymmetric encryption with trust model override
    if ! gpg \
        --batch \
        --yes \
        --quiet \
        --trust-model always \
        --encrypt \
        --recipient "$recipient" \
        --cipher-algo "$CIPHER_ALGO" \
        --digest-algo "$DIGEST_ALGO" \
        --compress-algo "$COMPRESS_ALGO" \
        --output "$final_file" \
        "$sym_file"; then
        log_error "Asymmetric encryption failed"
        exit 1
    fi

    # Verify the encrypted file was created and has content
    if [[ ! -s "$final_file" ]]; then
        log_error "Encryption failed: output file is empty or missing"
        exit 1
    fi

    log_success "File encrypted successfully: $final_file"
    log_info "Original file size: $(wc -c < "$input") bytes"
    log_info "Encrypted file size: $(wc -c < "$final_file") bytes"
}

decrypt_file() {
    local encrypted_file="$1"

    # Validation
    validate_file "$encrypted_file" "read"

    # Derive filenames
    if [[ ! "$encrypted_file" =~ \.asymmetric\.gpg$ ]]; then
        log_error "File doesn't appear to be encrypted with this script: $encrypted_file"
        log_info "Expected filename pattern: *.asymmetric.gpg"
        exit 1
    fi

    local base_name intermediate_file output_file
    base_name="${encrypted_file%.asymmetric.gpg}"
    intermediate_file=$(generate_temp_file "$base_name" "symmetric.gpg")
    output_file="${base_name}.decrypted"

    # Check if output file already exists
    if [[ -f "$output_file" ]]; then
        log_warning "Output file already exists: $output_file"
        read -p "Overwrite? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Operation cancelled"
            exit 0
        fi
    fi

    # Setup cleanup trap
    trap "cleanup '$intermediate_file'" EXIT INT TERM

    log_info "[1/2] Asymmetric decryption of '$encrypted_file'..."

    # Asymmetric decryption
    if ! gpg \
        --batch \
        --yes \
        --quiet \
        --output "$intermediate_file" \
        --decrypt "$encrypted_file"; then
        log_error "Asymmetric decryption failed"
        log_info "Possible reasons:"
        log_info "  - Wrong private key"
        log_info "  - Private key not available"
        log_info "  - File is corrupted"
        exit 1
    fi

    log_info "[2/2] Symmetric decryption of intermediate file..."

    # Symmetric decryption
    if ! gpg \
        --batch \
        --yes \
        --quiet \
        --output "$output_file" \
        --decrypt "$intermediate_file"; then
        log_error "Symmetric decryption failed"
        log_info "Possible reasons:"
        log_info "  - Wrong passphrase"
        log_info "  - File is corrupted"
        exit 1
    fi

    # Verify the decrypted file was created and has content
    if [[ ! -s "$output_file" ]]; then
        log_error "Decryption failed: output file is empty or missing"
        exit 1
    fi

    log_success "File decrypted successfully: $output_file"
    log_info "Decrypted file size: $(wc -c < "$output_file") bytes"
}

# Verify the integrity of an encrypted file
verify_file() {
    local encrypted_file="$1"

    validate_file "$encrypted_file" "read"

    log_info "Verifying encrypted file: $encrypted_file"

    # Try to list the packets without decrypting
    if gpg --list-packets "$encrypted_file" >/dev/null 2>&1; then
        log_success "File structure appears valid"
        gpg --list-packets "$encrypted_file" | head -10
    else
        log_error "File structure appears corrupted"
        exit 1
    fi
}

# Display comprehensive help
help() {
    cat <<EOF
🔐 gpgfy - Enhanced GPG Encryption Tool v2.0

DESCRIPTION:
    Encrypts files using a two-layer approach: symmetric encryption with AES256
    followed by asymmetric encryption. This provides both the security of public
    key cryptography and the efficiency of symmetric encryption for large files.

USAGE:
    gpgfy encrypt <input_file> <recipient_email>
        Encrypt the input file for the specified recipient.

    gpgfy decrypt <encrypted_file>
        Decrypt a file encrypted by this script.

    gpgfy verify <encrypted_file>
        Verify the structure of an encrypted file.

    gpgfy help
        Show this help message.

EXAMPLES:
    gpgfy encrypt secret.txt alice@example.com
    gpgfy decrypt secret.txt.asymmetric.gpg
    gpgfy verify secret.txt.asymmetric.gpg

SECURITY FEATURES:
    - AES256 symmetric encryption with SHA512 digest
    - High iteration count for key derivation (65M+ iterations)
    - Secure temporary file handling with shredding
    - Key validity checking
    - File integrity verification

REQUIREMENTS:
    - GPG (GNU Privacy Guard) must be installed
    - For encryption: recipient's public key in your keyring
    - For decryption: your private key and the symmetric passphrase

NOTES:
    - Encrypted files use the extension: .asymmetric.gpg
    - Decrypted files use the extension: .decrypted
    - Temporary files are securely deleted after use
    - The script will prompt before overwriting existing files

TROUBLESHOOTING:
    - Ensure GPG is properly configured: gpg --list-keys
    - Import recipient's key: gpg --import pubkey.asc
    - Check key validity: gpg --check-sigs recipient@example.com

For more information, see: https://gnupg.org/documentation/
EOF
}

# Main execution
main() {
    # Validate GPG availability
    validate_gpg

    case "${1:-}" in
        "encrypt")
            if [[ -z "${2:-}" || -z "${3:-}" ]]; then
                log_error "Missing arguments for encrypt command"
                echo
                help
                exit 1
            fi
            encrypt_file "$2" "$3"
            ;;
        "decrypt")
            if [[ -z "${2:-}" ]]; then
                log_error "Missing argument for decrypt command"
                echo
                help
                exit 1
            fi
            decrypt_file "$2"
            ;;
        "verify")
            if [[ -z "${2:-}" ]]; then
                log_error "Missing argument for verify command"
                echo
                help
                exit 1
            fi
            verify_file "$2"
            ;;
        "help"|"--help"|"-h"|"")
            help
            ;;
        *)
            log_error "Invalid command: ${1:-}"
            echo
            help
            exit 1
            ;;
    esac
}

# Execute main function with all arguments
main "$@"
