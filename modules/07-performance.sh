#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/lib/common.sh"

root_source="$(findmnt -no SOURCE / 2>/dev/null || true)"
if [[ -n "$root_source" ]] && lsblk -ndo ROTA "$root_source" 2>/dev/null | grep -qx 0; then
    enable_service fstrim.timer 1 || true
    log INFO "Weekly SSD discard is enabled through fstrim.timer."
else
    log INFO "Root storage was not identified as solid-state; fstrim.timer was not changed."
fi

if package_installed tlp || package_installed auto-cpufreq; then
    log WARN "TLP or auto-cpufreq is installed; leaving CPU power policy alone to avoid a conflict."
elif package_available power-profiles-daemon; then
    install_available_packages power-profiles-daemon
    enable_service power-profiles-daemon.service 1 || true
    log INFO "Enabled dynamic power profiles; no fixed performance governor was forced."
else
    log WARN "power-profiles-daemon is unavailable; leaving CPU power policy unchanged."
fi

log INFO "No speculative sysctl, security-mitigation, or kernel-parameter tweaks were applied."
log INFO "Zram was not enabled automatically; on a 16 GiB system it should be chosen based on workload."
