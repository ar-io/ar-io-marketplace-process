#!/bin/bash

# Clean script for ar-io-marketplace-process
# Removes build artifacts, coverage reports, and macOS metadata files

set -e

echo "🧹 Cleaning project..."

# Get the project root directory (parent of scripts directory)
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$PROJECT_ROOT"

# Remove dist directory
if [ -d "dist" ]; then
  echo "  Removing dist/"
  rm -rf dist
fi

# Remove coverage directory
if [ -d "coverage" ]; then
  echo "  Removing coverage/"
  rm -rf coverage
fi

# Remove ._* files (macOS metadata files)
echo "  Removing ._* files..."
find . -type f -name "._*" -delete

echo "✨ Clean complete!"

