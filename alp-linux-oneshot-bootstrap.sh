#!/usr/bin/env bash
set -Eeuo pipefail

DEFAULT_PROFILE="alp-heavy"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
UBUNTU_TSV="$SCRIPT_DIR/packages/ubuntu.tsv"
CHECK_SCRIPT="/tmp/check-alp-bootstrap-tools.sh"
PLANNED_BACKENDS="ubuntu, debian, fedora, arch, alpine, suse, rhel, centos, macos"

DRY_RUN=0
PROFILE="$DEFAULT_PROFILE"
NO_JAVA=1
WITH_JAVA=0

OS_ID=""
OS_NAME=""
OS_VERSION_ID=""
OS_ARCH=""
OS_KERNEL=""
BACKEND=""

SELECTED_APT_PACKAGES=()
AVAILABLE_APT_PACKAGES=()
SELECTED_COMMANDS=()

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

usage() {
  cat <<'USAGE'
Usage: ./alp-linux-oneshot-bootstrap.sh [options]

Options:
  --dry-run          Print packages and actions without applying them.
  --profile <name>  Select profile to install. Default: alp-heavy.
  --no-java         Keep Java/JVM tooling excluded. Default.
  --with-java       Explicit Java opt-in placeholder; does not install Java.
  --help            Show this help.

Current implementation is Ubuntu-first. Planned backend families are named, but only Ubuntu installs packages in v0.
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
  if [[ "$BACKEND" == "ubuntu" ]]; then
    return 0
  fi

  if (( DRY_RUN )); then
    warn "dry-run on ${OS_NAME} ${OS_VERSION_ID}: backend '$BACKEND' is planned but not implemented; previewing Ubuntu-first package plan only"
    return 0
  fi

  die "backend '$BACKEND' for ${OS_NAME} ${OS_VERSION_ID} is planned but not implemented in v0; implemented backend: ubuntu; planned backends: $PLANNED_BACKENDS"
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
        WITH_JAVA=0
        shift
        ;;
      --with-java)
        WITH_JAVA=1
        NO_JAVA=0
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

package_profile_selected() {
  local package_profile="$1"

  if [[ "$PROFILE" == "alp-heavy" ]]; then
    case "$package_profile" in
      core|server|terminal-ux|dev-c|rust|go|zig|python|containers|networking|security-lite|debugging|embedded-lite)
        return 0
        ;;
      *)
        return 1
        ;;
    esac
  fi

  case "$package_profile" in
    core|server|terminal-ux)
      return 0
      ;;
    "$PROFILE")
      return 0
      ;;
    *)
      return 1
      ;;
  esac
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

load_packages_from_tsv() {
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

      if [[ -n "${command:-}" ]]; then
        if ((${#SELECTED_COMMANDS[@]} == 0)) || ! array_contains "$command" "${SELECTED_COMMANDS[@]}"; then
          SELECTED_COMMANDS+=("$command")
        fi
      fi
    fi
  done < "$UBUNTU_TSV"

  ((${#SELECTED_APT_PACKAGES[@]} > 0)) || die "no apt packages selected for profile: $PROFILE"
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

  sudo apt update
  filter_available_ubuntu_packages

  log "available apt packages: ${AVAILABLE_APT_PACKAGES[*]}"
  sudo DEBIAN_FRONTEND=noninteractive apt install -y "${AVAILABLE_APT_PACKAGES[@]}"
}

install_packages() {
  case "$BACKEND" in
    ubuntu)
      install_ubuntu_packages
      ;;
    debian|fedora|arch|alpine|suse|rhel|centos|macos)
      if (( DRY_RUN )); then
        log "dry-run: backend '$BACKEND' is not implemented yet; Ubuntu package map is being shown as the current v0 plan"
        log "dry-run: selected profile: $PROFILE"
        log "dry-run: selected Ubuntu-first packages: ${SELECTED_APT_PACKAGES[*]}"
        log "dry-run: stopping before local Ubuntu-specific user configuration actions on non-Ubuntu host"
        exit 0
      fi
      die "backend '$BACKEND' is planned but not implemented yet; planned backends: $PLANNED_BACKENDS"
      ;;
    *)
      die "unknown backend for ${OS_NAME} ${OS_VERSION_ID}; planned backends: $PLANNED_BACKENDS"
      ;;
  esac
}

setup_user_dirs() {
  local dirs=(
    "$HOME/.local/bin"
    "$HOME/.bashrc.d"
    "$HOME/.config"
    "$HOME/workspace"
    "$HOME/repos"
    "$HOME/scratch"
  )

  log "creating user directories"

  if (( DRY_RUN )); then
    printf '[alp-bootstrap] dry-run: mkdir -p'
    printf ' %q' "${dirs[@]}"
    printf '\n'
    return 0
  fi

  mkdir -p "${dirs[@]}"
}

setup_ubuntu_compat_symlinks() {
  log "setting up Ubuntu fd/bat compatibility symlinks"

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

  log "detected: ${OS_NAME} ${OS_VERSION_ID} (${OS_ID}, ${OS_ARCH}); backend: $BACKEND"

  if (( WITH_JAVA )); then
    warn "Java is intentionally opt-in and not implemented in this skeleton; no Java packages will be installed"
  elif (( NO_JAVA )); then
    log "Java/JVM tooling excluded by default"
  fi

  load_packages_from_tsv
  install_packages
  setup_user_dirs
  setup_ubuntu_compat_symlinks
  setup_bashrc_loader
  setup_bash_qol
  write_check_script

  log "done"
  log "run check script with: $CHECK_SCRIPT"
}

main "$@"
