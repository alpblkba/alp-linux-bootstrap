# alp-linux-bootstrap

This is my own bootstrap repository for setting up Linux and macOS machines.

It installs packages, creates a small directory layout, adds conservative shell
helpers, and keeps package lists split by platform. The current working backends
are Ubuntu, Debian, Fedora, Arch, RHEL, Alpine, and macOS. Other distributions are
planned but not implemented yet.

It is a setup script that should stay readable enough to review, edit, and run
again.

## Current Status

- Ubuntu backend: apt package install, bash setup, and Ubuntu compatibility
  symlinks for tools such as `fd` and `bat`.
- Debian backend: apt package install, bash setup, and Debian-family
  compatibility symlinks for tools such as `fd` and `bat`.
- Fedora backend: dnf package install and bash setup.
- Arch backend: pacman package install and bash setup.
- RHEL backend: dnf package install and bash setup.
- Alpine backend: apk package install and bash setup.
- macOS backend: Homebrew package install, zsh setup, and conservative macOS
  defaults.
- Other backends: named/planned stubs only.
- GUI/rice: not in the default path.

The project is still early. Review the script and package maps before running a
real install.

Package maps are also early. Some apt, dnf, pacman, and Homebrew packages may
be unavailable on a given OS version or enabled repository set; the script
filters unavailable packages before real installs where practical.

## Usage

Ubuntu:

```bash
./alp-linux-oneshot-bootstrap.sh --dry-run
./alp-linux-oneshot-bootstrap.sh --profile alp-heavy
```

Debian:

```bash
./alp-linux-oneshot-bootstrap.sh --dry-run
./alp-linux-oneshot-bootstrap.sh --profile alp-heavy
```

macOS:

```bash
./alp-linux-oneshot-bootstrap.sh --dry-run
./alp-linux-oneshot-bootstrap.sh --profile alp-heavy
```

Fedora:

```bash
./alp-linux-oneshot-bootstrap.sh --dry-run
./alp-linux-oneshot-bootstrap.sh --profile alp-heavy
```

Arch:

```bash
./alp-linux-oneshot-bootstrap.sh --dry-run
./alp-linux-oneshot-bootstrap.sh --profile alp-heavy
```

RHEL:

```bash
./alp-linux-oneshot-bootstrap.sh --dry-run
./alp-linux-oneshot-bootstrap.sh --profile alp-heavy
```

Alpine:

```bash
./alp-linux-oneshot-bootstrap.sh --dry-run
./alp-linux-oneshot-bootstrap.sh --profile alp-heavy
```

Useful flags:

- `--dry-run` - print what would happen.
- `--profile <name>` - choose a profile. Default: `alp-heavy`.
- `--no-java` - keep Java/JVM tooling excluded. Default.
- `--add-java` - reserved opt-in placeholder; Java is not implemented yet.
- `--with-java` - deprecated alias for `--add-java`.
- `--help` - show script help.

## Supported and planned systems

Implemented now:

- Ubuntu: real apt install path.
- Debian: real apt install path.
- Fedora: real dnf install path.
- Arch: real pacman install path using official repositories only.
- RHEL: real dnf install path for RHEL-style repositories.
- Alpine: real apk install path.
- macOS: real Homebrew install path, assuming Homebrew is already installed.

Backends are currently family-based, not version-specific.

Debian and Ubuntu both use apt, but they have separate package maps.
Debian-family systems use compatibility symlinks for `fd` and `bat` command
names where needed.

Arch support does not include AUR helpers. No `yay`, `paru`, or AUR packages are
installed in v0.

RHEL support is repository-dependent. The script does not register RHEL systems,
run `subscription-manager`, or enable EPEL in v0.

Alpine support uses apk and does not enable edge repositories in v0. Package
availability depends on enabled repositories and architecture.

Planned backend families:

- CentOS
- openSUSE/SUSE

Longer-term target list:

- macOS current and recent versions
- Ubuntu 20-26, Server/Desktop/Core where possible
- Debian latest 1-2 releases
- Fedora 40+
- Arch rolling/recent
- Alpine latest 1-2
- RHEL 7/8/9
- CentOS 7/8
- openSUSE/SUSE latest, initially openSUSE Tumbleweed
- experimental OSes later, if useful

WSL support should be enough to avoid breaking, not a separate WSL-first setup.

## Profiles

The default profile is `alp-heavy`.

Implemented package groups:

- `core`
- `server`
- `terminal-ux`
- `dev-c`
- `rust`
- `go`
- `zig`
- `python`
- `containers`
- `networking`
- `security-lite`
- `debugging`
- `embedded-lite`

Synthetic profile:

- `alp-heavy` = `core` + `server` + `terminal-ux` + `dev-c` + `rust` + `go` +
  `zig` + `python` + `containers` + `networking` + `security-lite` +
  `debugging` + `embedded-lite`

Planned profiles:

- `desktop`
- `terminal-rice`
- `gui-rice`
- `devops`
- `fpga-hardware`
- `memory-debugging`

`alp-heavy` is broad CLI/devops/low-level setup. It is not a GUI or rice
profile. GUI/rice profiles are future work. Profile behavior is still
simple and based on TSV package rows.

## Java

Java is not installed by default.

Do not add Maven, Gradle, Spring, Kotlin, Selenium, or JVM-centered tooling to
default package maps. Java support should stay explicit opt-in work later.

## rust

The default Rust path prefers rustup.

On Ubuntu, the default package map avoids installing distro-managed cargo and
rustc alongside rustup, because this caused apt conflicts during real
Ubuntu ARM testing.

A distro-managed Rust profile may be added later as an explicit choice.

## macOS notes

macOS uses Homebrew. Homebrew is required but not auto-installed.

macOS setup is zsh-native:

- creates `~/.zshrc.d`
- appends a marked loader block to `~/.zshrc` if missing
- writes conservative zsh aliases
- may initialize starship only if `starship` exists

The script does not change the login shell, force bash as the interactive shell,
install GUI apps or casks, install window managers, override BSD tools with GNU
tools by default, or change security-sensitive Apple settings.

The macOS defaults are intentionally small:

- show Finder path bar
- show Finder status bar
- set screenshots to `~/Screenshots`
- set conservative keyboard repeat values

## Safety notes

- Use `--dry-run` first.
- No silent destructive config overwrite is intended.
- Managed shell files are clearly named under `~/.bashrc.d` or `~/.zshrc.d`.
- Existing shell startup files only get a marked loader block.
- No GUI/rice/casks/window managers are installed by default.
- No Java/JVM tooling is installed by default.
- The script does not change the login shell.

Backups and stronger dry-run coverage are still future work.

## Repo layout

- `README.md` - practical entry notes.
- `alp-linux-oneshot-bootstrap.sh` - current bootstrap script.
- `packages/ubuntu.tsv` - Ubuntu apt package map.
- `packages/debian.tsv` - Debian apt package map.
- `packages/fedora.tsv` - Fedora dnf package map.
- `packages/arch.tsv` - Arch pacman package map.
- `packages/rhel.tsv` - RHEL dnf package map.
- `packages/alpine.tsv` - Alpine apk package map.
- `packages/macos.tsv` - macOS Homebrew package map.

# optional Ubuntu workhorse scripts

The scripts/ directory contains optional Ubuntu-specific helper scripts for
post-bootstrap server work.

These are not part of the default bootstrap path.

scripts/finalize-ubuntu-workhorse.sh 
- post-bootstrap Ubuntu server cleanup,
package reinforcement, shell/session comfort, sysstat, chrony, plocate,
unattended-upgrades, Docker sanity checks, and final system summaries.
scripts/check-ubuntu-workhorse.sh 
- read-only Ubuntu workhorse check for
system resources, apt health, managed files, command coverage, Python,
Docker, and common server tooling.

## Tracelog

The Git history is the source of truth; this is only a short project-shape log.

### 2026-05-26

Started the repository with an Ubuntu-first bootstrap skeleton, then shaped it into a backend-based script with early Ubuntu and macOS support.

### 2026-05-27

Added the first Linux backend set beyond Ubuntu: Fedora, Arch, RHEL, and Debian. Also simplified the README and kept local notes/tracelogs out of Git.

### 2026-05-29

Added Alpine support with apk, keeping it conservative: no edge repositories, no AUR-like helper path, and no GUI/rice defaults.

### 2026-05-30

Added optional Ubuntu workhorse helper scripts for post-bootstrap server cleanup, checks, and day-to-day machine readiness.

### 2026-06-05

Tightened runtime behavior after real-machine testing: root-or-sudo execution, package-only check placeholders, clearer unsupported-backend failure, and the Ubuntu Rust default centered on rustup.
