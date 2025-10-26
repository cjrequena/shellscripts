#!/bin/bash

# SHA256 Checksum Verification Script
# Verifies file integrity using SHA256 checksums

set -e  # Exit on error

# Function to display help
show_help() {
    cat << EOF
SHA256 Checksum Verification Script

USAGE:
    ./verify_shasum.sh [OPTIONS]

DESCRIPTION:
    Verifies the integrity of files by checking their SHA256 checksums
    against a checksum file. Only files present in the current directory
    are checked (missing files are ignored).

OPTIONS:
    -h, --help          Show this help message and exit
    -f, --file FILE     Specify checksum file (skips interactive prompt)

INTERACTIVE MODE:
    When run without options, the script will prompt for the checksum
    file name. Press Enter to use the default: SHA256SUMS.asc

EXAMPLES:
    # Interactive mode (will prompt for filename)
    ./verify_shasum.sh

    # Direct mode with specified file
    ./verify_shasum.sh -f SHA256SUMS.txt
    ./verify_shasum.sh --file checksums.sha256

EXIT CODES:
    0    All checksums verified successfully
    1    Verification failed or file not found

EOF
    exit 0
}

# Parse command line arguments
CHECKSUM_FILE=""
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            ;;
        -f|--file)
            CHECKSUM_FILE="$2"
            shift 2
            ;;
        *)
            echo "❌ Error: Unknown option: $1"
            echo "Use -h or --help for usage information"
            exit 1
            ;;
    esac
done

# If no file specified via argument, prompt for it
if [ -z "$CHECKSUM_FILE" ]; then
    read -p "Enter checksum file name [SHA256SUMS.asc]: " INPUT_FILE
    CHECKSUM_FILE="${INPUT_FILE:-SHA256SUMS.asc}"
fi

# Check if checksum file exists
if [ ! -f "$CHECKSUM_FILE" ]; then
    echo "❌ Error: Checksum file '$CHECKSUM_FILE' not found!"
    exit 1
fi

echo "Verifying checksums from: $CHECKSUM_FILE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Check if file has GPG signature (for .asc files)
if [[ "$CHECKSUM_FILE" == *.asc ]]; then
    echo "🔐 Verifying GPG signature..."
    if gpg --verify "$CHECKSUM_FILE" 2>&1; then
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "✅ GPG signature verified!"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    else
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "⚠️  GPG signature verification failed or key not found!"
        echo "Continuing with checksum verification..."
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    fi
fi

echo "🔍 Verifying SHA256 checksums..."

# Verify checksums (suppress warning messages, only show results)
RESULT=$(shasum -a 256 --check "$CHECKSUM_FILE" --ignore-missing 2>&1 | grep -v "WARNING")
EXIT_CODE=${PIPESTATUS[0]}

echo "$RESULT"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ $EXIT_CODE -eq 0 ]; then
    echo "✅ All checksums verified successfully!"
    exit 0
else
    echo "❌ Checksum verification failed!"
    exit 1
fi
