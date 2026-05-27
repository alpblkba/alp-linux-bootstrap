# alp-linux-bootstrap

This is my own bootstrap repository for setting up Linux and macOS machines.

It installs packages, creates a small directory layout, adds conservative shell
helpers, and keeps package lists split by platform. The current working backends
are Ubuntu, Fedora, Arch, and macOS. Other distributions are planned but not
implemented yet.

It is a setup script that should stay readable enough to review, edit, and run
again.

## Current Status

- Ubuntu backend: apt package install, bash setup, and Ubuntu compatibility
  symlinks for tools such as `fd` and `bat`.
- Fedora backend: dnf package install and bash setup.
- Arch backend: pacman package install and bash setup.
- macOS backend: Homebrew package install, zsh setup, and conservative macOS
  defaults.
- Other backends: named/planned stubs only.
- GUI/rice: not in the default path.

The project is still early. Review the script and package maps before running a
real install.

Package maps are also early. Some apt, dnf, pacman, and Homebrew packages may be
unavailable on a given OS version; the script filters unavailable packages before
real installs where practical.

## Usage

Ubuntu:

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
- Fedora: real dnf install path.
- Arch: real pacman install path using official repositories only.
- macOS: real Homebrew install path, assuming Homebrew is already installed.

Backends are currently family-based, not version-specific.

Arch support does not include AUR helpers. No `yay`, `paru`, or AUR packages are
installed in v0.

Planned backend families:

- Debian
- Alpine
- RHEL
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

## about Java

Java is not installed by default.

Do not add Maven, Gradle, Spring, Kotlin, Selenium, or JVM-centered tooling to
default package maps. Java support should stay explicit opt-in work later.

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
- `packages/fedora.tsv` - Fedora dnf package map.
- `packages/arch.tsv` - Arch pacman package map.
- `packages/macos.tsv` - macOS Homebrew package map.
