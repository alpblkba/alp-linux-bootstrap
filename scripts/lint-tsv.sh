#!/usr/bin/env bash
set -euo pipefail

EXIT_CODE=0

mapfile -t TSV_FILES < <(find packages -name "*.tsv" 2>/dev/null | sort)

if [ ${#TSV_FILES[@]} -eq 0 ]; then
    echo "error: no tsv files found in packages/"
    exit 1
fi

for file in "${TSV_FILES[@]}"; do
    echo "linting syntax: $file"

    # Reject lines containing leading spaces instead of tabs
    if grep -P '^[^\t#]+ [^\t#]+' "$file" >/dev/null 2>&1; then
        echo "error: space detected instead of tab separator in $file"
        EXIT_CODE=1
    fi

    # Check for empty lines or malformed rows
    while IFS=$'\t' read -r col1 col2 col3 rest || [ -n "$col1" ]; do
        # Strip CR if present
        col1="${col1//$'\r'/}"
        [[ "$col1" =~ ^#.* ]] && continue
        [ -z "$col1" ] && continue

        if [ -z "$col2" ]; then
            echo "error: missing required columns in $file (line: $col1)"
            EXIT_CODE=1
        fi
    done < "$file"
done

exit $EXIT_CODE
