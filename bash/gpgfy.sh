#!/bin/bash

# Filename: gpgfy.sh
# Description: Encrypts a file symmetrically, then asymmetrically.
#              Can also decrypt the result by reversing the steps.

# Encrypt: ./gpgfy.sh encrypt input.txt recipient@example.com
# Decrypt: ./gpgfy.sh decrypt input.txt.asymmetric.gpg

encrypt_file() {
    INPUT="$1"
    RECIPIENT="$2"
    SYM_FILE="${INPUT}.symmetric.gpg"
    FINAL_FILE="${INPUT}.asymmetric.gpg"

    echo "🔐 [1/2] Symmetric encryption of '$INPUT'..."
    gpg --batch --yes --symmetric --cipher-algo AES256 --output "$SYM_FILE" "$INPUT"

    echo "🔐 [2/2] Asymmetric encryption of '$SYM_FILE' for $RECIPIENT..."
    gpg -vv --batch --yes --encrypt --recipient "$RECIPIENT" --output "$FINAL_FILE" "$SYM_FILE"

    rm -f "$SYM_FILE"
    echo "✅ Encrypted: $FINAL_FILE"
}

decrypt_file() {
    ENCRYPTED_FILE="$1"
    INTERMEDIATE_FILE="${ENCRYPTED_FILE%.asymmetric.gpg}.symmetric.gpg"
    OUTPUT_FILE="${ENCRYPTED_FILE%.asymmetric.gpg}.decrypted"

    echo "🔓 [1/2] Asymmetric decryption of '$ENCRYPTED_FILE'..."
    gpg --batch --yes --output "$INTERMEDIATE_FILE" --decrypt "$ENCRYPTED_FILE"

    echo "🔓 [2/2] Symmetric decryption of '$INTERMEDIATE_FILE'..."
    gpg -vv --batch --yes --output "$OUTPUT_FILE" --decrypt "$INTERMEDIATE_FILE"

    rm -f "$INTERMEDIATE_FILE"
    echo "✅ Decrypted: $OUTPUT_FILE"
}


help() {
    cat <<EOF
🔐 gpgfy - Encrypt and decrypt files using symmetric + asymmetric GPG encryption

Usage:
  gpgfy encrypt <input_file> <recipient_email>
      Encrypt the input file using AES256 (symmetric), then GPG (asymmetric).

  gpgfy decrypt <encrypted_file>
      Decrypt a file encrypted by this script.

  gpgfy help
      Show this help message.

Examples:
  gpgfy encrypt notes.txt alice@example.com
  gpgfy decrypt notes.txt.asymmetric.gpg

Notes:
- Requires GPG to be installed and properly configured.
- For encryption, the recipient must have a public key in your GPG keyring.
EOF
}



# Main
if [[ "$1" == "encrypt" && -n "$2" && -n "$3" ]]; then
    encrypt_file "$2" "$3"
elif [[ "$1" == "decrypt" && -n "$2" ]]; then
    decrypt_file "$2"
elif [[ "$1" == "help" || "$1" == "--help" || "$1" == "-h" ]]; then
    help
else
    echo "❌ Invalid arguments."
    help
    exit 1
fi

