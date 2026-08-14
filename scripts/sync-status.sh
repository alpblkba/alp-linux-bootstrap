#!/usr/bin/env bash
set -euo pipefail

STATUS_FILE="packages/STATUS.md"
DATE=$(date -u +"%Y-%m-%d %H:%M:%S UTC")

cat <<EOF > "$STATUS_FILE"
# Package synchronization status

Last automated scan: $DATE

| Distribution | Verified packages | Missing / Custom |
| :--- | :--- | :--- |
EOF

for file in packages/*.tsv; do
    [ -f "$file" ] || continue
    distro=$(basename "$file" .tsv)
    
    total=0
    placeholder=0
    
    while IFS=$'\t' read -r col1 col2 col3 col4 || [ -n "$col1" ]; do
        col1="${col1//$'\r'/}"
        col2="${col2//$'\r'/}"
        col3="${col3//$'\r'/}"
        col4="${col4//$'\r'/}"

        [[ "$col1" =~ ^#.* ]] && continue
        [ "$col1" = "category" ] && continue
        [ "$col2" = "logical_name" ] && continue

        if [ -n "$col4" ] || [ -n "$col3" ]; then
            pkg="$col3"
        else
            pkg="$col2"
        fi
        
        pkg="$(echo "$pkg" | xargs)"
        [ -z "$pkg" ] && continue
        
        total=$((total + 1))
        case "$pkg" in
            "-"|"none"|"custom"|"manual"|"builtin")
                placeholder=$((placeholder + 1))
                ;;
        esac
    done < "$file"
    
    verified=$((total - placeholder))
    echo "| $distro | $verified | $placeholder |" >> "$STATUS_FILE"
done

echo "status matrix updated at $STATUS_FILE"
