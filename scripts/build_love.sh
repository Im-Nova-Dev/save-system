#!/bin/sh
# Build the LÖVE .love bundle for the save system example.
# Usage: ./scripts/build_love.sh [output_dir]
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="${1:-$SCRIPT_DIR}"
LOVE_DIR="$SCRIPT_DIR/love_example"

echo "Copying library files to love_example..."
cp -r "$SCRIPT_DIR/lib" "$LOVE_DIR/"
cp "$SCRIPT_DIR/save_manager.lua" "$LOVE_DIR/"

echo "Creating .love bundle..."
cd "$LOVE_DIR"
zip -r "$OUTPUT_DIR/save_example.love" . -x "*.git/*" > /dev/null

echo "Bundle created: $OUTPUT_DIR/save_example.love"
echo "Run: love $OUTPUT_DIR/save_example.love"
