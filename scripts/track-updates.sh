#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"

DISTRO="${1:-}"

if [ -z "$DISTRO" ]; then
    echo "usage: $0 <distro_name>"
    exit 1
fi

TSV_FILE="packages/${DISTRO}.tsv"
LOCK_DIR="packages/locks"
LOCK_FILE="${LOCK_DIR}/${DISTRO}.lock"
OUTPUT_FILE="updates_${DISTRO}.txt"

mkdir -p "$LOCK_DIR"
touch "$LOCK_FILE"
rm -f "$OUTPUT_FILE"

RELEASE_INFO=""
case "$DISTRO" in
    arch)
        RELEASE_INFO="rolling"
        ;;
    ubuntu|debian)
        RELEASE_INFO="$(grep -oP '(?<=VERSION_CODENAME=).*' /etc/os-release 2>/dev/null || echo 'stable')"
        ;;
    fedora|rhel)
        RELEASE_INFO="$(grep -oP '(?<=VERSION_ID=).*' /etc/os-release 2>/dev/null || echo 'stable' | tr -d '"')"
        ;;
    alpine)
        RELEASE_INFO="$(cut -d. -f1,2 /etc/alpine-release 2>/dev/null || echo 'edge')"
        ;;
    nix)
        RELEASE_INFO="$( { nix-instantiate --eval --expr '(import <nixpkgs> { }).lib.version' 2>/dev/null || true; } | tr -d '"')"
        [ -z "$RELEASE_INFO" ] && RELEASE_INFO="unknown"
        ;;
    macos)
        RELEASE_INFO="$(sw_vers -productVersion 2>/dev/null || echo 'darwin')"
        ;;
esac

# One nixpkgs evaluation resolves every attribute to a version; the per-package
# loop below only reads the result.
NIX_VERSIONS=""
if [ "$DISTRO" = "nix" ]; then
    NIX_VERSIONS="$(mktemp)"
    trap 'rm -f "$NIX_VERSIONS"' EXIT
    awk -F'\t' 'NR > 1 && NF >= 3 { print $3 }' "$TSV_FILE" \
        | "$SCRIPT_DIR/nix-query.sh" > "$NIX_VERSIONS"
fi

TEMP_LOCK="$(mktemp)"
CHANGES_BUFFER="$(mktemp)"

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

    CURRENT_VER=""
    case "$DISTRO" in
        arch)
            CURRENT_VER="$(pacman -Si "$PACKAGE" 2>/dev/null | awk '/^Version/{print $3}' || true)"
            ;;
        ubuntu|debian)
            CURRENT_VER="$(apt-cache policy "$PACKAGE" 2>/dev/null | awk '/Candidate:/{print $2}' || true)"
            ;;
        fedora|rhel)
            CURRENT_VER="$(dnf info -q "$PACKAGE" 2>/dev/null | awk '/Version/{v=$3} /Release/{r=$3} END{if(v) print v"-"r}' || true)"
            ;;
        alpine)
            CURRENT_VER="$(apk policy "$PACKAGE" 2>/dev/null | awk '/:[ ]*$/ && !/policy:/{gsub(/[ :]/, ""); print; exit}' || true)"
            ;;
        nix)
            CURRENT_VER="$(awk -F'=' -v p="$PACKAGE" '$1 == p { sub(/^[^=]*=/, ""); print; exit }' "$NIX_VERSIONS")"
            ;;
        macos)
            CURRENT_VER="$(brew info --json=v2 "$PACKAGE" 2>/dev/null | grep -oP '(?<="version":")[^"]*' | head -n1 || true)"
            ;;
    esac

    [ -z "$CURRENT_VER" ] && CURRENT_VER="unknown"

    echo "${PACKAGE}=${CURRENT_VER}" >> "$TEMP_LOCK"

    # Literal compare: attribute names carry dots (linuxPackages.perf) and
    # package names carry regex metacharacters (docker.io, g++).
    OLD_VER="$(awk -F'=' -v p="$PACKAGE" '$1 == p { sub(/^[^=]*=/, ""); print; exit }' "$LOCK_FILE")"

    if [ -n "$OLD_VER" ] && [ "$OLD_VER" != "$CURRENT_VER" ] && [ "$OLD_VER" != "unknown" ]; then
        echo "${PACKAGE} ${OLD_VER} replaced with: ${CURRENT_VER}" >> "$CHANGES_BUFFER"
    fi
done < "$TSV_FILE"

if [ -s "$CHANGES_BUFFER" ]; then
    echo "${DISTRO} ${RELEASE_INFO}:" > "$OUTPUT_FILE"
    cat "$CHANGES_BUFFER" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
fi

mv "$TEMP_LOCK" "$LOCK_FILE"
rm -f "$CHANGES_BUFFER"
