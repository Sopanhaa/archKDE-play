#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/lib/common.sh"
source "$ROOT_DIR/config/packages.conf"

# install.sh offers to enable [multilib] before modules run.
packages=("${GAMING_PACKAGES[@]}")
if multilib_enabled; then
    packages+=(lib32-mangohud lib32-gamemode)
else
    log WARN "Multilib is disabled; 32-bit gaming libraries were skipped. Steam may be unavailable."
fi
install_available_packages "${packages[@]}"

# Start GameMode now when inside a graphical session. If this fails, GameMode
# still starts on demand when a game is launched.
enable_user_service gamemoded.service || true

# Heroic is available from some repositories and from Flathub. Prefer the
# native package when it exists, otherwise use the system-wide Flathub remote.
heroic_installed=0
for candidate in heroic-games-launcher heroic-games-launcher-bin; do
    if package_installed "$candidate"; then
        heroic_installed=1
        log INFO "Heroic Games Launcher is already installed ($candidate)."
        break
    fi
done

if ((!heroic_installed)); then
    heroic_package=""
    for candidate in heroic-games-launcher heroic-games-launcher-bin; do
        if package_available "$candidate"; then
            heroic_package="$candidate"
            break
        fi
    done
    if [[ -n "$heroic_package" ]]; then
        install_available_packages "$heroic_package"
    elif ensure_flathub_remote; then
        if ! sudo_run flatpak install --system --or-update flathub com.heroicgameslauncher.hgl; then
            log WARN "Heroic could not be installed from Flathub; you can retry later with: sudo flatpak install flathub com.heroicgameslauncher.hgl"
        fi
    else
        log WARN "Heroic was not installed; configure Flathub and install com.heroicgameslauncher.hgl later."
    fi
fi

# ProtonUp-Qt manages Proton-GE versions. Use the native package when it is
# available, otherwise fall back to Flatpak.
if package_installed protonup-qt || package_available protonup-qt; then
    log INFO "ProtonUp-Qt is installed from the repositories (or will be installed by this module)."
elif ensure_flathub_remote; then
    if ! sudo_run flatpak install --system --or-update flathub net.davidotek.pupgui2; then
        log WARN "ProtonUp-Qt could not be installed from Flathub."
    fi
else
    log WARN "ProtonUp-Qt is not available in the enabled repositories or Flathub."
fi

log INFO "Gaming tools are ready. Enable Steam Play for Windows games in Steam Settings."
