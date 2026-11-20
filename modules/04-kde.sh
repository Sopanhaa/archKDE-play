#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/lib/common.sh"
source "$ROOT_DIR/config/packages.conf"

install_available_packages "${KDE_PACKAGES[@]}"

enable_service NetworkManager.service || true
enable_service bluetooth.service || true
enable_display_manager sddm || true
log INFO "PipeWire user services start with the user's session; no system-wide audio service is enabled."
log INFO "If another display manager was already enabled, it was left untouched."
