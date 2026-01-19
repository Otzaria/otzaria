#!/bin/bash

# Script to register otzaria:// URL scheme on Linux

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DESKTOP_FILE="$SCRIPT_DIR/otzaria.desktop"
APP_DIR="$SCRIPT_DIR/../build/linux/x64/release/bundle"
EXECUTABLE="$APP_DIR/otzaria"

# Check if the executable exists
if [ ! -f "$EXECUTABLE" ]; then
    echo "Error: Otzaria executable not found at $EXECUTABLE"
    echo "Please build the application first with: flutter build linux"
    exit 1
fi

echo "Installing otzaria:// URL scheme handler..."

# Create applications directory if it doesn't exist
mkdir -p ~/.local/share/applications

# Copy the desktop file and update the Exec path
sed "s|Exec=otzaria|Exec=$EXECUTABLE|g" "$DESKTOP_FILE" > ~/.local/share/applications/otzaria.desktop

# Make the desktop file executable
chmod +x ~/.local/share/applications/otzaria.desktop

# Update the desktop database
if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database ~/.local/share/applications
    echo "✓ Desktop database updated"
fi

# Register the URL scheme handler
if command -v xdg-mime >/dev/null 2>&1; then
    xdg-mime default otzaria.desktop x-scheme-handler/otzaria
    echo "✓ URL scheme handler registered"
else
    echo "Warning: xdg-mime not found. URL scheme may not work properly."
fi

echo "Successfully installed otzaria:// URL scheme handler!"
echo "You can now open otzaria:// links with the Otzaria application."

# Test the installation
echo ""
echo "Testing installation..."
if xdg-mime query default x-scheme-handler/otzaria 2>/dev/null | grep -q "otzaria.desktop"; then
    echo "✓ URL scheme handler is properly registered"
else
    echo "⚠ URL scheme handler registration may not be complete"
fi