# ArchKDE-play

An easy, guided gaming setup for **Arch Linux + KDE Plasma**.

It installs the common pieces beginners need — graphics drivers, Steam, Lutris,
Heroic, Wine/Proton tools, GameMode, MangoHud, Flatpak, and safe performance
settings — with a simple menu and one confirmation.

**Safe by design:** it keeps your current kernel, never formats disks, never
edits bootloader entries, and never reboots your computer.

---

## Requirements

- Arch Linux (64-bit, `x86_64`) with internet access
- A regular user account with `sudo` (**do not run the installer as root**)
- At least 5 GiB free on `/` (10 GiB recommended)
- For Steam: `[multilib]` enabled — the installer can offer to enable it for you
- Secure Boot users must sign NVIDIA/kernel modules themselves; this project
  does not handle signing

---

## Quick start

Run these three commands:

```bash
git clone https://github.com/Sopanhaa/archKDE-play.git
cd archKDE-play
./install.sh
```

You will see a short system check and a menu:

```text
1) Recommended gaming setup  (recommended)
2) Gaming essentials (KDE already installed)
3) Custom module selection (advanced)
q) Quit
```

**Press Enter** to choose the recommended setup. Review the plan, then type `y`
at the single confirmation prompt.

That is the recommended command for almost everyone:

```bash
./install.sh
```

To choose the recommended setup without the menu:

```bash
./install.sh --recommended
```

---

## What happens during setup

1. **System check** — confirms Arch Linux, internet, disk space, `sudo`, the
   package database, your GPU, and your bootloader.
2. **Hardware summary** — shows your CPU, RAM, GPU vendor(s), storage, and free
   space, and recommends suitable options.
3. **Setup menu** — pick the recommended setup, gaming essentials, or custom
   modules. Optional parts can be skipped.
4. **Plan and confirmation** — shows exactly which modules will run and asks
   once before changing anything.
5. **Installation** — installs packages, enables services safely, and skips
   anything already installed.
6. **Summary** — shows what completed, the log location, and next steps.

If something fails, the installer stops with a clear message, keeps the log,
and tells you how to rerun only the failed module. Rerunning is safe.

---

## Setup options

| Choice | Modules | Best for |
|--------|---------|----------|
| **1. Recommended** | 01–07 | A new or mostly fresh Arch gaming PC |
| **2. Gaming essentials** | 03, 05, 06, 07 | KDE is already installed; add drivers and gaming tools |
| **3. Custom** | Your choice | Skip optional parts or install one module |
| `--full` | 01–08 | Everything, including optional virtualization |

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
| Preview everything (no changes) | `./install.sh --dry-run --recommended` |
| Install specific modules | `./install.sh --modules 03,05,06` |
| Install a range | `./install.sh --modules 03-05` |
| Install everything | `./install.sh --full` |
| Check system health | `./scripts/health-check.sh` |
| Update system and project | `./scripts/update.sh` |
| Preview updates | `./scripts/update.sh --dry-run` |
| Skip third-party AUR updates | `./scripts/update.sh --skip-aur` |
| Preview config rollback | `./scripts/rollback.sh --dry-run` |

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
- refreshes packages with `pacman -Syu`.

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

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| Install stops with an error | Read the log path shown on screen (`~/.local/state/archkde-play/logs/`), fix the reported issue, then rerun the same command or the failed module, e.g. `./install.sh --modules 03`. Rerunning is safe. |
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
  profile; choose gaming essentials or custom selection to skip it. Boot entries
  are never edited.
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
install.sh              Guided installer and profile menu
lib/common.sh           Shared helpers (logging, packages, services, safety)
lib/preflight.sh        Read-only system checks
lib/modules.sh          Single source of truth for modules and profiles
modules/NN-*.sh         One focused script per installation step
config/                 Package lists and managed configuration files
scripts/                Health check, update, rollback, and lint helpers
tests/                  Bash tests, mocks, and dry-run checks
```

For contributors, see `CONTRIBUTING.md` (style, tests, pull requests),
`SECURITY.md` (private reports), and `CODE_OF_CONDUCT.md`.

## License

[MIT](./LICENSE)
