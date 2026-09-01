#!/usr/bin/env bash
# Resolve nixpkgs attribute paths against <nixpkgs> in a single evaluation.
#
# Reads attribute paths on stdin, one per line (dotted paths such as
# linuxPackages.perf are supported). Prints "attr=version" for every attribute
# that exists; attributes missing from the current channel are dropped.
set -euo pipefail

ATTRS=()

while IFS= read -r attr || [ -n "$attr" ]; do
    attr="${attr//$'\r'/}"
    attr="$(echo "$attr" | xargs)"
    [ -z "$attr" ] && continue
    ATTRS+=("$attr")
done

if [ ${#ATTRS[@]} -eq 0 ]; then
    exit 0
fi

EXPR="$(
    printf 'let\n'
    printf '  pkgs = import <nixpkgs> { };\n'
    printf '  lib = pkgs.lib;\n'
    printf '  probe = path: builtins.tryEval (lib.attrByPath (lib.splitString "." path) null pkgs);\n'
    printf '  has = path: let p = probe path; in p.success && p.value != null;\n'
    printf '  version = path:\n'
    printf '    let v = builtins.tryEval ((probe path).value.version or "unknown");\n'
    printf '    in if v.success && builtins.isString v.value then v.value else "unknown";\n'
    printf '  wanted = [\n'
    printf '    "%s"\n' "${ATTRS[@]}"
    printf '  ];\n'
    printf 'in builtins.concatStringsSep "\\n" (map (p: p + "=" + version p) (builtins.filter has wanted))\n'
)"

nix-instantiate --eval --raw --expr "$EXPR"
printf '\n'
