#!/bin/bash

# Check if files exist - logic is inverted: file NOT found = pass, file found = error

if [ $# -eq 0 ]; then
    echo "Error: No files provided"
    echo "Usage: $0 file1 [file2 ...]"
    exit 1
fi

found_files=()

for file in "$@"; do
    if [ -e "$file" ]; then
        found_files+=("$file")
    fi
done

if [ ${#found_files[@]} -eq 0 ]; then
    echo "pass"
else
    echo "Error: Found ${#found_files[@]} file(s):"
    for f in "${found_files[@]}"; do
        echo "  - $f"
    done
    exit 1
fi
