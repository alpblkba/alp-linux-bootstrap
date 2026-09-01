#!/usr/bin/env bash
# Structural test for the package manifests.
#
# Asserts that every packages/<target>.tsv uses the same 5-column shape, that
# every row belongs to a known package group, and that every target carries the
# same set of groups. macOS is the single documented exception: it has no
# "server" group, matching resolve_profile_groups() in the bootstrap script.
set -euo pipefail

KNOWN_GROUPS="core server terminal-ux dev-c rust go zig python containers networking security-lite debugging embedded-lite"
PLACEHOLDERS="- none custom manual builtin n/a N/A"

EXIT_CODE=0

fail() {
    echo "error: $*"
    EXIT_CODE=1
}

contains() {
    local needle="$1" haystack="$2" item
    for item in $haystack; do
        [ "$item" = "$needle" ] && return 0
    done
    return 1
}

TSV_FILES="$(find packages -maxdepth 1 -name "*.tsv" | sort)"

if [ -z "$TSV_FILES" ]; then
    echo "error: no package manifests found in packages/"
    exit 1
fi

FILE_COUNT=0

for file in $TSV_FILES; do
    target="$(basename "$file" .tsv)"
    FILE_COUNT=$((FILE_COUNT + 1))
    echo "checking profiles: $file"

    # Header shape: profile / logical_name / <manager>_package / command / notes
    IFS=$'\t' read -r h1 h2 h3 h4 h5 < "$file"
    [ "$h1" = "profile" ] || fail "$file header column 1 is '$h1', expected 'profile'"
    [ "$h2" = "logical_name" ] || fail "$file header column 2 is '$h2', expected 'logical_name'"
    case "$h3" in
        *_package) ;;
        *) fail "$file header column 3 is '$h3', expected something ending in _package" ;;
    esac
    [ "$h4" = "command" ] || fail "$file header column 4 is '$h4', expected 'command'"
    [ "$h5" = "notes" ] || fail "$file header column 5 is '$h5', expected 'notes'"

    # Every data row: exactly 5 tab-separated fields, known group, real package
    LINE_NO=1
    while IFS= read -r line || [ -n "$line" ]; do
        LINE_NO=$((LINE_NO + 1))
        line="${line//$'\r'/}"
        case "$line" in
            ""|\#*) continue ;;
        esac

        fields="$(printf '%s' "$line" | awk -F'\t' '{print NF}')"
        if [ "$fields" -ne 5 ]; then
            fail "$file:$LINE_NO has $fields fields, expected 5"
            continue
        fi

        IFS=$'\t' read -r group logical package command _notes <<< "$line"
        contains "$group" "$KNOWN_GROUPS" || fail "$file:$LINE_NO unknown package group '$group'"
        [ -n "$logical" ] || fail "$file:$LINE_NO empty logical_name"
        [ -n "$package" ] || fail "$file:$LINE_NO empty package for '$logical'"
        [ -n "$command" ] || fail "$file:$LINE_NO empty command for '$logical' (use - when there is none)"
        if contains "$package" "$PLACEHOLDERS"; then
            fail "$file:$LINE_NO placeholder package '$package' for '$logical'; backend rows must name a real package"
        fi
    done < <(tail -n +2 "$file")

    # Group coverage
    present="$(awk -F'\t' 'NR>1 && NF {print $1}' "$file" | sort -u | tr '\n' ' ')"

    for group in $KNOWN_GROUPS; do
        if [ "$target" = "macos" ] && [ "$group" = "server" ]; then
            if contains "$group" "$present"; then
                fail "$file defines a 'server' group; the bootstrap skips that group on macOS"
            fi
            continue
        fi
        contains "$group" "$present" || fail "$file is missing package group '$group'"
    done

    for group in $present; do
        contains "$group" "$KNOWN_GROUPS" || fail "$file: group '$group' is not a known package group"
    done

    printf '  %s: %s rows, groups: %s\n' \
        "$target" "$(awk -F'\t' 'NR>1 && NF' "$file" | wc -l | tr -d ' ')" "$present"
done

if [ "$EXIT_CODE" -eq 0 ]; then
    echo "profile check passed for $FILE_COUNT manifests"
fi

exit $EXIT_CODE
