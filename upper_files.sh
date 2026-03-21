#!/bin/bash

# Default to current directory if no argument is provided
TARGET_DIR="${1:-.}"

echo "Checking files in: $TARGET_DIR"
echo "--------------------------------"

for file in "$TARGET_DIR"/*; do
  # Ensure it is a file, not a folder
  if [ -f "$file" ]; then

    dirname=$(dirname "$file")
    filename=$(basename "$file")

    # Calculate the uppercase name using 'tr' (compatible with your system)
    upper_filename=$(echo "$filename" | tr '[:lower:]' '[:upper:]')

    # --- THE CHECK ---
    # If the original name matches the uppercase name, do nothing.
    if [ "$filename" == "$upper_filename" ]; then
      echo "Skipping: $filename (Already uppercase)"
      continue
    fi

    # --- THE RENAME ---
    # Use a temporary name to ensure safety on all operating systems
    mv "$file" "$dirname/${upper_filename}_temp_safe"
    mv "$dirname/${upper_filename}_temp_safe" "$dirname/$upper_filename"

    echo "Changed:  $filename -> $upper_filename"
  fi
done
