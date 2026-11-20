#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/lib/common.sh"
source "$ROOT_DIR/config/packages.conf"

install_available_packages "${FLATPAK_PACKAGES[@]}"

if ! ensure_flathub_remote; then
    log WARN "Flathub was not configured. Check your internet connection and rerun this module."
    exit 1
fi

if ((DRY_RUN)); then
    run flatpak remotes
    exit 0
fi

if flatpak remote-info flathub org.freedesktop.Platform >/dev/null 2>&1; then
    log INFO "Flathub is reachable and ready to install applications."
else
    log WARN "Flathub is configured, but its metadata could not be read. Check your internet connection."
fi
log INFO "Existing Flatpak applications were not reinstalled."
