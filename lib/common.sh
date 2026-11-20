#!/usr/bin/env bash

ROOT_DIR="${ROOT_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
STATE_ROOT="${XDG_STATE_HOME:-${HOME}/.local/state}"
STATE_DIR="${STATE_ROOT}/archkde-play"
LEGACY_STATE_DIR="${STATE_ROOT}/arch-extreme-gaming"
# Keep using an existing legacy state directory so an in-progress install does
# not lose its logs or rollback manifest after the project rename.
if [[ ! -d "$STATE_DIR" && -d "$LEGACY_STATE_DIR" ]]; then
    STATE_DIR="$LEGACY_STATE_DIR"
fi
LOG_FILE="${LOG_FILE:-$STATE_DIR/logs/setup-$(date +%Y%m%d).log}"
MANIFEST_FILE="${MANIFEST_FILE:-$STATE_DIR/rollback/manifest.txt}"
BACKUP_DIR="${BACKUP_DIR:-$STATE_DIR/backups}"
DRY_RUN="${DRY_RUN:-0}"
LOG_TEE="${LOG_TEE:-0}"
SETUP_QUIET="${SETUP_QUIET:-0}"
MULTILIB_PREVIEW_ENABLED="${MULTILIB_PREVIEW_ENABLED:-0}"

# Colour is only used on a real terminal. install.sh sets SETUP_FORCE_COLOR
# before it redirects output through tee so interactive output stays readable.
if [[ -z "${NO_COLOR:-}" && "${TERM:-dumb}" != "dumb" ]] &&
    { [[ -t 1 ]] || [[ "${SETUP_FORCE_COLOR:-0}" == "1" ]]; }; then
    C_RESET=$'\033[0m'
    C_BOLD=$'\033[1m'
    C_DIM=$'\033[2m'
    C_RED=$'\033[31m'
    C_GREEN=$'\033[32m'
    C_YELLOW=$'\033[33m'
    C_BLUE=$'\033[34m'
    C_CYAN=$'\033[36m'
else
    C_RESET=""
    C_BOLD=""
    C_DIM=""
    C_RED=""
    C_GREEN=""
    C_YELLOW=""
    C_BLUE=""
    C_CYAN=""
fi

log() {
    local level="$1"
    shift
    local message quiet=0
    printf -v message '%s [%s] %s' "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$*"
    if ((SETUP_QUIET)) && [[ "$level" == INFO ]]; then
        quiet=1
    fi
    ((quiet)) || printf '%s\n' "$message"
    if ((!LOG_TEE)) || ((quiet)); then
        if [[ -d "$(dirname -- "$LOG_FILE")" ]] || mkdir -p -- "$(dirname -- "$LOG_FILE")"; then
            printf '%s\n' "$message" >>"$LOG_FILE"
        else
            printf 'Unable to write log file: %s\n' "$LOG_FILE" >&2
            return 1
        fi
    fi
}

die() {
    log ERROR "$*"
    exit 1
}

section() {
    ((SETUP_QUIET)) && return 0
    printf '\n%s==> %s%s\n' "$C_BOLD$C_BLUE" "$*" "$C_RESET"
}

ui_ok() {
    ((SETUP_QUIET)) && return 0
    printf '  %s[ OK ]%s %s\n' "$C_GREEN" "$C_RESET" "$*"
}

ui_warn() {
    printf '  %s[WARN]%s %s\n' "$C_YELLOW" "$C_RESET" "$*"
}

ui_fail() {
    printf '  %s[FAIL]%s %s\n' "$C_RED" "$C_RESET" "$*"
}

ui_note() {
    ((SETUP_QUIET)) && return 0
    printf '  %s[INFO]%s %s\n' "$C_CYAN" "$C_RESET" "$*"
}

format_duration() {
    local seconds="${1:-0}"
    if ((seconds < 60)); then
        printf '%ss' "$seconds"
    else
        printf '%dm %ss' "$((seconds / 60))" "$((seconds % 60))"
    fi
}

require_non_root() {
    ((EUID != 0)) || die "Run this command as a regular user, not root."
}

path_within_state() {
    local path="$1"
    local state_real path_real
    state_real="$(realpath -m -- "$STATE_DIR" 2>/dev/null)" || return 1
    path_real="$(realpath -m -- "$path" 2>/dev/null)" || return 1
    [[ "$path_real" == "$state_real" || "$path_real" == "$state_real"/* ]]
}

rollback_target_allowed() {
    local target="${1:-}"
    local canonical
    canonical="$(realpath -m -- "$target" 2>/dev/null)" || return 1
    [[ "$canonical" == "$target" ]] || return 1
    [[ "$target" == /etc/modprobe.d/arch-extreme-gaming-* ||
        "$target" == /etc/modprobe.d/archkde-play-* ]]
}

init_logging() {
    local log_dir
    log_dir="$(dirname -- "$LOG_FILE")"
    mkdir -p -- "$STATE_DIR"
    chmod 700 -- "$STATE_DIR" 2>/dev/null || true
    mkdir -p -- "$log_dir"
    if path_within_state "$log_dir"; then
        chmod 700 -- "$log_dir" 2>/dev/null || true
    fi
    touch "$LOG_FILE"
    if path_within_state "$LOG_FILE"; then
        chmod 600 -- "$LOG_FILE" 2>/dev/null || true
    fi
}

run() {
    local quoted
    printf -v quoted '%q ' "$@"
    quoted="${quoted% }"
    if ((DRY_RUN)); then
        printf '%s[DRY-RUN]%s %s\n' "$C_DIM" "$C_RESET" "$quoted"
        return 0
    fi
    printf '%s+ %s%s\n' "$C_DIM" "$quoted" "$C_RESET"
    "$@"
}

sudo_run() {
    run sudo "$@"
}

check_arch() {
    [[ -f /etc/arch-release ]] || die "This installer supports Arch Linux only."
    command -v pacman >/dev/null 2>&1 || die "pacman was not found."
    [[ "$(uname -m)" == x86_64 ]] || die "This gaming setup currently supports x86_64 systems only."
}

check_internet() {
    if ! internet_available; then
        die "Internet connectivity check failed; connect to the internet and ensure curl, wget, or timeout is available."
    fi
    log INFO "Internet connectivity verified."
}

secure_boot_enabled() {
    local boot_status=""
    if command -v mokutil >/dev/null 2>&1 &&
        mokutil --sb-state 2>/dev/null | grep -qi enabled; then
        return 0
    fi
    if command -v bootctl >/dev/null 2>&1; then
        boot_status="$(bootctl status --no-pager 2>/dev/null || true)"
    fi
    grep -Eqi 'Secure Boot:[[:space:]]*enabled' <<<"$boot_status"
}

internet_available() {
    if command -v curl >/dev/null 2>&1; then
        if curl -fsS --max-time 8 https://archlinux.org/ -o /dev/null; then
            return 0
        fi
    fi
    if command -v wget >/dev/null 2>&1; then
        if wget -q --spider --timeout=8 https://archlinux.org/; then
            return 0
        fi
    fi
    if command -v timeout >/dev/null 2>&1; then
        if timeout 8 bash -c 'exec 3<>/dev/tcp/archlinux.org/443' >/dev/null 2>&1; then
            return 0
        fi
    fi
    return 1
}

# Return the raw display-controller information from lspci. If lspci is not
# installed (or returns nothing), fall back to sysfs so GPU detection still
# works on minimal systems.
detect_system_gpu_info() {
    local info=""
    local device class vendor_id

    if command -v lspci >/dev/null 2>&1; then
        info="$(lspci -nn 2>/dev/null |
            grep -Ei 'VGA compatible controller|3D controller|Display controller' || true)"
    fi

    if [[ -n "$info" ]]; then
        printf '%s\n' "$info"
        return 0
    fi

    for device in /sys/bus/pci/devices/*; do
        [[ -r "$device/class" && -r "$device/vendor" ]] || continue
        class="$(<"$device/class")"
        class="${class,,}"
        case "$class" in
            0x0300*|0x0302*|0x0380*)
                vendor_id="$(<"$device/vendor")"
                printf '%s: display controller\n' "${vendor_id#0x}"
                ;;
        esac
    done
}

# Accepts lspci-style text and prints unique vendor names in detection order:
# "nvidia", "amd", "intel", multiple values, or "unknown".
detect_gpu_vendors() {
    local info="${1:-}"
    local line lower vendor
    local -a found=()
    local -A seen=()

    while IFS= read -r line; do
        [[ -n "${line//[[:space:]]/}" ]] || continue
        lower="${line,,}"
        if [[ "$lower" =~ (nvidia|10de:) ]]; then
            vendor=nvidia
        elif [[ "$lower" =~ (amd|advanced[[:space:]]micro[[:space:]]devices|1002:) ]]; then
            vendor=amd
        elif [[ "$lower" =~ (intel|8086:) ]]; then
            vendor=intel
        else
            continue
        fi
        [[ -n "${seen[$vendor]:-}" ]] && continue
        seen[$vendor]=1
        found+=("$vendor")
    done <<<"$info"

    if ((${#found[@]})); then
        printf '%s\n' "${found[@]}"
    else
        printf 'unknown\n'
    fi
}

gpu_vendor_label() {
    local vendor result=""
    for vendor in "$@"; do
        case "$vendor" in
            nvidia) result+="${result:+, }NVIDIA" ;;
            amd) result+="${result:+, }AMD" ;;
            intel) result+="${result:+, }Intel" ;;
            unknown) result+="${result:+, }Unknown" ;;
        esac
    done
    printf '%s' "${result:-Unknown}"
}

gpu_has_vendor() {
    local wanted="${1:-}"
    shift || true
    local vendors="${*:-}"
    local normalized="${vendors//$'\n'/ }"
    [[ " $normalized " == *" $wanted "* ]]
}

gpu_is_hybrid() {
    local vendors="${1:-}"
    local vendor count=0

    for vendor in nvidia amd intel; do
        if gpu_has_vendor "$vendor" "$vendors"; then
            count=$((count + 1))
        fi
    done
    ((count > 1))
}

show_hardware_summary() {
    local cpu ram gpu gpu_vendors gpu_label disk storage free_kib hybrid_note=""
    local -a gpu_vendor_list=()
    cpu="$(awk -F: '/model name/ {gsub(/^[ \t]+/, "", $2); print $2; exit}' /proc/cpuinfo 2>/dev/null || true)"
    ram="$(awk '/MemTotal/ {printf "%.1f GiB", $2 / 1048576}' /proc/meminfo 2>/dev/null || printf unknown)"
    gpu="$(detect_system_gpu_info)"
    gpu_vendors="$(detect_gpu_vendors "$gpu")"
    mapfile -t gpu_vendor_list <<<"$gpu_vendors"
    gpu_label="$(gpu_vendor_label "${gpu_vendor_list[@]}")"
    if gpu_is_hybrid "$gpu_vendors"; then
        hybrid_note=" (hybrid graphics detected)"
    fi
    [[ -n "$gpu" ]] || gpu="Not detected (lspci unavailable or no display controller found)"
    disk="$(findmnt -no SOURCE / 2>/dev/null || printf unknown)"
    storage="Not detected"
    if command -v lsblk >/dev/null 2>&1 && [[ "$disk" != unknown ]]; then
        storage="$(lsblk -s -npo NAME,TYPE,SIZE,ROTA,MODEL "$disk" 2>/dev/null |
            awk '$2 == "disk" {
                model=$5
                for (i=6; i<=NF; i++) model=model " " $i
                kind=($4 == 0 ? "non-rotational" : "rotational")
                printf "%s %s (%s, %s)", $1, model, $3, kind
            }' || true)"
        [[ -n "$storage" ]] || storage="Not detected"
    fi
    free_kib="$(df -Pk / 2>/dev/null | awk 'NR == 2 {print $4}' || true)"

    printf '\nHardware summary\n'
    printf '  CPU: %s\n' "${cpu:-unknown}"
    printf '  Memory: %s\n' "$ram"
    printf '  Detected GPU vendor(s): %s%s\n' "$gpu_label" "$hybrid_note"
    printf '  Display adapter(s):\n%s\n' "$gpu"
    printf '  Root filesystem: %s\n' "$disk"
    printf '  Physical storage: %s\n' "$storage"
    if [[ "$free_kib" =~ ^[0-9]+$ ]]; then
        printf '  Free space on /: %.1f GiB\n' "$(awk -v kib="$free_kib" 'BEGIN {print kib / 1048576}')"
        if ((free_kib < 10485760)); then
            log WARN "Less than 10 GiB is free on /; package installation may fail."
        fi
    else
        log WARN "Could not determine free disk space."
    fi
}

package_available() {
    local package="$1"
    ((DRY_RUN)) && return 0
    command -v pacman >/dev/null 2>&1 || return 1
    pacman -Si -- "$package" >/dev/null 2>&1
}

# One pacman call for the common case where every package is available.
packages_available_batch() {
    (($#)) || return 0
    ((DRY_RUN)) && return 0
    command -v pacman >/dev/null 2>&1 || return 1
    pacman -Si -- "$@" >/dev/null 2>&1
}

package_database_ready() {
    compgen -G "/var/lib/pacman/sync/*.db" >/dev/null 2>&1
}

validate_package_name() {
    [[ "$1" =~ ^[a-zA-Z0-9@._+-]+$ ]]
}

package_installed() {
    local package="$1"
    command -v pacman >/dev/null 2>&1 || return 1
    pacman -Q "$package" >/dev/null 2>&1
}

install_available_packages() {
    local package
    local -a unique=()
    local -a available=()
    local -a missing=()
    local -a invalid=()
    local -a to_install=()
    local -a already=()
    local -A seen=()

    for package in "$@"; do
        if ! validate_package_name "$package"; then
            invalid+=("$package")
        elif [[ -z "${seen[$package]:-}" ]]; then
            seen[$package]=1
            unique+=("$package")
        fi
    done

    if ((${#invalid[@]})); then
        log WARN "Invalid package names (skipped): ${invalid[*]}"
    fi
    if ((${#unique[@]} == 0)); then
        log WARN "No valid packages were requested; nothing was installed."
        return 0
    fi

    if ((!DRY_RUN)); then
        local -a candidates=()
        for package in "${unique[@]}"; do
            if package_installed "$package"; then
                already+=("$package")
            else
                candidates+=("$package")
            fi
        done
        unique=("${candidates[@]}")
        if ((${#already[@]})); then
            log INFO "Already installed (skipped): ${already[*]}"
        fi
        if ((${#unique[@]} == 0)); then
            log INFO "All requested packages are already installed; nothing to do."
            return 0
        fi
    fi

    if ((${#unique[@]})) && packages_available_batch "${unique[@]}"; then
        available=("${unique[@]}")
    else
        for package in "${unique[@]}"; do
            if package_available "$package"; then
                available+=("$package")
            else
                missing+=("$package")
            fi
        done
    fi

    if ((${#missing[@]})); then
        log WARN "Unavailable packages (skipped): ${missing[*]}"
        log WARN "If these packages should exist, refresh the package database with: sudo pacman -Syu"
    fi
    if ((${#available[@]} == 0)); then
        log WARN "No requested packages are available; nothing was installed."
        return 0
    fi

    to_install=("${available[@]}")
    log INFO "Installing ${#to_install[@]} package(s): ${to_install[*]}"
    sudo_run pacman -S --needed -- "${to_install[@]}"
    if ((!DRY_RUN)); then
        local -a not_installed=()
        for package in "${to_install[@]}"; do
            package_installed "$package" || not_installed+=("$package")
        done
        if ((${#not_installed[@]})); then
            log WARN "Requested packages that are still missing: ${not_installed[*]}"
        else
            log INFO "All requested packages are installed."
        fi
    fi
}

pacman_conf_path() {
    if [[ -n "${PACMAN_CONF:-}" ]]; then
        if [[ "${ARCHKDE_ALLOW_PACMAN_CONF_OVERRIDE:-0}" != "1" ]]; then
            die "PACMAN_CONF is a test-only override. Refusing to use it in a real run."
        fi
        printf '%s\n' "$PACMAN_CONF"
        return 0
    fi
    printf '/etc/pacman.conf\n'
}

multilib_enabled() {
    local conf
    # In a dry run, a preview selection assumes the offered [multilib] change
    # will be accepted, so later modules show the 32-bit packages too.
    if ((DRY_RUN)) && [[ "${MULTILIB_PREVIEW_ENABLED:-0}" == "1" ]]; then
        return 0
    fi
    conf="$(pacman_conf_path)"
    [[ -r "$conf" ]] || return 1
    awk '
        /^[[:space:]]*\[multilib\][[:space:]]*$/ { in_multilib=1; next }
        /^[[:space:]]*\[[^]]+\][[:space:]]*$/ { in_multilib=0 }
        in_multilib && /^[[:space:]]*Include[[:space:]]*=/ { found=1 }
        END { exit !found }
    ' "$conf"
}

# Print a pacman.conf with the [multilib] section enabled. The input file is
# never modified, so the result can be validated before it is installed.
render_multilib_enabled_pacman_conf() {
    local conf="${1:-}"
    [[ -r "$conf" ]] || return 1
    awk '
        /^[[:space:]]*#?[[:space:]]*\[[^]]+\][[:space:]]*$/ {
            section = $0
            gsub(/[[:space:]]/, "", section)
            if (section == "#[multilib]") {
                sub(/^[[:space:]]*#[[:space:]]*/, "")
                in_multilib = 1
                found = 1
                print
                next
            }
            in_multilib = (section == "[multilib]")
            if (in_multilib) found = 1
            print
            next
        }
        in_multilib && /^[[:space:]]*#[[:space:]]*Include[[:space:]]*=/ {
            sub(/^[[:space:]]*#[[:space:]]*/, "")
            print
            next
        }
        { print }
        END { exit !found }
    ' "$conf"
}

# Confirm that a rendered pacman.conf has an active [multilib] Include line.
multilib_config_has_include() {
    local conf="${1:-}"
    [[ -r "$conf" ]] || return 1
    awk '
        /^[[:space:]]*\[multilib\][[:space:]]*$/ { in_multilib=1; next }
        /^[[:space:]]*\[[^]]+\][[:space:]]*$/ { in_multilib=0 }
        in_multilib && /^[[:space:]]*Include[[:space:]]*=/ { found=1 }
        END { exit !found }
    ' "$conf"
}

# Ask before enabling [multilib], which Steam needs for 32-bit support.
# Returns 1 when the user declines or the change cannot be made safely.
ensure_multilib() {
    local conf tmp answer
    conf="$(pacman_conf_path)"

    if multilib_enabled; then
        log INFO "[multilib] is already enabled."
        return 0
    fi

    if ((DRY_RUN)); then
        export MULTILIB_PREVIEW_ENABLED=1
        log INFO "Dry run: would enable [multilib] in $conf and refresh package databases."
        return 0
    fi

    if [[ ! -r "$conf" ]]; then
        log WARN "Cannot read $conf; enable [multilib] manually to use Steam."
        return 1
    fi
    if [[ -L "$conf" ]]; then
        log WARN "$conf is a symbolic link; leaving it unchanged. Enable [multilib] manually to use Steam."
        return 1
    fi
    if [[ ! -t 0 ]]; then
        log WARN "[multilib] is disabled and no terminal is available to confirm enabling it."
        return 1
    fi

    printf '\nSteam needs 32-bit support from the [multilib] repository.\n'
    printf 'Enabling it also runs a full system upgrade (pacman -Syu).\n'
    read -r -p "Enable [multilib] and upgrade packages now? [Y/n] " answer || answer="n"
    case "${answer,,}" in
        ""|y|yes) ;;
        *)
            log WARN "Leaving [multilib] disabled; Steam and 32-bit libraries may be skipped."
            return 1
            ;;
    esac

    command -v sudo >/dev/null 2>&1 || {
        log WARN "sudo was not found; [multilib] was not changed."
        return 1
    }
    sudo -v || {
        log WARN "sudo authentication failed; [multilib] was not changed."
        return 1
    }

    tmp="$(mktemp)" || {
        log WARN "Could not create a temporary file; $conf was not changed."
        return 1
    }
    if ! render_multilib_enabled_pacman_conf "$conf" >"$tmp" ||
        ! multilib_config_has_include "$tmp"; then
        rm -f -- "$tmp"
        log WARN "Could not prepare a safe [multilib] configuration; $conf was not changed."
        return 1
    fi

    if ! backup_file "$conf" pacman.conf; then
        rm -f -- "$tmp"
        log WARN "Could not back up $conf; [multilib] was not changed."
        return 1
    fi

    if ! sudo_run install -D -m 0644 -- "$tmp" "$conf"; then
        rm -f -- "$tmp"
        log WARN "Could not update $conf; [multilib] was not changed."
        return 1
    fi
    rm -f -- "$tmp"
    record_change "modified" "$conf" "multilib-enabled" "-"
    log INFO "Enabled [multilib] in $conf."

    # Refresh the package databases so Steam and 32-bit libraries are visible.
    if ! sudo_run pacman -Syu; then
        log WARN "[multilib] is enabled, but the package refresh failed. Run 'sudo pacman -Syu' before installing Steam."
        return 1
    fi
    log INFO "[multilib] is ready."
    return 0
}

# Enable services without failing the whole module when a unit is missing or
# already enabled. Returns 1 only when the unit could not be enabled at all.
enable_service() {
    local unit="$1"
    local start="${2:-0}"

    if ! command -v systemctl >/dev/null 2>&1; then
        log WARN "systemctl was not found; cannot enable $unit."
        return 1
    fi

    if ((DRY_RUN)); then
        run sudo systemctl enable "$unit"
        ((start)) && run sudo systemctl start "$unit"
        return 0
    fi

    if systemctl is-enabled --quiet "$unit" 2>/dev/null; then
        log INFO "Service $unit is already enabled."
    elif ! sudo_run systemctl enable "$unit"; then
        log WARN "Could not enable $unit; continuing without it."
        return 1
    else
        log INFO "Enabled service $unit."
    fi

    if ((start)) && ! systemctl is-active --quiet "$unit" 2>/dev/null; then
        sudo_run systemctl start "$unit" || log WARN "Could not start $unit; it may start on next boot."
    fi
    return 0
}

enable_services() {
    local unit
    for unit in "$@"; do
        enable_service "$unit" || true
    done
}

# Never switch the login manager automatically. If another display manager is
# already enabled, leave it alone and explain how to change it manually.
enable_display_manager() {
    local wanted="$1"
    local current=""
    local dm

    for dm in gdm lightdm greetd ly sddm; do
        if systemctl is-enabled --quiet "$dm.service" 2>/dev/null; then
            current="$dm"
            break
        fi
    done

    if [[ -n "$current" && "$current" != "$wanted" ]]; then
        log WARN "Display manager '$current' is already enabled; not switching to $wanted automatically."
        log WARN "To use $wanted, disable $current first and then enable $wanted.service."
        return 0
    fi
    enable_service "$wanted.service"
}

enable_user_service() {
    local unit="$1"

    if ((DRY_RUN)); then
        run systemctl --user enable --now "$unit"
        return 0
    fi
    if ! command -v systemctl >/dev/null 2>&1 || [[ -z "${XDG_RUNTIME_DIR:-}" ]]; then
        log WARN "Cannot manage the user service $unit outside a graphical login session."
        return 1
    fi
    if systemctl --user enable --now "$unit" >/dev/null 2>&1; then
        log INFO "Enabled user service $unit."
    else
        log WARN "Could not enable user service $unit; it may start automatically when needed."
        return 1
    fi
}

# Add the Flathub remote system-wide if it is missing.
ensure_flathub_remote() {
    local url="https://flathub.org/repo/flathub.flatpakrepo"

    if ((DRY_RUN)); then
        run sudo flatpak remote-add --if-not-exists flathub "$url"
        return 0
    fi

    if ! command -v flatpak >/dev/null 2>&1; then
        log WARN "Flatpak is not installed; Flathub was not configured."
        return 1
    fi

    if flatpak remotes --system 2>/dev/null | awk '{print $1}' | grep -qx 'flathub'; then
        log INFO "Flathub is already configured system-wide."
        return 0
    fi
    if ! sudo_run flatpak remote-add --if-not-exists flathub "$url"; then
        log WARN "Could not add the Flathub remote; check your internet connection and try again."
        return 1
    fi
    log INFO "Added the Flathub remote system-wide."
}

record_change() {
    local kind="$1"
    local target="$2"
    local detail="${3:--}"
    local source="${4:--}"
    local manifest_dir
    ((DRY_RUN)) && return 0
    manifest_dir="$(dirname -- "$MANIFEST_FILE")"
    mkdir -p -- "$manifest_dir"
    if path_within_state "$manifest_dir"; then
        chmod 700 -- "$manifest_dir" 2>/dev/null || true
    fi
    printf '%s|%s|%s|%s\n' "$kind" "$target" "$detail" "$source" >>"$MANIFEST_FILE"
    if path_within_state "$MANIFEST_FILE"; then
        chmod 600 -- "$MANIFEST_FILE" 2>/dev/null || true
    fi
}

file_sha256() {
    sha256sum -- "$1" 2>/dev/null | awk '{print $1}'
}

tracked_change_count() {
    if [[ -f "$MANIFEST_FILE" ]]; then
        awk -F'|' '$1 == "created" { count++ } END { print count + 0 }' "$MANIFEST_FILE"
    else
        printf '0\n'
    fi
}

backup_file() {
    local target="$1"
    local label="${2:-$(basename -- "$target")}"
    local stamp backup
    stamp="$(date +%Y%m%d-%H%M%S)"
    backup="$BACKUP_DIR/$stamp/$label"
    if ((DRY_RUN)); then
        run sudo cp -aL -- "$target" "$backup"
        log INFO "Dry run: would back up $target to $backup"
        return 0
    fi
    mkdir -p -- "$BACKUP_DIR/$stamp"
    if path_within_state "$BACKUP_DIR"; then
        chmod 700 -- "$BACKUP_DIR" "$BACKUP_DIR/$stamp" 2>/dev/null || true
    fi
    # -n avoids an unexpected password prompt in non-interactive runs; the
    # installer authenticates sudo before any module starts, so this succeeds
    # there without prompting.
    if ! sudo -n cp -aL -- "$target" "$backup" 2>/dev/null; then
        log WARN "Could not back up $target; it will be left untouched."
        return 1
    fi
    sudo chown "$(id -u):$(id -g)" -- "$backup" 2>/dev/null || true
    if path_within_state "$backup"; then
        sudo chmod 600 -- "$backup" 2>/dev/null || true
    fi
    record_change "backup" "$target" "$backup" "-"
    log INFO "Backed up $target to $backup"
}

ensure_managed_config() {
    local source_file="$1"
    local target_file="$2"
    local digest
    if [[ -L "$target_file" ]]; then
        log WARN "Target is a symbolic link; leaving it unchanged: $target_file"
        return 0
    fi
    if [[ -e "$target_file" ]]; then
        if cmp -s -- "$source_file" "$target_file"; then
            log INFO "Managed configuration already matches: $target_file"
        else
            log WARN "Existing configuration differs; it will not be overwritten: $target_file"
            backup_file "$target_file" "$(basename -- "$target_file")" ||
                log WARN "A backup could not be created; the existing file is still untouched."
        fi
        return 0
    fi
    if ((DRY_RUN)); then
        run sudo install -D -m 0644 -- "$source_file" "$target_file"
        log INFO "Dry run: would install managed configuration: $target_file"
        return 0
    fi
    sudo_run install -D -m 0644 -- "$source_file" "$target_file"
    digest="$(file_sha256 "$target_file")"
    record_change "created" "$target_file" "$digest" "$source_file"
    log INFO "Installed managed configuration: $target_file"
}
