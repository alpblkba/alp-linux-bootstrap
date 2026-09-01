#!/usr/bin/env bash
set -Eeuo pipefail

DEFAULT_PROFILE="alp-base"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
UBUNTU_TSV="$SCRIPT_DIR/packages/ubuntu.tsv"
DEBIAN_TSV="$SCRIPT_DIR/packages/debian.tsv"
MACOS_TSV="$SCRIPT_DIR/packages/macos.tsv"
FEDORA_TSV="$SCRIPT_DIR/packages/fedora.tsv"
ARCH_TSV="$SCRIPT_DIR/packages/arch.tsv"
RHEL_TSV="$SCRIPT_DIR/packages/rhel.tsv"
ALPINE_TSV="$SCRIPT_DIR/packages/alpine.tsv"
NIX_TSV="$SCRIPT_DIR/packages/nix.tsv"
NIX_RELEASES_TSV="$SCRIPT_DIR/packages/meta/nix-releases.tsv"
CHECK_SCRIPT="/tmp/check-alp-bootstrap-tools.sh"
IMPLEMENTED_BACKENDS="ubuntu, debian, fedora, arch, rhel, alpine, nix, macos"
PLANNED_BACKENDS="centos, suse"

# Package groups as they appear in the first column of packages/*.tsv.
# alp-base is the default; alp-heavy is every group; any single group name is
# also a valid profile and is installed on top of alp-base.
KNOWN_GROUPS=(core server terminal-ux dev-c rust go zig python containers networking security-lite debugging embedded-lite)
BASE_GROUPS=(core server terminal-ux)
SYNTHETIC_PROFILES="alp-base, alp-heavy"
SELECTED_GROUPS=()

DRY_RUN=0
PROFILE="$DEFAULT_PROFILE"
NO_JAVA=1
ADD_JAVA=0
JAVA_FLAG_SOURCE=""

OS_ID=""
OS_NAME=""
OS_VERSION_ID=""
OS_ARCH=""
OS_KERNEL=""
BACKEND=""

SELECTED_APT_PACKAGES=()
AVAILABLE_APT_PACKAGES=()
SELECTED_DEBIAN_APT_PACKAGES=()
AVAILABLE_DEBIAN_APT_PACKAGES=()
SELECTED_BREW_PACKAGES=()
AVAILABLE_BREW_PACKAGES=()
SELECTED_DNF_PACKAGES=()
AVAILABLE_DNF_PACKAGES=()
SELECTED_PACMAN_PACKAGES=()
AVAILABLE_PACMAN_PACKAGES=()
SELECTED_RHEL_DNF_PACKAGES=()
AVAILABLE_RHEL_DNF_PACKAGES=()
SELECTED_APK_PACKAGES=()
AVAILABLE_APK_PACKAGES=()
SELECTED_NIX_ATTRS=()
AVAILABLE_NIX_ATTRS=()
SELECTED_COMMANDS=()

NIX_RELEASE=""
NIX_CODENAME=""
NIX_CHANNEL=""
NIX_RELEASE_STATUS=""
NIX_CURRENT_RELEASE=""
NIX_MIN_RELEASE=""
NIX_MIN_CODENAME=""
NIX_SUPPORTED_RELEASES=""
NIX_RELEASE_IDS=()
NIX_RELEASE_CODENAMES=()
NIX_RELEASE_CHANNELS=()
NIX_RELEASE_STATUSES=()

log() {
  printf '[alp-bootstrap] %s\n' "$*"
}

warn() {
  printf '[alp-bootstrap] warning: %s\n' "$*" >&2
}

die() {
  printf '[alp-bootstrap] error: %s\n' "$*" >&2
  exit 1
}

run_privileged() {
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  else
    die "root privileges required; run as root or install sudo"
  fi
}

usage() {
  cat <<'USAGE'
Usage: ./alp-linux-oneshot-bootstrap.sh [options]

Options:
  --dry-run          Print packages and actions without applying them.
  --profile <name>   Select profile to install. Default: alp-base.
  --no-java          Keep Java/JVM tooling excluded. Default.
  --add-java         Reserved Java/JVM opt-in placeholder; does not install Java.
  --with-java        Deprecated alias for --add-java; does not install Java.
  --help             Show this help.

Profiles:
  alp-base           core + server + terminal-ux. Default.
  alp-heavy          Every package group.
  <group>            Any single package group, installed on top of alp-base:
                     core, server, terminal-ux, dev-c, rust, go, zig, python,
                     containers, networking, security-lite, debugging,
                     embedded-lite.

The server group is skipped on macOS; the macOS package map does not define it.

Implemented backends: ubuntu, debian, fedora, arch, rhel, alpine, nix, macos.
Planned backends: centos, suse.
USAGE
}

detect_os() {
  OS_ARCH="$(uname -m)"
  OS_KERNEL="$(uname -s)"

  if [[ "$OS_KERNEL" == "Darwin" ]]; then
    OS_ID="macos"
    OS_NAME="macOS"
    OS_VERSION_ID="$(sw_vers -productVersion 2>/dev/null || printf 'unknown')"
    return 0
  fi

  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release

    OS_ID="${ID:-unknown}"
    OS_NAME="${NAME:-unknown}"
    OS_VERSION_ID="${VERSION_ID:-unknown}"
    return 0
  fi

  OS_ID="unknown"
  OS_NAME="$OS_KERNEL"
  OS_VERSION_ID="unknown"
}

select_backend() {
  case "$OS_ID" in
    ubuntu)
      BACKEND="ubuntu"
      ;;
    debian)
      BACKEND="debian"
      ;;
    fedora)
      BACKEND="fedora"
      ;;
    arch|archarm)
      BACKEND="arch"
      ;;
    alpine)
      BACKEND="alpine"
      ;;
    nixos)
      BACKEND="nix"
      ;;
    opensuse*|sles)
      BACKEND="suse"
      ;;
    rhel)
      BACKEND="rhel"
      ;;
    centos)
      BACKEND="centos"
      ;;
    macos)
      BACKEND="macos"
      ;;
    *)
      BACKEND="unknown"
      ;;
  esac
}

require_supported_backend() {
  if [[ "$BACKEND" == "ubuntu" || "$BACKEND" == "debian" || "$BACKEND" == "fedora" || "$BACKEND" == "arch" || "$BACKEND" == "rhel" || "$BACKEND" == "alpine" || "$BACKEND" == "nix" || "$BACKEND" == "macos" ]]; then
    return 0
  fi

  die "backend '$BACKEND' for ${OS_NAME} ${OS_VERSION_ID} is planned but not implemented in v0; implemented backends: $IMPLEMENTED_BACKENDS; planned backends: $PLANNED_BACKENDS"
}

parse_args() {
  while (($#)); do
    case "$1" in
      --dry-run)
        DRY_RUN=1
        shift
        ;;
      --profile)
        [[ $# -ge 2 ]] || die "--profile requires a value"
        PROFILE="$2"
        shift 2
        ;;
      --no-java)
        NO_JAVA=1
        ADD_JAVA=0
        JAVA_FLAG_SOURCE=""
        shift
        ;;
      --add-java)
        ADD_JAVA=1
        NO_JAVA=0
        JAVA_FLAG_SOURCE="--add-java"
        shift
        ;;
      --with-java)
        ADD_JAVA=1
        NO_JAVA=0
        JAVA_FLAG_SOURCE="--with-java"
        shift
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      *)
        die "unknown option: $1"
        ;;
    esac
  done
}

resolve_profile_groups() {
  local groups=() group

  case "$PROFILE" in
    alp-base)
      groups=("${BASE_GROUPS[@]}")
      ;;
    alp-heavy)
      groups=("${KNOWN_GROUPS[@]}")
      ;;
    *)
      array_contains "$PROFILE" "${KNOWN_GROUPS[@]}" \
        || die "unknown profile: $PROFILE; synthetic profiles: $SYNTHETIC_PROFILES; package groups: ${KNOWN_GROUPS[*]}"
      groups=("${BASE_GROUPS[@]}" "$PROFILE")
      ;;
  esac

  SELECTED_GROUPS=()

  for group in "${groups[@]}"; do
    # The macOS package map has no server group; skip it instead of failing.
    if [[ "$BACKEND" == "macos" && "$group" == "server" ]]; then
      continue
    fi

    if ((${#SELECTED_GROUPS[@]} == 0)) || ! array_contains "$group" "${SELECTED_GROUPS[@]}"; then
      SELECTED_GROUPS+=("$group")
    fi
  done

  ((${#SELECTED_GROUPS[@]} > 0)) || die "profile '$PROFILE' resolved to no package groups"
}

package_profile_selected() {
  array_contains "$1" "${SELECTED_GROUPS[@]}"
}

array_contains() {
  local needle="$1"
  shift
  local item

  [[ -n "$needle" ]] || return 1

  for item in "$@"; do
    [[ "$item" == "$needle" ]] && return 0
  done

  return 1
}

command_is_checkable() {
  local command="${1:-}"

  case "$command" in
    ""|-|none|NONE)
      return 1
      ;;
    *)
      return 0
      ;;
  esac
}

load_ubuntu_packages_from_tsv() {
  local package_profile logical_name apt_package command notes

  [[ -r "$UBUNTU_TSV" ]] || die "missing Ubuntu package map: $UBUNTU_TSV"

  SELECTED_APT_PACKAGES=()
  SELECTED_COMMANDS=()

  while IFS=$'\t' read -r package_profile logical_name apt_package command notes; do
    [[ -z "${package_profile:-}" ]] && continue
    [[ "$package_profile" == "profile" ]] && continue

    if package_profile_selected "$package_profile"; then
      if [[ -n "${apt_package:-}" ]]; then
        if ((${#SELECTED_APT_PACKAGES[@]} == 0)) || ! array_contains "$apt_package" "${SELECTED_APT_PACKAGES[@]}"; then
          SELECTED_APT_PACKAGES+=("$apt_package")
        fi
      fi

      if command_is_checkable "${command:-}"; then
        if ((${#SELECTED_COMMANDS[@]} == 0)) || ! array_contains "$command" "${SELECTED_COMMANDS[@]}"; then
          SELECTED_COMMANDS+=("$command")
        fi
      fi
    fi
  done < "$UBUNTU_TSV"

  ((${#SELECTED_APT_PACKAGES[@]} > 0)) || die "no apt packages selected for profile: $PROFILE"
}

load_debian_packages_from_tsv() {
  local package_profile logical_name apt_package command notes

  [[ -r "$DEBIAN_TSV" ]] || die "missing Debian package map: $DEBIAN_TSV"

  SELECTED_DEBIAN_APT_PACKAGES=()
  SELECTED_COMMANDS=()

  while IFS=$'\t' read -r package_profile logical_name apt_package command notes; do
    [[ -z "${package_profile:-}" ]] && continue
    [[ "$package_profile" == "profile" ]] && continue

    if package_profile_selected "$package_profile"; then
      if [[ -n "${apt_package:-}" ]]; then
        if ((${#SELECTED_DEBIAN_APT_PACKAGES[@]} == 0)) || ! array_contains "$apt_package" "${SELECTED_DEBIAN_APT_PACKAGES[@]}"; then
          SELECTED_DEBIAN_APT_PACKAGES+=("$apt_package")
        fi
      fi

      if command_is_checkable "${command:-}"; then
        if ((${#SELECTED_COMMANDS[@]} == 0)) || ! array_contains "$command" "${SELECTED_COMMANDS[@]}"; then
          SELECTED_COMMANDS+=("$command")
        fi
      fi
    fi
  done < "$DEBIAN_TSV"

  ((${#SELECTED_DEBIAN_APT_PACKAGES[@]} > 0)) || die "no Debian apt packages selected for profile: $PROFILE"
}

load_macos_packages_from_tsv() {
  local package_profile logical_name brew_package command notes

  [[ -r "$MACOS_TSV" ]] || die "missing macOS package map: $MACOS_TSV"

  SELECTED_BREW_PACKAGES=()
  SELECTED_COMMANDS=()

  while IFS=$'\t' read -r package_profile logical_name brew_package command notes; do
    [[ -z "${package_profile:-}" ]] && continue
    [[ "$package_profile" == "profile" ]] && continue

    if package_profile_selected "$package_profile"; then
      if [[ -n "${brew_package:-}" ]]; then
        if ((${#SELECTED_BREW_PACKAGES[@]} == 0)) || ! array_contains "$brew_package" "${SELECTED_BREW_PACKAGES[@]}"; then
          SELECTED_BREW_PACKAGES+=("$brew_package")
        fi
      fi

      if command_is_checkable "${command:-}"; then
        if ((${#SELECTED_COMMANDS[@]} == 0)) || ! array_contains "$command" "${SELECTED_COMMANDS[@]}"; then
          SELECTED_COMMANDS+=("$command")
        fi
      fi
    fi
  done < "$MACOS_TSV"

  ((${#SELECTED_BREW_PACKAGES[@]} > 0)) || die "no Homebrew packages selected for profile: $PROFILE"
}

load_fedora_packages_from_tsv() {
  local package_profile logical_name dnf_package command notes

  [[ -r "$FEDORA_TSV" ]] || die "missing Fedora package map: $FEDORA_TSV"

  SELECTED_DNF_PACKAGES=()
  SELECTED_COMMANDS=()

  while IFS=$'\t' read -r package_profile logical_name dnf_package command notes; do
    [[ -z "${package_profile:-}" ]] && continue
    [[ "$package_profile" == "profile" ]] && continue

    if package_profile_selected "$package_profile"; then
      if [[ -n "${dnf_package:-}" ]]; then
        if ((${#SELECTED_DNF_PACKAGES[@]} == 0)) || ! array_contains "$dnf_package" "${SELECTED_DNF_PACKAGES[@]}"; then
          SELECTED_DNF_PACKAGES+=("$dnf_package")
        fi
      fi

      if command_is_checkable "${command:-}"; then
        if ((${#SELECTED_COMMANDS[@]} == 0)) || ! array_contains "$command" "${SELECTED_COMMANDS[@]}"; then
          SELECTED_COMMANDS+=("$command")
        fi
      fi
    fi
  done < "$FEDORA_TSV"

  ((${#SELECTED_DNF_PACKAGES[@]} > 0)) || die "no dnf packages selected for profile: $PROFILE"
}

load_arch_packages_from_tsv() {
  local package_profile logical_name pacman_package command notes

  [[ -r "$ARCH_TSV" ]] || die "missing Arch package map: $ARCH_TSV"

  SELECTED_PACMAN_PACKAGES=()
  SELECTED_COMMANDS=()

  while IFS=$'\t' read -r package_profile logical_name pacman_package command notes; do
    [[ -z "${package_profile:-}" ]] && continue
    [[ "$package_profile" == "profile" ]] && continue

    if package_profile_selected "$package_profile"; then
      if [[ -n "${pacman_package:-}" ]]; then
        if ((${#SELECTED_PACMAN_PACKAGES[@]} == 0)) || ! array_contains "$pacman_package" "${SELECTED_PACMAN_PACKAGES[@]}"; then
          SELECTED_PACMAN_PACKAGES+=("$pacman_package")
        fi
      fi

      if command_is_checkable "${command:-}"; then
        if ((${#SELECTED_COMMANDS[@]} == 0)) || ! array_contains "$command" "${SELECTED_COMMANDS[@]}"; then
          SELECTED_COMMANDS+=("$command")
        fi
      fi
    fi
  done < "$ARCH_TSV"

  ((${#SELECTED_PACMAN_PACKAGES[@]} > 0)) || die "no pacman packages selected for profile: $PROFILE"
}

load_rhel_packages_from_tsv() {
  local package_profile logical_name dnf_package command notes

  [[ -r "$RHEL_TSV" ]] || die "missing RHEL package map: $RHEL_TSV"

  SELECTED_RHEL_DNF_PACKAGES=()
  SELECTED_COMMANDS=()

  while IFS=$'\t' read -r package_profile logical_name dnf_package command notes; do
    [[ -z "${package_profile:-}" ]] && continue
    [[ "$package_profile" == "profile" ]] && continue

    if package_profile_selected "$package_profile"; then
      if [[ -n "${dnf_package:-}" ]]; then
        if ((${#SELECTED_RHEL_DNF_PACKAGES[@]} == 0)) || ! array_contains "$dnf_package" "${SELECTED_RHEL_DNF_PACKAGES[@]}"; then
          SELECTED_RHEL_DNF_PACKAGES+=("$dnf_package")
        fi
      fi

      if command_is_checkable "${command:-}"; then
        if ((${#SELECTED_COMMANDS[@]} == 0)) || ! array_contains "$command" "${SELECTED_COMMANDS[@]}"; then
          SELECTED_COMMANDS+=("$command")
        fi
      fi
    fi
  done < "$RHEL_TSV"

  ((${#SELECTED_RHEL_DNF_PACKAGES[@]} > 0)) || die "no RHEL dnf packages selected for profile: $PROFILE"
}

load_alpine_packages_from_tsv() {
  local package_profile logical_name apk_package command notes

  [[ -r "$ALPINE_TSV" ]] || die "missing Alpine package map: $ALPINE_TSV"

  SELECTED_APK_PACKAGES=()
  SELECTED_COMMANDS=()

  while IFS=$'\t' read -r package_profile logical_name apk_package command notes; do
    [[ -z "${package_profile:-}" ]] && continue
    [[ "$package_profile" == "profile" ]] && continue

    if package_profile_selected "$package_profile"; then
      if [[ -n "${apk_package:-}" ]]; then
        if ((${#SELECTED_APK_PACKAGES[@]} == 0)) || ! array_contains "$apk_package" "${SELECTED_APK_PACKAGES[@]}"; then
          SELECTED_APK_PACKAGES+=("$apk_package")
        fi
      fi

      if command_is_checkable "${command:-}"; then
        if ((${#SELECTED_COMMANDS[@]} == 0)) || ! array_contains "$command" "${SELECTED_COMMANDS[@]}"; then
          SELECTED_COMMANDS+=("$command")
        fi
      fi
    fi
  done < "$ALPINE_TSV"

  ((${#SELECTED_APK_PACKAGES[@]} > 0)) || die "no Alpine apk packages selected for profile: $PROFILE"
}

release_sort_key() {
  local release="${1:-}"

  if [[ "$release" =~ ^([0-9]{2})\.([0-9]{2})$ ]]; then
    printf '%s%s' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
    return 0
  fi

  return 1
}

load_nix_release_table() {
  local release codename channel status notes key min_key=""

  [[ -r "$NIX_RELEASES_TSV" ]] || die "missing Nix release table: $NIX_RELEASES_TSV"

  NIX_RELEASE_IDS=()
  NIX_RELEASE_CODENAMES=()
  NIX_RELEASE_CHANNELS=()
  NIX_RELEASE_STATUSES=()
  NIX_CURRENT_RELEASE=""
  NIX_MIN_RELEASE=""
  NIX_MIN_CODENAME=""

  while IFS=$'\t' read -r release codename channel status notes; do
    [[ -z "${release:-}" ]] && continue
    [[ "$release" == "release" ]] && continue

    NIX_RELEASE_IDS+=("$release")
    NIX_RELEASE_CODENAMES+=("$codename")
    NIX_RELEASE_CHANNELS+=("$channel")
    NIX_RELEASE_STATUSES+=("$status")

    if [[ "$status" == "current" ]]; then
      NIX_CURRENT_RELEASE="$release"
    fi

    if key="$(release_sort_key "$release")"; then
      if [[ -z "$min_key" ]] || ((10#$key < 10#$min_key)); then
        min_key="$key"
        NIX_MIN_RELEASE="$release"
        NIX_MIN_CODENAME="$codename"
      fi
    fi
  done < "$NIX_RELEASES_TSV"

  ((${#NIX_RELEASE_IDS[@]} > 0)) || die "no releases defined in $NIX_RELEASES_TSV"
  [[ -n "$NIX_CURRENT_RELEASE" ]] || die "no release marked 'current' in $NIX_RELEASES_TSV"

  NIX_SUPPORTED_RELEASES="${NIX_RELEASE_IDS[*]}"
}

nix_release_lookup() {
  local want="$1" index

  for ((index = 0; index < ${#NIX_RELEASE_IDS[@]}; index++)); do
    if [[ "${NIX_RELEASE_IDS[index]}" == "$want" ]]; then
      NIX_RELEASE="${NIX_RELEASE_IDS[index]}"
      NIX_CODENAME="${NIX_RELEASE_CODENAMES[index]}"
      NIX_CHANNEL="${NIX_RELEASE_CHANNELS[index]}"
      NIX_RELEASE_STATUS="${NIX_RELEASE_STATUSES[index]}"
      return 0
    fi
  done

  return 1
}

resolve_nix_release() {
  local candidate key current_key

  load_nix_release_table

  # NixOS reports VERSION_ID as 26.05 on a release, or 26.05.<date>.<rev> when
  # it follows a channel; the first two components are the release series.
  candidate="$(printf '%s' "${OS_VERSION_ID:-}" | cut -d. -f1,2)"
  [[ -n "$candidate" ]] || candidate="unknown"

  if ! nix_release_lookup "$candidate"; then
    key="$(release_sort_key "$candidate")" || key=""
    current_key="$(release_sort_key "$NIX_CURRENT_RELEASE")" || current_key=""

    if [[ -n "$key" && -n "$current_key" ]] && ((10#$key < 10#$current_key)); then
      die "NixOS release '$candidate' is older than $NIX_MIN_RELEASE ($NIX_MIN_CODENAME), the oldest release this bootstrap accepts; supported releases: $NIX_SUPPORTED_RELEASES"
    fi

    warn "NixOS release '$candidate' is not listed in $NIX_RELEASES_TSV; treating it as the unstable channel"
    nix_release_lookup "unstable" || die "no 'unstable' row in $NIX_RELEASES_TSV"
  fi

  case "$NIX_RELEASE_STATUS" in
    legacy)
      warn "NixOS $NIX_RELEASE ($NIX_CODENAME) is past upstream support; continuing best-effort"
      ;;
    rolling)
      warn "tracking the $NIX_CHANNEL channel; nixpkgs attribute names can move without notice"
      ;;
  esac

  log "nixpkgs target: $NIX_RELEASE ($NIX_CODENAME), channel $NIX_CHANNEL, status $NIX_RELEASE_STATUS"
}

load_nix_packages_from_tsv() {
  local package_profile logical_name nix_package command notes

  [[ -r "$NIX_TSV" ]] || die "missing Nix package map: $NIX_TSV"

  SELECTED_NIX_ATTRS=()
  SELECTED_COMMANDS=()

  while IFS=$'\t' read -r package_profile logical_name nix_package command notes; do
    [[ -z "${package_profile:-}" ]] && continue
    [[ "$package_profile" == "profile" ]] && continue

    if package_profile_selected "$package_profile"; then
      if [[ -n "${nix_package:-}" ]]; then
        if ((${#SELECTED_NIX_ATTRS[@]} == 0)) || ! array_contains "$nix_package" "${SELECTED_NIX_ATTRS[@]}"; then
          SELECTED_NIX_ATTRS+=("$nix_package")
        fi
      fi

      if command_is_checkable "${command:-}"; then
        if ((${#SELECTED_COMMANDS[@]} == 0)) || ! array_contains "$command" "${SELECTED_COMMANDS[@]}"; then
          SELECTED_COMMANDS+=("$command")
        fi
      fi
    fi
  done < "$NIX_TSV"

  ((${#SELECTED_NIX_ATTRS[@]} > 0)) || die "no nixpkgs attributes selected for profile: $PROFILE"
}

load_package_map() {
  case "$BACKEND" in
    ubuntu)
      load_ubuntu_packages_from_tsv
      ;;
    debian)
      load_debian_packages_from_tsv
      ;;
    macos)
      load_macos_packages_from_tsv
      ;;
    fedora)
      load_fedora_packages_from_tsv
      ;;
    arch)
      load_arch_packages_from_tsv
      ;;
    rhel)
      load_rhel_packages_from_tsv
      ;;
    alpine)
      load_alpine_packages_from_tsv
      ;;
    nix)
      resolve_nix_release
      load_nix_packages_from_tsv
      ;;
    suse|centos)
      die "backend '$BACKEND' is planned but not implemented in v0; implemented backends: $IMPLEMENTED_BACKENDS; planned backends: $PLANNED_BACKENDS"
      ;;
    *)
      die "unknown backend for package loading: $BACKEND"
      ;;
  esac
}

filter_available_ubuntu_packages() {
  local package

  AVAILABLE_APT_PACKAGES=()

  log "checking Ubuntu package availability"

  for package in "${SELECTED_APT_PACKAGES[@]}"; do
    if apt-cache show "$package" >/dev/null 2>&1; then
      AVAILABLE_APT_PACKAGES+=("$package")
    else
      warn "skipping unavailable apt package: $package"
    fi
  done

  ((${#AVAILABLE_APT_PACKAGES[@]} > 0)) || die "no available apt packages remained for profile: $PROFILE"
}


install_ubuntu_packages() {
  log "selected profile: $PROFILE"
  log "selected apt packages: ${SELECTED_APT_PACKAGES[*]}"

  if (( DRY_RUN )); then
    log "dry-run: sudo apt update"
    log "dry-run: check apt availability for selected packages"
    log "dry-run: sudo DEBIAN_FRONTEND=noninteractive apt install -y ${SELECTED_APT_PACKAGES[*]}"
    return 0
  fi

  run_privileged apt update
  filter_available_ubuntu_packages

  log "available apt packages: ${AVAILABLE_APT_PACKAGES[*]}"
  run_privileged env DEBIAN_FRONTEND=noninteractive apt install -y "${AVAILABLE_APT_PACKAGES[@]}"
}

filter_available_debian_packages() {
  local package

  AVAILABLE_DEBIAN_APT_PACKAGES=()

  log "checking Debian package availability"

  for package in "${SELECTED_DEBIAN_APT_PACKAGES[@]}"; do
    if apt-cache show "$package" >/dev/null 2>&1; then
      AVAILABLE_DEBIAN_APT_PACKAGES+=("$package")
    else
      warn "skipping unavailable Debian apt package: $package"
    fi
  done

  ((${#AVAILABLE_DEBIAN_APT_PACKAGES[@]} > 0)) || die "no available Debian apt packages remained for profile: $PROFILE"
}

install_debian_packages() {
  log "selected profile: $PROFILE"
  log "selected Debian apt packages: ${SELECTED_DEBIAN_APT_PACKAGES[*]}"

  if (( DRY_RUN )); then
    log "dry-run: sudo apt update"
    log "dry-run: check Debian apt availability for selected packages"
    log "dry-run: sudo DEBIAN_FRONTEND=noninteractive apt install -y ${SELECTED_DEBIAN_APT_PACKAGES[*]}"
    return 0
  fi

  run_privileged apt update
  filter_available_debian_packages

  log "available Debian apt packages: ${AVAILABLE_DEBIAN_APT_PACKAGES[*]}"
  run_privileged env DEBIAN_FRONTEND=noninteractive apt install -y "${AVAILABLE_DEBIAN_APT_PACKAGES[@]}"
}

ensure_homebrew() {
  if command -v brew >/dev/null 2>&1; then
    return 0
  fi

  if (( DRY_RUN )); then
    log "dry-run: Homebrew is required for the macOS backend; would require brew before install"
    return 0
  fi

  die "Homebrew is required for the macOS backend, but brew was not found; install Homebrew manually and rerun"
}

filter_available_macos_packages() {
  local package

  AVAILABLE_BREW_PACKAGES=()

  log "checking Homebrew package availability"

  for package in "${SELECTED_BREW_PACKAGES[@]}"; do
    if brew info "$package" >/dev/null 2>&1; then
      AVAILABLE_BREW_PACKAGES+=("$package")
    else
      warn "skipping unavailable Homebrew package: $package"
    fi
  done

  ((${#AVAILABLE_BREW_PACKAGES[@]} > 0)) || die "no available Homebrew packages remained for profile: $PROFILE"
}

install_macos_packages() {
  log "selected profile: $PROFILE"
  log "selected Homebrew packages: ${SELECTED_BREW_PACKAGES[*]}"

  ensure_homebrew

  if (( DRY_RUN )); then
    log "dry-run: brew update"
    log "dry-run: check Homebrew availability for selected packages"
    log "dry-run: brew install ${SELECTED_BREW_PACKAGES[*]}"
    return 0
  fi

  brew update
  filter_available_macos_packages

  log "available Homebrew packages: ${AVAILABLE_BREW_PACKAGES[*]}"
  brew install "${AVAILABLE_BREW_PACKAGES[@]}"
}

ensure_dnf() {
  if command -v dnf >/dev/null 2>&1; then
    return 0
  fi

  die "dnf is required for this backend, but dnf was not found"
}

dnf_package_available() {
  local package="$1"

  if dnf repoquery --available "$package" >/dev/null 2>&1; then
    return 0
  fi

  if dnf list --available "$package" >/dev/null 2>&1; then
    return 0
  fi

  return 1
}

filter_available_fedora_packages() {
  local package

  AVAILABLE_DNF_PACKAGES=()

  log "checking Fedora package availability"

  for package in "${SELECTED_DNF_PACKAGES[@]}"; do
    if dnf_package_available "$package"; then
      AVAILABLE_DNF_PACKAGES+=("$package")
    else
      warn "skipping unavailable dnf package: $package"
    fi
  done

  ((${#AVAILABLE_DNF_PACKAGES[@]} > 0)) || die "no available dnf packages remained for profile: $PROFILE"
}

install_fedora_packages() {
  log "selected profile: $PROFILE"
  log "selected dnf packages: ${SELECTED_DNF_PACKAGES[*]}"

  if (( DRY_RUN )); then
    log "dry-run: sudo dnf makecache"
    log "dry-run: check dnf availability for selected packages"
    log "dry-run: sudo dnf install -y ${SELECTED_DNF_PACKAGES[*]}"
    return 0
  fi

  ensure_dnf
  run_privileged dnf makecache
  filter_available_fedora_packages

  log "available dnf packages: ${AVAILABLE_DNF_PACKAGES[*]}"
  run_privileged dnf install -y "${AVAILABLE_DNF_PACKAGES[@]}"
}

filter_available_rhel_packages() {
  local package

  AVAILABLE_RHEL_DNF_PACKAGES=()

  log "checking RHEL package availability"

  for package in "${SELECTED_RHEL_DNF_PACKAGES[@]}"; do
    if dnf_package_available "$package"; then
      AVAILABLE_RHEL_DNF_PACKAGES+=("$package")
    else
      warn "skipping unavailable RHEL dnf package: $package"
    fi
  done

  ((${#AVAILABLE_RHEL_DNF_PACKAGES[@]} > 0)) || die "no available RHEL dnf packages remained for profile: $PROFILE"
}

install_rhel_packages() {
  log "selected profile: $PROFILE"
  log "selected RHEL dnf packages: ${SELECTED_RHEL_DNF_PACKAGES[*]}"

  if (( DRY_RUN )); then
    log "dry-run: sudo dnf makecache"
    log "dry-run: check RHEL dnf availability for selected packages"
    log "dry-run: sudo dnf install -y ${SELECTED_RHEL_DNF_PACKAGES[*]}"
    return 0
  fi

  ensure_dnf
  run_privileged dnf makecache
  filter_available_rhel_packages

  log "available RHEL dnf packages: ${AVAILABLE_RHEL_DNF_PACKAGES[*]}"
  run_privileged dnf install -y "${AVAILABLE_RHEL_DNF_PACKAGES[@]}"
}

ensure_pacman() {
  if command -v pacman >/dev/null 2>&1; then
    return 0
  fi

  die "pacman is required for the Arch backend, but pacman was not found"
}

filter_available_arch_packages() {
  local package

  AVAILABLE_PACMAN_PACKAGES=()

  log "checking Arch package availability in official pacman repositories"

  for package in "${SELECTED_PACMAN_PACKAGES[@]}"; do
    if pacman -Si "$package" >/dev/null 2>&1; then
      AVAILABLE_PACMAN_PACKAGES+=("$package")
    else
      warn "skipping unavailable pacman package: $package"
    fi
  done

  ((${#AVAILABLE_PACMAN_PACKAGES[@]} > 0)) || die "no available pacman packages remained for profile: $PROFILE"
}

install_arch_packages() {
  log "selected profile: $PROFILE"
  log "selected pacman packages: ${SELECTED_PACMAN_PACKAGES[*]}"

  if (( DRY_RUN )); then
    log "dry-run: sudo pacman -Sy"
    log "dry-run: check pacman availability in official repos for selected packages"
    log "dry-run: sudo pacman -S --needed --noconfirm ${SELECTED_PACMAN_PACKAGES[*]}"
    return 0
  fi

  ensure_pacman
  run_privileged pacman -Sy
  filter_available_arch_packages

  log "available pacman packages: ${AVAILABLE_PACMAN_PACKAGES[*]}"
  run_privileged pacman -S --needed --noconfirm "${AVAILABLE_PACMAN_PACKAGES[@]}"
}

ensure_apk() {
  if command -v apk >/dev/null 2>&1; then
    return 0
  fi

  die "apk is required for the Alpine backend, but apk was not found"
}

filter_available_alpine_packages() {
  local package

  AVAILABLE_APK_PACKAGES=()

  log "checking Alpine package availability"

  for package in "${SELECTED_APK_PACKAGES[@]}"; do
    if apk search -e "$package" >/dev/null 2>&1; then
      AVAILABLE_APK_PACKAGES+=("$package")
    else
      warn "skipping unavailable apk package: $package"
    fi
  done

  ((${#AVAILABLE_APK_PACKAGES[@]} > 0)) || die "no available apk packages remained for profile: $PROFILE"
}

install_alpine_packages() {
  log "selected profile: $PROFILE"
  log "selected apk packages: ${SELECTED_APK_PACKAGES[*]}"

  if (( DRY_RUN )); then
    log "dry-run: sudo apk update"
    log "dry-run: check apk availability for selected packages"
    log "dry-run: sudo apk add ${SELECTED_APK_PACKAGES[*]}"
    return 0
  fi

  ensure_apk
  run_privileged apk update
  filter_available_alpine_packages

  log "available apk packages: ${AVAILABLE_APK_PACKAGES[*]}"
  run_privileged apk add "${AVAILABLE_APK_PACKAGES[@]}"
}

ensure_nix() {
  command -v nix-env >/dev/null 2>&1 \
    || die "nix-env is required for the nix backend, but nix-env was not found"
  command -v nix-instantiate >/dev/null 2>&1 \
    || die "nix-instantiate is required for the nix backend, but nix-instantiate was not found"
}

nix_attr_filter_expr() {
  printf 'let\n'
  printf '  pkgs = import <nixpkgs> { };\n'
  printf '  lib = pkgs.lib;\n'
  printf '  has = path:\n'
  printf '    let probe = builtins.tryEval (lib.attrByPath (lib.splitString "." path) null pkgs);\n'
  printf '    in probe.success && probe.value != null;\n'
  printf '  wanted = [\n'
  printf '    "%s"\n' "${SELECTED_NIX_ATTRS[@]}"
  printf '  ];\n'
  printf 'in builtins.concatStringsSep "\\n" (builtins.filter has wanted)\n'
}

filter_available_nix_attrs() {
  local output attr

  AVAILABLE_NIX_ATTRS=()

  log "checking nixpkgs attribute availability"

  # One evaluation resolves every attribute path, including dotted ones such as
  # linuxPackages.perf; per-attribute queries would re-evaluate nixpkgs.
  if ! output="$(nix-instantiate --eval --raw --expr "$(nix_attr_filter_expr)" 2>/dev/null)"; then
    warn "could not evaluate <nixpkgs>; installing the selected attributes without pre-filtering"
    AVAILABLE_NIX_ATTRS=("${SELECTED_NIX_ATTRS[@]}")
    return 0
  fi

  while IFS= read -r attr; do
    [[ -n "$attr" ]] && AVAILABLE_NIX_ATTRS+=("$attr")
  done <<< "$output"

  for attr in "${SELECTED_NIX_ATTRS[@]}"; do
    if ((${#AVAILABLE_NIX_ATTRS[@]} == 0)) || ! array_contains "$attr" "${AVAILABLE_NIX_ATTRS[@]}"; then
      warn "skipping nixpkgs attribute missing from $NIX_CHANNEL: $attr"
    fi
  done

  ((${#AVAILABLE_NIX_ATTRS[@]} > 0)) || die "no available nixpkgs attributes remained for profile: $PROFILE"
}

install_nix_packages() {
  local attr

  log "selected profile: $PROFILE"
  log "selected nixpkgs attributes: ${SELECTED_NIX_ATTRS[*]}"

  if (( DRY_RUN )); then
    log "dry-run: nix-channel --update"
    log "dry-run: check <nixpkgs> attribute availability for selected attributes"
    log "dry-run: nix-env -f <nixpkgs> -iA ${SELECTED_NIX_ATTRS[*]}"
    return 0
  fi

  ensure_nix

  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    warn "running as root; nix-env installs into the root profile, not a user profile"
  fi

  nix-channel --update || warn "nix-channel --update failed; continuing with the current <nixpkgs>"

  filter_available_nix_attrs
  log "available nixpkgs attributes: ${AVAILABLE_NIX_ATTRS[*]}"

  if nix-env -f '<nixpkgs>' -iA "${AVAILABLE_NIX_ATTRS[@]}"; then
    return 0
  fi

  # A single file collision (coreutils vs util-linux, gcc vs clang) aborts the
  # whole batch, so retry per attribute and report what did not apply.
  warn "batch nix-env install failed; retrying one attribute at a time"

  for attr in "${AVAILABLE_NIX_ATTRS[@]}"; do
    nix-env -f '<nixpkgs>' -iA "$attr" \
      || warn "skipping nixpkgs attribute that failed to install: $attr"
  done
}

install_packages() {
  case "$BACKEND" in
    ubuntu)
      install_ubuntu_packages
      ;;
    debian)
      install_debian_packages
      ;;
    macos)
      install_macos_packages
      ;;
    fedora)
      install_fedora_packages
      ;;
    arch)
      install_arch_packages
      ;;
    rhel)
      install_rhel_packages
      ;;
    alpine)
      install_alpine_packages
      ;;
    nix)
      install_nix_packages
      ;;
    suse|centos)
      die "backend '$BACKEND' is planned but not implemented yet; implemented backends: $IMPLEMENTED_BACKENDS; planned backends: $PLANNED_BACKENDS"
      ;;
    *)
      die "unknown backend for ${OS_NAME} ${OS_VERSION_ID}; implemented backends: $IMPLEMENTED_BACKENDS; planned backends: $PLANNED_BACKENDS"
      ;;
  esac
}

setup_user_dirs() {
  local dirs=(
    "$HOME/.local/bin"
    "$HOME/.config"
    "$HOME/workspace"
    "$HOME/repos"
    "$HOME/scratch"
  )

  if [[ "$BACKEND" == "macos" ]]; then
    dirs+=("$HOME/.zshrc.d")
  else
    dirs+=("$HOME/.bashrc.d")
  fi

  log "creating user directories"

  if (( DRY_RUN )); then
    printf '[alp-bootstrap] dry-run: mkdir -p'
    printf ' %q' "${dirs[@]}"
    printf '\n'
    return 0
  fi

  mkdir -p "${dirs[@]}"
}

setup_debian_family_compat_symlinks() {
  log "setting up Debian-family fd/bat compatibility symlinks"

  if [[ -x /usr/bin/fdfind && ! -e "$HOME/.local/bin/fd" ]]; then
    if (( DRY_RUN )); then
      log "dry-run: ln -s /usr/bin/fdfind $HOME/.local/bin/fd"
    else
      ln -s /usr/bin/fdfind "$HOME/.local/bin/fd"
    fi
  fi

  if [[ -x /usr/bin/batcat && ! -e "$HOME/.local/bin/bat" ]]; then
    if (( DRY_RUN )); then
      log "dry-run: ln -s /usr/bin/batcat $HOME/.local/bin/bat"
    else
      ln -s /usr/bin/batcat "$HOME/.local/bin/bat"
    fi
  fi
}

setup_bashrc_loader() {
  local bashrc="$HOME/.bashrc"
  local marker_begin="# >>> alp-linux-bootstrap bashrc.d loader >>>"
  local marker_end="# <<< alp-linux-bootstrap bashrc.d loader <<<"

  log "ensuring ~/.bashrc has the alp bashrc.d loader"

  if [[ -f "$bashrc" ]] && grep -Fqx "$marker_begin" "$bashrc"; then
    log "bashrc loader already present"
    return 0
  fi

  if (( DRY_RUN )); then
    log "dry-run: append marked bashrc.d loader block to $bashrc"
    return 0
  fi

  {
    printf '\n%s\n' "$marker_begin"
    printf 'if [ -d "$HOME/.bashrc.d" ]; then\n'
    printf '  for alp_bashrc_snippet in "$HOME"/.bashrc.d/*.sh; do\n'
    printf '    [ -r "$alp_bashrc_snippet" ] && . "$alp_bashrc_snippet"\n'
    printf '  done\n'
    printf '  unset alp_bashrc_snippet\n'
    printf 'fi\n'
    printf '%s\n' "$marker_end"
  } >> "$bashrc"
}

setup_bash_qol() {
  local aliases_file="$HOME/.bashrc.d/10-alp-aliases.sh"

  log "writing conservative bash aliases"

  if (( DRY_RUN )); then
    log "dry-run: write $aliases_file"
    return 0
  fi

  cat > "$aliases_file" <<'ALIASES'
# alp-linux-bootstrap: conservative keyboard-first aliases
alias ll='ls -alF'
alias la='ls -A'
alias v='vim'
alias gs='git status --short --branch'
alias ports='ss -tulpn'
alias mem='free -h'
alias dfh='df -h'
ALIASES
}

setup_zshrc_loader() {
  local zshrc="$HOME/.zshrc"
  local marker_begin="# >>> alp-linux-bootstrap zshrc.d loader >>>"
  local marker_end="# <<< alp-linux-bootstrap zshrc.d loader <<<"

  log "ensuring ~/.zshrc has the alp zshrc.d loader"

  if [[ -f "$zshrc" ]] && grep -Fqx "$marker_begin" "$zshrc"; then
    log "zshrc loader already present"
    return 0
  fi

  if (( DRY_RUN )); then
    log "dry-run: append marked zshrc.d loader block to $zshrc"
    return 0
  fi

  {
    printf '\n%s\n' "$marker_begin"
    printf 'if [ -d "$HOME/.zshrc.d" ]; then\n'
    printf '  for alp_zshrc_snippet in "$HOME"/.zshrc.d/*.zsh(N); do\n'
    printf '    [ -r "$alp_zshrc_snippet" ] && . "$alp_zshrc_snippet"\n'
    printf '  done\n'
    printf '  unset alp_zshrc_snippet\n'
    printf 'fi\n'
    printf '%s\n' "$marker_end"
  } >> "$zshrc"
}

setup_zsh_qol() {
  local aliases_file="$HOME/.zshrc.d/10-alp-aliases.zsh"
  local starship_file="$HOME/.zshrc.d/20-starship.zsh"

  log "writing conservative zsh aliases"

  if (( DRY_RUN )); then
    log "dry-run: write $aliases_file"
    log "dry-run: write $starship_file only if starship is available"
    return 0
  fi

  cat > "$aliases_file" <<'ALIASES'
# alp-linux-bootstrap: conservative macOS zsh aliases
alias ll='ls -lah'
alias la='ls -A'
alias v='vim'
alias gs='git status --short'
alias ports='lsof -nP -iTCP -sTCP:LISTEN'
alias mem='vm_stat'
alias dfh='df -h'
ALIASES

  if command -v starship >/dev/null 2>&1; then
    cat > "$starship_file" <<'STARSHIP'
# alp-linux-bootstrap: optional starship init for zsh
eval "$(starship init zsh)"
STARSHIP
  fi
}

apply_macos_defaults() {
  log "applying conservative macOS defaults"

  if (( DRY_RUN )); then
    log "dry-run: defaults write com.apple.finder ShowPathbar -bool true"
    log "dry-run: defaults write com.apple.finder ShowStatusBar -bool true"
    log "dry-run: mkdir -p $HOME/Screenshots"
    log "dry-run: defaults write com.apple.screencapture location $HOME/Screenshots"
    log "dry-run: defaults write NSGlobalDomain InitialKeyRepeat -int 20"
    log "dry-run: defaults write NSGlobalDomain KeyRepeat -int 3"
    log "dry-run: Finder restart may be needed later; v0 does not force kill Finder"
    return 0
  fi

  defaults write com.apple.finder ShowPathbar -bool true
  defaults write com.apple.finder ShowStatusBar -bool true
  mkdir -p "$HOME/Screenshots"
  defaults write com.apple.screencapture location "$HOME/Screenshots"
  defaults write NSGlobalDomain InitialKeyRepeat -int 20
  defaults write NSGlobalDomain KeyRepeat -int 3
  warn "Finder restart may be needed for Finder defaults to appear; v0 does not force kill Finder"
}

write_check_script() {
  local command

  log "writing check script: $CHECK_SCRIPT"

  if (( DRY_RUN )); then
    log "dry-run: write $CHECK_SCRIPT for commands: ${SELECTED_COMMANDS[*]}"
    return 0
  fi

  {
    printf '#!/usr/bin/env bash\n'
    printf 'set -Eeuo pipefail\n\n'
    printf 'commands=(\n'
    for command in "${SELECTED_COMMANDS[@]}"; do
      printf '  %q\n' "$command"
    done
    printf ')\n\n'
    printf 'for cmd in "${commands[@]}"; do\n'
    printf '  if command -v "$cmd" >/dev/null 2>&1; then\n'
    printf '    printf "present %%s -> %%s\\n" "$cmd" "$(command -v "$cmd")"\n'
    printf '  else\n'
    printf '    printf "missing %%s\\n" "$cmd"\n'
    printf '  fi\n'
    printf 'done\n'
  } > "$CHECK_SCRIPT"

  chmod +x "$CHECK_SCRIPT"
}

main() {
  parse_args "$@"
  detect_os
  select_backend
  require_supported_backend
  resolve_profile_groups

  log "detected: ${OS_NAME} ${OS_VERSION_ID} (${OS_ID}, ${OS_ARCH}); backend: $BACKEND"
  log "profile: $PROFILE; package groups: ${SELECTED_GROUPS[*]}"

  if (( ADD_JAVA )); then
    if [[ "$JAVA_FLAG_SOURCE" == "--with-java" ]]; then
      warn "--with-java is a deprecated alias for --add-java"
    fi
    warn "Java/JVM opt-in is reserved but not implemented yet; no Java packages will be installed"
  elif (( NO_JAVA )); then
    log "Java/JVM tooling excluded by default"
  fi

  load_package_map
  install_packages
  setup_user_dirs

  case "$BACKEND" in
    ubuntu)
      setup_debian_family_compat_symlinks
      setup_bashrc_loader
      setup_bash_qol
      ;;
    debian)
      setup_debian_family_compat_symlinks
      setup_bashrc_loader
      setup_bash_qol
      ;;
    fedora)
      setup_bashrc_loader
      setup_bash_qol
      ;;
    arch)
      setup_bashrc_loader
      setup_bash_qol
      ;;
    rhel)
      setup_bashrc_loader
      setup_bash_qol
      ;;
    alpine)
      setup_bashrc_loader
      setup_bash_qol
      ;;
    nix)
      setup_bashrc_loader
      setup_bash_qol
      ;;
    macos)
      setup_zshrc_loader
      setup_zsh_qol
      apply_macos_defaults
      ;;
  esac

  write_check_script

  log "done"
  log "run check script with: $CHECK_SCRIPT"
}

main "$@"
