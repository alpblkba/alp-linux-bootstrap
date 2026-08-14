#!/usr/bin/env bash
set -euo pipefail

DISTRO="${1:-}"

if [ -z "$DISTRO" ]; then
    echo "usage: $0 <distro_name>"
    exit 1
fi

TSV_FILE="packages/${DISTRO}.tsv"

if [ ! -f "$TSV_FILE" ]; then
    echo "error: file not found: $TSV_FILE"
    exit 1
fi

MISSING_PACKAGES=()
VERIFIED_COUNT=0

echo "verifying packages in $TSV_FILE for $DISTRO"

while IFS=$'\t' read -r col1 col2 col3 col4 || [ -n "$col1" ]; do
    col1="${col1//$'\r'/}"
    col2="${col2//$'\r'/}"
    col3="${col3//$'\r'/}"
    col4="${col4//$'\r'/}"

    [[ "$col1" =~ ^#.* ]] && continue
    [ "$col1" = "category" ] && continue
    [ "$col2" = "logical_name" ] && continue

    if [ -n "$col4" ] || [ -n "$col3" ]; then
        PACKAGE="$col3"
    else
        PACKAGE="$col2"
    fi

    PACKAGE="$(echo "$PACKAGE" | xargs)"

    [ -z "$PACKAGE" ] && continue
    case "$PACKAGE" in
        "-"|"none"|"custom"|"manual"|"n/a"|"N/A"|"builtin")
            continue
            ;;
    esac

    EXISTS=0
    case "$DISTRO" in
        arch)
            if pacman -Si "$PACKAGE" >/dev/null 2>&1; then
                EXISTS=1
            fi
            ;;
        ubuntu|debian)
            if apt-cache show -- "$PACKAGE" >/dev/null 2>&1; then
                EXISTS=1
            fi
            ;;
        fedora|rhel)
            if dnf info -q "$PACKAGE" >/dev/null 2>&1; then
                EXISTS=1
            fi
            ;;
        alpine)
            if apk info -e "$PACKAGE" >/dev/null 2>&1 || apk search -e "$PACKAGE" >/dev/null 2>&1; then
                EXISTS=1
            fi
            ;;
        macos)
            if brew info "$PACKAGE" >/dev/null 2>&1; then
                EXISTS=1
            fi
            ;;
    esac

    if [ "$EXISTS" -eq 1 ]; then
        VERIFIED_COUNT=$((VERIFIED_COUNT + 1))
    else
        MISSING_PACKAGES+=("$PACKAGE")
    fi
done < "$TSV_FILE"

echo "verified: $VERIFIED_COUNT packages found in $DISTRO repositories"

if [ ${#MISSING_PACKAGES[@]} -ne 0 ]; then
    echo "warning: the following packages are not present in standard $DISTRO repositories:"
    printf '  - %s\n' "${MISSING_PACKAGES[@]}"
fi

exit 0
