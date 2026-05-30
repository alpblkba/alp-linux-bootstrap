#!/usr/bin/env bash
set -Eeuo pipefail

log() {
  printf '[alp-workhorse] %s\n' "$*"
}

warn() {
  printf '[alp-workhorse] warning: %s\n' "$*" >&2
}

die() {
  printf '[alp-workhorse] error: %s\n' "$*" >&2
  exit 1
}

require_ubuntu() {
  if [[ ! -r /etc/os-release ]]; then
    die "cannot detect OS; /etc/os-release is missing"
  fi

  # shellcheck disable=SC1091
  . /etc/os-release

  [[ "${ID:-}" == "ubuntu" ]] || die "this script is Ubuntu-specific; detected ID=${ID:-unknown}"
}

target_user() {
  printf '%s\n' "${SUDO_USER:-${USER:-$(id -un)}}"
}

target_home() {
  local user="$1"
  local home

  home="$(getent passwd "$user" | cut -d: -f6 || true)"
  [[ -n "$home" ]] || home="$HOME"
  printf '%s\n' "$home"
}

install_workhorse_packages() {
  local packages=(
    ca-certificates
    curl
    wget
    git
    tmux
    htop
    btop
    iotop
    iftop
    nethogs
    ncdu
    duf
    lsof
    sysstat
    plocate
    chrony
    unattended-upgrades
    apt-listchanges
    needrestart
    logrotate
    acl
    tree
    jq
    yq
    ripgrep
    fd-find
    bat
    fzf
    zoxide
    direnv
    shellcheck
    shfmt
    strace
    ltrace
    gdb
    valgrind
    tcpdump
    nmap
    mtr-tiny
    dnsutils
    net-tools
    iproute2
    traceroute
    whois
    socat
    netcat-openbsd
  )

  log "installing Ubuntu workhorse packages"
  sudo apt install -y "${packages[@]}"
}

write_user_shell_files() {
  local user="$1"
  local home="$2"
  local bashrcd="$home/.bashrc.d"
  local localbin="$home/.local/bin"

  log "writing managed bash snippets for $user"
  install -d -m 0755 "$localbin" "$bashrcd"

  cat > "$bashrcd/00-path.sh" <<'EOF'
# alp-linux-bootstrap: user local bin
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) PATH="$HOME/.local/bin:$PATH" ;;
esac
export PATH
EOF

  cat > "$bashrcd/20-history.sh" <<'EOF'
# alp-linux-bootstrap: bash history quality-of-life
export HISTCONTROL=ignoreboth:erasedups
export HISTSIZE=50000
export HISTFILESIZE=100000
shopt -s histappend
PROMPT_COMMAND="history -a; history -c; history -r${PROMPT_COMMAND:+; $PROMPT_COMMAND}"
EOF

  cat > "$bashrcd/30-tools.sh" <<'EOF'
# alp-linux-bootstrap: optional interactive tool hooks
command -v zoxide >/dev/null 2>&1 && eval "$(zoxide init bash)"
command -v direnv >/dev/null 2>&1 && eval "$(direnv hook bash)"
if command -v fzf >/dev/null 2>&1; then
  [ -r /usr/share/doc/fzf/examples/key-bindings.bash ] && . /usr/share/doc/fzf/examples/key-bindings.bash
  [ -r /usr/share/doc/fzf/examples/completion.bash ] && . /usr/share/doc/fzf/examples/completion.bash
fi
EOF

  chown "$user":"$user" "$bashrcd/00-path.sh" "$bashrcd/20-history.sh" "$bashrcd/30-tools.sh" "$localbin" "$bashrcd" || warn "could not chown all user shell files"
}

setup_debian_family_symlinks() {
  local user="$1"
  local home="$2"
  local localbin="$home/.local/bin"

  log "setting up fd/bat compatibility symlinks"
  install -d -m 0755 "$localbin"

  if [[ -x /usr/bin/fdfind && ! -e "$localbin/fd" ]]; then
    ln -s /usr/bin/fdfind "$localbin/fd"
  fi

  if [[ -x /usr/bin/batcat && ! -e "$localbin/bat" ]]; then
    ln -s /usr/bin/batcat "$localbin/bat"
  fi

  chown -h "$user":"$user" "$localbin/fd" "$localbin/bat" 2>/dev/null || true
}

enable_sysstat() {
  if [[ -f /etc/default/sysstat ]]; then
    log "enabling sysstat collection"
    sudo sed -i 's/^ENABLED=.*/ENABLED="true"/' /etc/default/sysstat
  fi

  if command -v systemctl >/dev/null 2>&1; then
    sudo systemctl enable --now sysstat || warn "could not enable sysstat"
  fi
}

enable_chrony() {
  if command -v systemctl >/dev/null 2>&1; then
    log "enabling chrony"
    sudo systemctl enable --now chrony || warn "could not enable chrony"
  fi
}

update_plocate() {
  if command -v updatedb >/dev/null 2>&1; then
    log "updating plocate database"
    sudo updatedb || warn "updatedb failed"
  fi
}

check_docker() {
  local user="$1"

  if ! command -v docker >/dev/null 2>&1; then
    warn "docker command not found; skipping Docker service check"
    return 0
  fi

  if command -v systemctl >/dev/null 2>&1; then
    log "enabling Docker service if available"
    sudo systemctl enable --now docker || warn "could not enable Docker"
  fi

  if id -nG "$user" | tr ' ' '\n' | grep -Fxq docker; then
    log "user $user is in docker group"
  else
    warn "user $user is not in docker group; docker may require sudo until group membership is fixed"
  fi

  docker info >/dev/null 2>&1 || warn "docker daemon is not usable by current session"
}

configure_unattended_upgrades() {
  log "configuring unattended-upgrades"
  sudo dpkg-reconfigure -f noninteractive unattended-upgrades || warn "unattended-upgrades reconfigure failed"
}

print_summary() {
  log "final summary"
  uname -a || true
  free -h || true
  df -hT / || true

  if command -v systemctl >/dev/null 2>&1; then
    systemctl --failed || true
  fi

  if command -v needrestart >/dev/null 2>&1; then
    needrestart -r a || true
  fi
}

main() {
  local user home

  require_ubuntu
  sudo -v

  user="$(target_user)"
  home="$(target_home "$user")"

  log "running apt health steps"
  sudo dpkg --configure -a
  sudo apt -f install -y
  sudo apt update
  sudo apt full-upgrade -y

  install_workhorse_packages
  write_user_shell_files "$user" "$home"
  setup_debian_family_symlinks "$user" "$home"
  enable_sysstat
  enable_chrony
  update_plocate
  check_docker "$user"
  configure_unattended_upgrades
  print_summary

  log "done. reboot is recommended if a new kernel was installed or needrestart reported a pending kernel upgrade."
}

main "$@"
