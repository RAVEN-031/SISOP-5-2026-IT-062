#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OSBOOT_DIR="${ROOT_DIR}/osboot"
TIMESTAMP="$(date +%d%m%Y-%H%M%S)"
OUTPUT_FILE="${OSBOOT_DIR}/farewell_backup_[${TIMESTAMP}].zip"

FILES=(
    "bzImage"
    "single.gz"
    "multi.gz"
    "farewell.iso"
)

if ! command -v zip >/dev/null 2>&1; then
    echo "Error: zip is required to create the backup archive." >&2
    exit 1
fi

for file in "${FILES[@]}"; do
    if [ ! -f "${OSBOOT_DIR}/${file}" ]; then
        echo "Error: ${OSBOOT_DIR}/${file} is missing." >&2
        exit 1
    fi
done

(
    cd "${OSBOOT_DIR}"
    zip -9 -q "${OUTPUT_FILE}" "${FILES[@]}"
)

echo "Backup archive created at ${OUTPUT_FILE}"
