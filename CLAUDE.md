# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) and AI agents when working with code in this repository.

## Overview

Personal cross-platform dotfiles repository supporting **macOS** and **Ubuntu 26.04 (amd64 / arm64)**. Two primary entrypoint scripts drive the system:
- `setup.sh`: Installs platform packages, links tool configurations, configures shell blocks, and sets up developer runtimes.
- `uninstall.sh`: Conservatively reverts managed symlinks and configuration blocks (and optionally removes newly installed packages).

---

## Directory & Modular Architecture

- `lib/common.sh`: Common logging, error handling (`fail`, `report`), safe execution wrappers (`run`, `run_privileged`), and path initializers (`init_paths`).
- `lib/platform.sh`: Platform detection (`detect_platform`), GUI mode resolution (`desktop` vs. `headless`), and dynamic platform adapter loading.
- `lib/state.sh`: Transactional, append-only journal (`~/.local/state/dotfiles/journal.tsv`) tracking symlinks, backups, packages, and releases.
- `lib/config.sh`: Atomic symlink linking with backup preservation, `~/.zshrc` managed block injection/migration, and Git profile include management.
- `lib/runtime.sh`: Virtual environment provisioning (`~/.venv`), IntelliJ IDEA plugin installation, `rtk` initialization, and Podman/Kind cluster management.
- `lib/platforms/macos.sh`: macOS Homebrew bundling, bundle parsing, application paths, and package teardown.
- `lib/platforms/ubuntu.sh`: Ubuntu APT packages, GPG-pinned vendor repositories, and verified user-space release binaries.
- `packages/ubuntu/`: Inventory TSV files (`common.tsv`, `home.tsv`, `work.tsv`, `vendors.tsv`, `releases.tsv`).
- `.config/`: Tool configuration files (Starship, Ghostty, Zed, Zsh snippet, Git profiles).
- `tests/`: BATS unit and integration test suites, stubs, and unified test harness (`tests/validate.bash`).

---

## Setup & Teardown

```bash
# Setup for home or work profile
./setup.sh home
./setup.sh work

# Preview planned actions without modifying system state
./setup.sh home --dry-run
./setup.sh work --headless --dry-run

# Revert dotfiles-managed configurations and restore original files
./uninstall.sh

# Revert configurations and remove managed packages recorded in journal
./uninstall.sh --remove-packages

# Complete teardown: configs, packages, and runtimes (~/.venv, Kind clusters)
./uninstall.sh --purge-all
```

---

## Testing & Quality Assurance

Enforce syntax validation, static analysis, and BATS test execution before committing:

```bash
# Run full validation harness (shellcheck, zsh syntax, and BATS tests)
bash tests/validate.bash
```
