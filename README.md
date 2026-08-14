# alp-linux-bootstrap

These are  my personal boootstrap scripts and package manifests to configure fresh Linux and macOS installations. The setup handles package installation, user shell environment configuration, and compatibility symlinks across multiple distributions.

Package definitions are maintained in TSV files under packages/ to separate data from execution logic. Version locks are generated and checked daily through container-based CI jobs.


## Quickstart

Run the single-stage bootstrap script directly on a fresh machine:

```bash
sh -c "$(curl -fsSL [https://raw.githubusercontent.com/alpblkba/alp-linux-bootstrap/main/alp-linux-oneshot-bootstrap.sh](https://raw.githubusercontent.com/alpblkba/alp-linux-bootstrap/main/alp-linux-oneshot-bootstrap.sh))"
```

To inspect package manifests and modify selections before applying:

```
git clone [https://github.com/alpblkba/alp-linux-bootstrap.git](https://github.com/alpblkba/alp-linux-bootstrap.git) ~/.alp-bootstrap
cd ~/.alp-bootstrap
./alp-linux-oneshot-bootstrap.sh
```

## Supported distributions & platforms

The automated CI matrix and bootstrap definitions currently verify and support the following targets:

- **Ubuntu**: 24.04 LTS (`ubuntu:24.04`)
- **Debian**: 12 Bookworm (`debian:bookworm-slim`)
- **Arch Linux**: Rolling release (`archlinux:latest`)
- **Fedora**: Latest stable release (`fedora:latest`)
- **RHEL / Enterprise Linux**: EL 9 ecosystem (`rockylinux:9` with EPEL and CRB enabled)
- **Alpine Linux**: Latest stable (`alpine:latest` with edge community repository)
- **macOS**: Latest stable (`macos-latest` runner via Homebrew)

 Package manifests are located in `packages/<distro>.tsv` and version lock states are synchronized daily in `packages/locks/<distro>.lock`.

Backends are currently family-based, not version-specific.

Debian and Ubuntu both use apt, but they have separate package maps. Debian-family systems use compatibility symlinks for fd and bat command names where needed.

Arch support does not include AUR helpers. No yay, paru, or AUR packages are installed in v0.

RHEL support is repository-dependent. The script does not register RHEL systems, run subscription-manager, or enable EPEL in v0.

Alpine support uses apk and does not enable edge repositories in v0. Package availability depends on enabled repositories and architecture.

### Planned backend families:

    CentOS
    openSUSE/SUSE

### Longer-term target list:

    macOS current and recent versions
    Ubuntu 20-26, Server/Desktop/Core where possible
    Debian latest 1-2 releases
    Fedora 40+
    Arch rolling/recent
    Alpine latest 1-2
    RHEL 7/8/9
    CentOS 7/8
    openSUSE/SUSE latest, initially openSUSE Tumbleweed
    experimental OSes later, if useful

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

#### Synthetic profile:

- `alp-heavy` = `core` + `server` + `terminal-ux` + `dev-c` + `rust` + `go` +
  `zig` + `python` + `containers` + `networking` + `security-lite` +
  `debugging` + `embedded-lite`

#### Planned profiles:

- `desktop`
- `terminal-rice`
- `gui-rice`
- `devops`
- `fpga-hardware`
- `memory-debugging`

`alp-heavy` is the broader and more professional setup. GUI/rice profiles are future work. Profile behavior is still simple and based on TSV package rows.


## about Java

Java is not installed by default.

Do not add Maven, Gradle, Spring, Kotlin, Selenium, or JVM-centered tooling to default package maps. Java support should stay explicit opt-in work later.

## Rust

The default Rust path prefers rustup.

On Ubuntu, the default package map avoids installing distro-managed cargo and rustc alongside rustup, because this caused apt conflicts during real Ubuntu ARM testing.

A distro-managed Rust profile may be added later as an explicit choice.

## macOS notes

macOS uses Homebrew. Homebrew is required but not auto-installed.

macOS setup is zsh-native:

- creates `~/.zshrc.d`
- appends a marked loader block to `~/.zshrc` if missing
- writes conservative zsh aliases
- may initialize starship only if `starship` exists

The script does not change the login shell, force bash as the interactive shell, install GUI apps or casks, install window managers, override BSD tools with GNU tools by default, or change security-sensitive Apple settings.

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

### optional Ubuntu workhorse scripts

The scripts/ directory contains optional Ubuntu-specific helper scripts for post-bootstrap server work.

These are not part of the default bootstrap path.

scripts/finalize-ubuntu-workhorse.sh 
- post-bootstrap Ubuntu server cleanup,package reinforcement, shell/session comfort, sysstat, chrony, plocate,unattended-upgrades, Docker sanity checks, and final system summaries.

scripts/check-ubuntu-workhorse.sh 
- read-only Ubuntu workhorse check for system resources, apt health, managed files, command coverage, Python, Docker, and common server tooling.

## Current status

- Ubuntu: apt package install, bash setup, and Ubuntu compatibility symlinks for tools such as fd and bat.
- Debian: apt package install, bash setup, and Debian-family compatibility symlinks for tools such as fd and bat.
- Fedora: dnf package install and bash setup.
- Arch: pacman package install and bash setup.
- RHEL: dnf package install and bash setup.
- Alpine: apk package install and bash setup.
- macOS: Homebrew package install, zsh setup, and conservative macOS defaults.
- Other backends: named/planned stubs only.
- GUI/rice options: not in the default path.

The project is still early. Review the script and package maps before running a real install.

Package maps are also early. Some apt, dnf, pacman, and Homebrew packages may be unavailable on a given OS version or enabled repository set; the script filters unavailable packages before real installs where practical.


## Repository structure (always is subject to change)

```
├── alp-linux-oneshot-bootstrap.sh   # Main entrypoint script
├── packages
│   ├── STATUS.md                   # Package count and placeholder status table
│   ├── <distro>.tsv                # Tab-separated package manifests per platform
│   └── locks
│       └── <distro>.lock           # Synchronized upstream package versions
├── scripts
│   ├── lint-tsv.sh                 # Validates TSV file format and separators
│   ├── verify-packages.sh          # Checks package availability in distribution repositories
│   ├── track-updates.sh            # Queries repository versions and generates lockfiles
│   └── sync-status.sh              # Updates STATUS.md overview matrix
└── tracelog                        # Historical notes and implementation records
```



### Manifest format

- **category**: Group name used during installation (base, development, tools, network, security).
- **logical_name**: Generic name of the tool across all operating systems.
- **package**: Distribution specific package manager name. Placeholders (-, none, custom, builtin) indicate tools installed outside standard package managers.
- **description**: Plain text summary of the package.


## Automated CI and version tracking

The repository uses GitHub Actions to validate package availability and track version changes across all supported platforms. The workflow executes on every push, pull request, and daily at 04:00 UTC:

- scripts/lint-tsv.sh validates that all manifest files use tab characters instead of spaces and contain non-empty field definitions.

- Container matrix jobs launch isolated environments for Arch, Ubuntu, Debian, Fedora, RHEL (Rocky Linux 9), Alpine, and macOS runners.

- scripts/verify-packages.sh queries the native package managers to confirm that listed packages exist in upstream repositories.

- scripts/track-updates.sh resolves package versions, generates lockfiles in packages/locks/, and records upstream version bumps.

##### ! If version changes are detected during the scheduled run, the workflow generates a commit with detailed version diffs and updates packages/locks/.



## Tracelog

The Git history is the source of truth; this is only a short project-shape log.

#### 2026-05-26
Started the repository with an Ubuntu-first bootstrap skeleton, then shaped it into a backend-based script with early Ubuntu and macOS support.

#### 2026-05-27
Added the first Linux backend set beyond Ubuntu: Fedora, Arch, RHEL, and Debian. Also simplified the README and kept local notes/tracelogs out of Git.

#### 2026-05-29
Added Alpine support with apk, keeping it conservative: no edge repositories, no AUR-like helper path, and no GUI/rice defaults.

#### 2026-05-30
Added optional Ubuntu workhorse helper scripts for post-bootstrap server cleanup, checks, and day-to-day machine readiness.

#### 2026-06-05
Tightened runtime behavior after real-machine testing: root-or-sudo execution, package-only check placeholders, clearer unsupported-backend failure, and the Ubuntu Rust default centered on rustup.

#### 2026-08-14
Added GitHub Actions container matrix and TSV linter (`scripts/lint-tsv.sh`, `scripts/verify-packages.sh`).

#### 2026-08-15
Added version tracking (`scripts/track-updates.sh`), lockfile management, and automated sync commits.
