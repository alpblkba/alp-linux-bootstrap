# alp-linux-bootstrap

`alp-linux-bootstrap` is a cross-distribution Linux/macOS bootstrap framework for
building a practical, opinionated, keyboard-first engineering environment.

It should feel like yet another boring Linux bootstrapper from the outside:
install packages, create a few directories, wire up shell helpers, and get out of
the way. Internally, it is intended to grow into a profile-aware setup system
that can support servers, desktops, terminals, devops machines, hardware labs,
and macOS without pretending they are all the same computer.

Current status: early skeleton. The first implementation is Ubuntu-first: it
uses the Ubuntu package map and Ubuntu backend as the first working path, while
the repository is intentionally structured to grow into a multi-distro framework.
Other distributions, richer fallbacks, backups, profile expansion, and one-shot
export are planned.

## Current Status

The first working implementation is Ubuntu-first. It reads `packages/ubuntu.tsv`,
selects packages by profile, creates conservative user directories, wires a
bashrc.d loader, writes a small aliases file, and creates a temporary check
script. The script already names planned backend families so the shape remains
multi-distro, but only the Ubuntu backend performs real package installation in
v0.

Package maps are early and may require distro-specific fallbacks as real Ubuntu
versions are tested.

The Ubuntu backend should prefer package-manager installs, but it must tolerate
missing packages where Ubuntu versions differ. Tools such as `starship`,
`zellij`, `zig`, and some container/debugging packages may require fallback
installers later; v0 should skip unavailable apt packages with a warning rather
than failing the entire bootstrap transaction.

## Why This Exists

Most bootstrap projects drift toward one of two extremes: blind dotfiles copying
or highly personal setup machinery that is hard to reuse. This project aims for
the middle:

- Survey respected Linux/FOSS power users' dotfiles and steal durable patterns.
- Prefer good long-session UX over screenshot-first aesthetics.
- Keep the workflow terminal-first, keyboard-first, and low-friction.
- Make GUI and rice layers optional, reproducible, and productivity-oriented.
- Treat profiles as first-class choices instead of one giant install script.
- Keep the first implementation simple enough to audit.

## Design Philosophy

- Do not silently overwrite user configuration.
- Do not copy dotfiles blindly.
- Prefer modular shell snippets over giant unstructured startup files.
- Prefer boring package-manager installs before custom build logic.
- Prefer readable bash for GNU/Linux bootstrap behavior.
- Prefer macOS-native behavior on macOS instead of forcing Linux habits onto it.
- Keep local user tools in `~/.local/bin`.
- Make power-user terminal defaults available without making the machine weird.
- Keep Java out of the default path.

## Shell Stance

GNU/Linux defaults to bash as the main interactive shell target.

macOS keeps zsh as the native main shell. Bash should still be available for
scripts and installers, but the bootstrapper should not forcibly Linuxify macOS.
Future macOS support should use Homebrew and conservative system tweaks.

## Java Stance

Java is excluded by default. No Maven, Gradle, Spring, Kotlin, Selenium, or
JVM-centered tooling should appear in default profiles. Java may be added later
as an explicit opt-in path only.

The current one-shot script accepts `--with-java`, but it intentionally prints a
not-implemented message.

## Target Systems

Ubuntu is the first implemented backend. The script should keep room for the
other backend families from the beginning, but the rest of this list is still
the planned multi-distro roadmap rather than completed support.

Planned support includes:

- macOS current and recent versions
- Ubuntu 20-26, Server/Desktop/Core where possible
- Debian latest 1-2 releases
- Fedora 40+
- Arch rolling/recent
- Alpine latest 1-2
- RHEL 7/8/9
- CentOS 7/8
- openSUSE/SUSE latest, initially openSUSE Tumbleweed
- experimental or devops-oriented OSes later, if useful

WSL support should exist enough to avoid breaking, not as a rich WSL-first
design.

## Profiles

Profiles are the main unit of intent. The initial package map is small, but the
eventual profile set is expected to include:

- `core`
- `server`
- `desktop`
- `alp-heavy`
- `terminal-rice`
- `gui-rice`
- `devops`
- `containers`
- `networking`
- `security-lite`
- `embedded`
- `fpga-hardware`
- `memory-debugging`
- `macos`
- `no-java`

The default bootstrap profile is currently `alp-heavy`.

## Safety Goals

Safety is part of the product, not a polish pass:

- Dry-run support should be available and trustworthy.
- Backups should exist before managed config writes.
- No silent destructive overwrites.
- Local overrides should be respected.
- Installer behavior should be visible and boring.
- Platform detection should fail clearly when unsupported.

The current script already avoids GUI/rice work and keeps shell changes small.
More complete dry-run and backup behavior will come as the repository grows.

## Current Files

- `README.md` - project intent and design constraints.
- `docs/guru-survey.md` - structured notes from dotfiles/bootstrap influences.
- `packages/ubuntu.tsv` - initial Ubuntu package map.
- `alp-linux-oneshot-bootstrap.sh` - early repo-run bash bootstrap skeleton.

## Early Usage

From a checkout on Ubuntu:

```bash
./alp-linux-oneshot-bootstrap.sh --dry-run
./alp-linux-oneshot-bootstrap.sh --profile alp-heavy
```

This is not yet a polished public installer. Treat it as a readable foundation.
