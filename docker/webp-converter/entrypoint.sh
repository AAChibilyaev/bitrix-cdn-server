#!/bin/bash
# Entrypoint for WebP converter container

set -e

echo "Starting WebP Converter Service..."

# Wait for SSHFS mount
echo "Waiting for SSHFS mount..."
for i in {1..30}; do
    if [ -d "$SOURCE_DIR" ] && [ "$(ls -A $SOURCE_DIR 2>/dev/null)" ]; then
        echo "Mount is ready"
        break
    fi
    echo "Waiting... ($i/30)"
    sleep 2
done

# Check if mount successful
if [ ! -d "$SOURCE_DIR" ] || [ ! "$(ls -A $SOURCE_DIR 2>/dev/null)" ]; then
    echo "WARNING: Source directory not mounted or empty: $SOURCE_DIR"
fi

# Create cache directory
mkdir -p "$CACHE_DIR"
echo "Cache directory: $CACHE_DIR"

# Start converter
exec python3 /app/converter.py
