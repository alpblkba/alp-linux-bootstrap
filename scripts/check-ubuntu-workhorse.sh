#!/usr/bin/env bash
set -u

MISSING_COMMANDS=0
PYTHON_READY=0
DOCKER_READY=0

section() {
  printf '\n== %s ==\n' "$*"
}

ok() {
  printf 'OK      %s\n' "$*"
}

warn() {
  printf 'WARN    %s\n' "$*"
}

missing() {
  printf 'MISSING %s\n' "$*"
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

check_cmd() {
  local cmd="$1"

  if have_cmd "$cmd"; then
    ok "$cmd -> $(command -v "$cmd")"
  else
    missing "$cmd"
    MISSING_COMMANDS=$((MISSING_COMMANDS + 1))
  fi
}

check_one_of() {
  local label="$1"
  shift
  local cmd

  for cmd in "$@"; do
    if have_cmd "$cmd"; then
      ok "$label -> $cmd ($(command -v "$cmd"))"
      return 0
    fi
  done

  missing "$label (${*})"
  MISSING_COMMANDS=$((MISSING_COMMANDS + 1))
  return 1
}

check_path() {
  local path="$1"

  if [[ -e "$path" ]]; then
    ok "$path"
  else
    missing "$path"
  fi
}

section_system() {
  section "system"
  uname -a || true
  if [[ -r /etc/os-release ]]; then
    sed -n 's/^PRETTY_NAME=//p' /etc/os-release | tr -d '"'
  fi
}

section_resources() {
  section "resources"
  free -h || true
  df -hT / || true
}

section_apt_health() {
  section "apt health"
  dpkg --audit || true
  apt-get check || true
}

section_bootstrap_files() {
  section "bootstrap managed files"
  check_path "$HOME/.local/bin"
  check_path "$HOME/.bashrc.d"
  check_path "$HOME/.bashrc.d/10-alp-aliases.sh"
  check_path "$HOME/.config"
  check_path "$HOME/workspace"
  check_path "$HOME/repos"
  check_path "$HOME/scratch"
  check_path /tmp/check-alp-bootstrap-tools.sh
}

section_core_commands() {
  local commands=(
    bash
    curl
    wget
    git
    gpg
    make
    gcc
    g++
    pkg-config
    unzip
    zip
    tar
    rsync
    ssh
    sshd
    htop
    tmux
    tree
    jq
    yq
    shellcheck
    rg
    fzf
    zoxide
    direnv
    starship
    zellij
    cmake
    ninja
    gdb
    lldb
    clang
    clang-format
    valgrind
    rustup
    cargo
    rustc
    go
    zig
    python3
    pip3
    pipx
    docker
    podman
    buildah
    skopeo
    dig
    netstat
    ip
    traceroute
    mtr
    nmap
    tcpdump
    whois
    socat
    nc
    ufw
    fail2ban-client
    age
    pass
    strace
    ltrace
    perf
    bpftrace
    iostat
    lsof
    avrdude
    openocd
    arm-none-eabi-gcc
    gdb-multiarch
  )
  local cmd

  section "core commands"
  for cmd in "${commands[@]}"; do
    check_cmd "$cmd"
  done

  check_one_of fd fd fdfind
  check_one_of bat bat batcat

  if have_cmd docker-compose; then
    ok "docker-compose -> $(command -v docker-compose)"
  elif have_cmd docker && docker compose version >/dev/null 2>&1; then
    ok "docker-compose -> docker compose plugin"
  else
    missing "docker-compose or docker compose plugin"
    MISSING_COMMANDS=$((MISSING_COMMANDS + 1))
  fi
}

section_versions() {
  section "versions"
  python3 --version 2>/dev/null || true
  docker --version 2>/dev/null || true
  node --version 2>/dev/null || true
  npm --version 2>/dev/null || true
  npx --version 2>/dev/null || true
}

section_python_readiness() {
  section "Python readiness"

  if ! have_cmd python3; then
    missing "python3"
    return 0
  fi

  if python3 - <<'PY'
import sys
raise SystemExit(0 if sys.version_info >= (3, 12) else 1)
PY
  then
    ok "python3 >= 3.12"
    PYTHON_READY=1
  else
    warn "python3 is older than 3.12"
  fi
}

section_container_runtime() {
  section "container runtime"

  if ! have_cmd docker; then
    missing "docker"
    return 0
  fi

  if docker info >/dev/null 2>&1; then
    ok "Docker daemon usable"
    DOCKER_READY=1
  else
    warn "Docker command exists but daemon is not usable by this session"
  fi
}

section_verdict() {
  section "verdict"

  if (( MISSING_COMMANDS == 0 )); then
    ok "Bootstrap coverage: rough OK"
  else
    warn "Bootstrap coverage: $MISSING_COMMANDS missing command checks"
  fi
}

main() {
  section_system
  section_resources
  section_apt_health
  section_bootstrap_files
  section_core_commands
  section_versions
  section_python_readiness
  section_container_runtime
  section_verdict
}

main "$@"
