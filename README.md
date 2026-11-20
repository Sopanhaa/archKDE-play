# ArchKDE-play

An easy, guided gaming setup for **Arch Linux + KDE Plasma**.

It installs the common pieces beginners need — graphics drivers, Steam, Lutris,
Heroic, Wine/Proton tools, GameMode, MangoHud, Flatpak, and safe performance
settings — with a simple menu and one confirmation.

**Safe by design:** it keeps your current kernel, never formats disks, never
edits bootloader entries, and never reboots your computer.

---

## Install in one command

Download the small entry script, then run it:

```bash
curl -fsSL https://raw.githubusercontent.com/Sopanhaa/archKDE-play/main/install.sh -o archkde-install.sh
bash archkde-install.sh
```

Optional: inspect the entry script first with `less archkde-install.sh`.

Run the download from a private directory such as your home directory, not a
shared directory like `/tmp`, so another local user cannot replace the file
while you inspect or run it.

The entry script downloads the repository archive over HTTPS, verifies it
against `SHA256SUMS`, and launches the installer.
It does **not** pipe downloaded code directly into a shell.

You do not run the whole installer as root. It asks for `sudo` only when system
changes are needed.

### Or use a local clone

```bash
git clone https://github.com/Sopanhaa/archKDE-play.git
cd archKDE-play
./install.sh
```

---

## Requirements

- Arch Linux (64-bit, `x86_64`) with internet access
- A regular user account with `sudo` (**do not run the installer as root**)
- At least 5 GiB free on `/` (10 GiB recommended)
- For Steam: `[multilib]` enabled — the installer can offer to enable it for you
- Secure Boot users must sign NVIDIA/kernel modules themselves; this project
  does not handle signing

---

## How the download is verified

- The repository URL is HTTPS and fixed by default.
- The entry script downloads a GitHub archive and a `SHA256SUMS` manifest.
- Every installer file is checked against the manifest before anything runs.
  On the default `main` branch, the downloaded entry script itself is checked
  against the same manifest as well.
- You can additionally pin the archive hash:
  ```bash
  ARCHKDE_SHA256=<sha256> bash archkde-install.sh
  ```
- The archive is unpacked into a private temporary directory and removed on
  exit. For a real installation, the verified source is also saved under
  `~/.local/share/archkde-play/source` so you can rerun modules and run the
  health check later. Check/dry-run/help runs do not save it.
- Nothing is piped directly into `bash`.
- You can inspect the entry script before running it. The repository is also
  available as a normal `git clone` if you prefer to review every file first.
- `ARCHKDE_REF` selects a branch or tag, and `ARCHKDE_REPO` selects a fork.
  For a reproducible install, use a release tag:
  ```bash
  ARCHKDE_REF=v1.2.3 bash archkde-install.sh
  ```
  `ARCHKDE_SKIP_CHECKSUM=1` exists only for local/offline testing and requires
  `ARCHKDE_ALLOW_INSECURE_SOURCE=1`; it is refused for normal remote HTTPS
  installs. Do not use it for real installations.

If verification fails, delete the downloaded file and run the command again.

Checksums protect against corrupted or mismatched downloads. They do not protect
against a compromised GitHub account or repository, because the archive and
manifest come from the same place. For higher assurance, pin a release tag with
`ARCHKDE_REF` and optionally set `ARCHKDE_SHA256`.

---

## Setup menu

```text
  ╭──────────────────────────────────────────────────╮
  │  archKDE-play                                    │
  │  Arch Linux gaming setup                         │
  ╰──────────────────────────────────────────────────╯

  Welcome! Let's set up your gaming system.
  System   Arch Linux x86_64 · NVIDIA GPU · KDE Plasma
  Safety   No partitions · No bootloader edits · No auto-reboot

  ❯  [1] Quick Setup                             (Recommended)
        Drivers, KDE, Steam, tools, and performance setup
     [2] Custom Setup
        Choose exactly which modules to install
     [3] GPU Drivers
        NVIDIA, AMD, Intel, and hybrid graphics
     [4] Gaming Apps
        Steam, Lutris, Heroic, Wine, GameMode, MangoHud
     [5] Performance Tools
        SSD trim and safe power profiles
     [6] System Check
        Read-only check; nothing is changed
     [0] Exit
        Quit without changing anything

  ↑/↓ Navigate   Enter Select   Q Quit

  Choose an option [1]:
```

Use **↑/↓** (or `j`/`k`) to move, **Enter** to select, or type a number.
On narrow terminals the descriptions are hidden; on terminals without Unicode
or color support the menu uses plain ASCII. Non-interactive runs still require
one of the CLI flags.

- **1. Quick Setup** — system update, Zen kernel, GPU drivers, KDE Plasma,
  gaming tools, Flatpak, and safe performance settings.
- **2. Custom Setup** — choose exactly which modules to install.
- **3. GPU Drivers** — detect NVIDIA/AMD/Intel/hybrid graphics and install the
  matching drivers and Vulkan libraries.
- **4. Gaming Apps** — Steam, Lutris, Heroic, Wine, GameMode, MangoHud,
  Gamescope, and Proton tools.
- **5. Performance Tools** — SSD trim and safe power profiles only.
- **6. System Check** — run the read-only checks and exit.
- **0. Exit** — leave without changing anything.

Press **Enter** for Quick Setup, or type an option number.

---

## What happens during setup

1. **Menu** — choose Quick Setup, Custom Setup, a single area, or a
   compatibility check.
2. **System check** — confirms Arch Linux, internet, disk space, `sudo`, the
   package database, KDE Plasma, your GPU, and your bootloader.
3. **Hardware summary** — shows your CPU, RAM, GPU vendor(s), storage, and free
   space, and recommends suitable options.
4. **Plan and confirmation** — shows exactly which modules will run and asks
   once before changing anything.
5. **Installation** — shows per-module progress (`→` running, `✓` complete),
   installs packages, enables services safely, and skips anything already
   installed.
6. **Summary** — shows what completed, the log location, and next steps.

If a module fails, the installer shows the error, common recovery steps, and
offers to retry that module. Declining stops before continuing to later modules
and keeps the log for troubleshooting. Rerunning is safe.

### Progress and errors

During installation, each module reports real status:

```text
  → [1/4] GPU drivers
  ✓ [1/4] GPU drivers (8s)
  → [2/4] Gaming tools
  ✓ [2/4] Gaming tools (12s)
```

- `→` means the module is running.
- `✓` is shown only after the module completes successfully.
- `✗` means it failed; the installer then offers to retry the module.
- Detailed output and errors are still saved under
  `~/.local/state/archkde-play/logs/`.

---

## Setup options

| Menu choice | Modules | Best for |
|-------------|---------|----------|
| **1. Quick Setup** | 01–07 | A new or mostly fresh Arch gaming PC |
| **2. Custom Setup** | Your choice | Skip optional parts or install one module |
| **3. GPU Drivers** | 03 | Fix or install graphics drivers |
| **4. Gaming Apps** | 05 | Add Steam, Lutris, Heroic, Wine, and tools |
| **5. Performance Tools** | 07 | SSD trim and safe power profiles |
| **6. System Check** | none | Read-only compatibility check |
| `--full` | 01–08 | Everything, including optional virtualization |
| `--gaming` | 03, 05, 06, 07 | KDE is already installed; add gaming tools |

### Modules

| # | Module | What it does |
|---|--------|--------------|
| 01 | System update | Updates Arch and installs `git`, `curl`, `wget`, PCI tools |
| 02 | Zen kernel *(optional)* | Installs `linux-zen` and keeps your current kernel as fallback |
| 03 | GPU drivers | Detects NVIDIA/AMD/Intel/hybrid graphics and installs matching drivers |
| 04 | KDE Plasma | Plasma, SDDM, NetworkManager, Bluetooth, PipeWire, KDE applets |
| 05 | Gaming tools | Steam, Lutris, Heroic, Wine, GameMode, MangoHud, Gamescope |
| 06 | Flatpak | Flatpak and the Flathub application store |
| 07 | Performance | SSD trim and safe power profiles only |
| 08 | Virtualization *(optional)* | QEMU/KVM and Virtual Machine Manager |

`--full` and `--modules` cannot be combined with each other or with a profile.

---

## Common commands

| Task | Command |
|------|---------|
| Guided setup (recommended) | `./install.sh` |
| Recommended setup, no menu | `./install.sh --recommended` |
| Gaming tools only | `./install.sh --gaming` |
| Check the system (no changes) | `./install.sh --check` |
| Preview the menu flow (no changes) | `./install.sh --dry-run` |
| Preview recommended setup (no changes) | `./install.sh --dry-run --recommended` |
| Install specific modules | `./install.sh --modules 03,05,06` |
| Install a range | `./install.sh --modules 03-05` |
| Install everything | `./install.sh --full` |
| Check system health | `./scripts/health-check.sh` |
| Update system and project | `./scripts/update.sh` |
| Preview updates | `./scripts/update.sh --dry-run` |
| Skip third-party AUR updates | `./scripts/update.sh --skip-aur` |
| Preview config rollback | `./scripts/rollback.sh --dry-run` |

When you used the one-command download, replace `./install.sh` with
`bash archkde-install.sh`, for example:

```bash
bash archkde-install.sh --check
bash archkde-install.sh --dry-run
```

No command ever uses automatic `--noconfirm` installation or reboots your PC.

---

## GPU support

GPUs are detected automatically:

- **NVIDIA** — installs `nvidia-open-dkms` (Turing/newer) or a matching DKMS
  package, plus `nvidia-utils`, `nvidia-settings`, and 32-bit libraries.
- **AMD** — installs Mesa, `vulkan-radeon`, and video acceleration drivers.
- **Intel** — installs Mesa, `vulkan-intel`, and media drivers.
- **Hybrid laptops** — installs drivers for each detected vendor; `prime-run`
  is added for NVIDIA offloading. The integrated GPU stays enabled.

The installer **does not** force PRIME, change GPU power settings, disable the
integrated GPU, or edit bootloader entries.

> **Older NVIDIA cards:** if your GPU is older than Turing (for example a GTX
> 10-series), install `nvidia-dkms` instead of `nvidia-open-dkms`. The installer
> warns you during the GPU step.

---

## Multilib and Steam

Steam needs 32-bit support from the `[multilib]` repository. If it is disabled,
the installer offers to enable it safely:

- it shows a clear yes/no prompt first;
- backs up `/etc/pacman.conf`;
- only uncomments the `[multilib]` section;
- validates the result before installing it;
- runs a full system upgrade with `pacman -Syu` after you confirm.

If you decline, the rest of the setup continues and Steam is skipped with a
warning. You can enable multilib manually later, then rerun:

```bash
sudo nano /etc/pacman.conf   # uncomment [multilib] and its Include line
sudo pacman -Syu
./install.sh --modules 05
```

---

## After installation

1. **Reboot** if the kernel or GPU drivers were installed.
2. **Steam:** open Steam → *Settings* → *Compatibility* → enable **Steam Play**
   for supported titles.
3. **GameMode + MangoHud:** add this to a game's Steam launch options:
   ```text
   gamemoderun mangohud %command%
   ```
4. **Heroic / ProtonUp-Qt:** open them from the application menu. ProtonUp-Qt
   manages Proton-GE versions for Steam, Lutris, and Heroic.
5. **Zen kernel:** if module 02 ran, choose `linux-zen` from your bootloader menu
   when convenient. Your previous kernel remains available.
6. **Verify:** run `./scripts/health-check.sh`.
7. **Virtualization:** if module 08 ran, sign out and back in before using
   Virtual Machine Manager, so the `libvirt` group applies.

If you used the one-command download, the verified source is saved here:

```bash
~/.local/share/archkde-play/source/install.sh
```

(or `$XDG_DATA_HOME/archkde-play/source` when `XDG_DATA_HOME` is set)

So you can rerun a module or check health without downloading again:

```bash
bash ~/.local/share/archkde-play/source/install.sh --modules 05
bash ~/.local/share/archkde-play/source/scripts/health-check.sh
```

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `curl` download fails | Check your internet connection and rerun the `curl` command. The URL uses HTTPS and should return a small Bash file. |
| `Checksum verification failed` | The archive or checksum manifest was corrupted or changed. Delete `archkde-install.sh`, then download and run it again. |
| `SHA256SUMS` cannot be downloaded | Retry. If you are testing a fork or a tag without a manifest, use the `git clone` method. Do not disable checksum verification for a remote HTTPS install. |
| Install stops with an error | The installer first offers to retry the failed module. If you decline, read the log path shown on screen (`~/.local/state/archkde-play/logs/`), fix the reported issue, then rerun the same command or the failed module, e.g. `./install.sh --modules 03`. Rerunning is safe. |
| `pacman is locked` | Wait for another update or package manager to finish. Do not delete the lock unless you are sure no update is running. |
| No internet / downloads fail | Reconnect, then rerun. Check with `ping archlinux.org`. |
| Steam is missing | Enable `[multilib]` (the installer offers this), run `sudo pacman -Syu`, then `./install.sh --modules 05`. |
| NVIDIA driver does not load | Check `dkms status`. With Secure Boot, sign the modules. Older GPUs may need `nvidia-dkms` instead of `nvidia-open-dkms`. |
| Vulkan problems | Run `sudo pacman -S vulkan-tools`, then `vulkaninfo --summary`. Ensure `vulkan-radeon`, `vulkan-intel`, or `nvidia-utils` is installed. |
| Packages were skipped | Refresh first with `sudo pacman -Syu`, then rerun the module. |
| Another login manager is installed | The installer will **not** switch display managers automatically. Disable your current one and enable `sddm` yourself if you want SDDM. |
| Not enough disk space | Free space on `/` and rerun. The installer warns below 10 GiB and stops below 5 GiB. |
| AUR updates need an AUR helper | AUR support is optional. Use `./scripts/update.sh --skip-aur` if you do not use `yay` or `paru`. |
| Secure Boot | Modules must be signed by your own setup. This project does not sign them or change boot entries. |

### Safe preview and checks

Nothing below changes the system:

```bash
./install.sh --check
./install.sh --dry-run --recommended
./install.sh --dry-run --modules 03,05
```

Dry-run prints every command that would run. It does not create log or state
files and does not install anything.

---

## Updates and rollback

Update official packages, Flatpak apps, optional AUR packages, and the project:

```bash
./scripts/update.sh
```

The saved one-command source is not a Git checkout, so `update.sh` updates
packages but skips the project Git pull. Rerun the download command to refresh
the saved source.

AUR packages are third-party PKGBUILDs. `update.sh` asks for a separate
confirmation before updating them; use `--skip-aur` to skip AUR updates
entirely.

Rollback removes **only** configuration files created by this project whose
contents are still unchanged:

```bash
./scripts/rollback.sh --dry-run   # preview
./scripts/rollback.sh             # confirm and remove
```

Rollback does **not** remove packages, undo upgrades, restore service states,
revert drivers, or change boot entries. Backups are kept under
`~/.local/state/archkde-play/backups/`.

---

## Optional features explained

- **Zen kernel (02):** better responsiveness for some desktops and games. Your
  existing kernel is kept as a fallback. It is included in the recommended
  profile; use `--gaming` or Custom Setup to skip it. Boot entries are
  never edited.
- **KDE Plasma (04):** skip it if you already use KDE. If another display
  manager is enabled, SDDM is installed but not forced.
- **Flatpak (06):** adds the Flathub store for apps such as Heroic if a native
  package is unavailable.
- **Performance (07):** enables weekly SSD trim and dynamic power profiles.
  It does not apply risky sysctl, CPU governor, or security-mitigation tweaks.
- **Virtualization (08):** optional QEMU/KVM setup. It is not part of the
  recommended profile.

---

## Project structure

```text
install.sh              Guided installer, remote entry point, and menu
SHA256SUMS              Checksums used by the remote entry point
lib/common.sh           Shared helpers (logging, packages, services, safety)
lib/ui.sh               Terminal UI: menu, keyboard navigation, progress helpers
lib/preflight.sh        Read-only system checks
lib/modules.sh          Single source of truth for modules and profiles
modules/NN-*.sh         One focused script per installation step
config/                 Package lists and managed configuration files
scripts/                Health check, update, rollback, checksum, and lint helpers
tests/                  Bash tests, mocks, and dry-run checks
```

For security reports, see `SECURITY.md`.

## License

[MIT](./LICENSE)
