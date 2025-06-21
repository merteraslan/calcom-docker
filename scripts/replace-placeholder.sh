#!/usr/bin/env bash
set -e

# Usage: replace-placeholder.sh <FROM> <TO>
# Replaces all occurrences of FROM with TO in the static build output.

FROM="$1"
TO="$2"

if [ "$FROM" = "$TO" ]; then
    echo "Nothing to replace, the value is already set to ${TO}."
    exit 0
fi

echo "Replacing all statically built instances of ${FROM} with ${TO}."

# Find files in the build output and perform in-place replacement
find apps/web/.next apps/web/public -type f -print0 | \
  xargs -0 grep -Il "${FROM}" | \
  while IFS= read -r file; do
    sed -i "s|${FROM}|${TO}|g" "$file"
  done
