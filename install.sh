#!/bin/bash

# Otzaria Linux Installation Script

set -e

# Get the directory where the script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Find the DEB file
DEB_FILE=$(find "$SCRIPT_DIR" -maxdepth 1 -name "otzaria*.deb" | head -n 1)

if [ -z "$DEB_FILE" ]; then
    echo "שגיאה: לא נמצא קובץ DEB"
    exit 1
fi

echo "מתקין את אוצריא..."
echo "קובץ: $(basename "$DEB_FILE")"

# Install using pkexec (GUI sudo)
pkexec apt install -y "$DEB_FILE"

echo ""
echo "✓ ההתקנה הושלמה בהצלחה!"
