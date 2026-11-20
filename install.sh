#!/usr/bin/env bash

if [ -z "${BASH_VERSION:-}" ]; then
    printf 'Run this installer with bash, not sh.\n' >&2
    exit 1
fi

if ((EUID == 0)); then
    printf 'Run this installer as a regular user, not root.\n' >&2
    exit 1
fi

set -Eeuo pipefail

# Decide about colour before lib/common.sh is sourced, because the installer
# sends all output through tee (which would otherwise hide the terminal).
for arg in "$@"; do
    if [[ "$arg" == "--no-color" ]]; then
        export NO_COLOR=1
    fi
done
if [[ -t 1 && -z "${NO_COLOR:-}" && "${TERM:-dumb}" != "dumb" ]]; then
    export SETUP_FORCE_COLOR=1
fi

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Remote one-command bootstrap
#
# The README tells users to download only this file, for example:
#   curl -fsSL .../install.sh -o archkde-install.sh
#   bash archkde-install.sh
#
# When the rest of the repository is not present, this file downloads the
# repository archive over HTTPS, verifies it against SHA256SUMS, and launches
# the real installer. A downloaded file is never piped directly into a shell.
# ---------------------------------------------------------------------------
ARCHKDE_REPO="${ARCHKDE_REPO:-Sopanhaa/archKDE-play}"
ARCHKDE_REF="${ARCHKDE_REF:-main}"
ARCHKDE_REPO_URL="${ARCHKDE_REPO_URL:-https://github.com/${ARCHKDE_REPO}}"
ARCHKDE_RAW_URL="${ARCHKDE_RAW_URL:-https://raw.githubusercontent.com/${ARCHKDE_REPO}/${ARCHKDE_REF}}"
ARCHKDE_ARCHIVE_URL="${ARCHKDE_ARCHIVE_URL:-${ARCHKDE_REPO_URL}/archive/${ARCHKDE_REF}.tar.gz}"
ARCHKDE_CHECKSUM_URL="${ARCHKDE_CHECKSUM_URL:-${ARCHKDE_RAW_URL}/SHA256SUMS}"
BOOTSTRAP_TMP=""

bootstrap_die() {
    printf '\nERROR: %s\n' "$*" >&2
    exit 1
}

bootstrap_cleanup() {
    if [[ -n "$BOOTSTRAP_TMP" && -d "$BOOTSTRAP_TMP" ]]; then
        rm -rf -- "$BOOTSTRAP_TMP"
    fi
}

bootstrap_scheme_allowed() {
    local url="$1"
    case "$url" in
        https://*) return 0 ;;
        file://*|http://*) [[ "${ARCHKDE_ALLOW_INSECURE_SOURCE:-0}" == "1" ]] ;;
        *) return 1 ;;
    esac
}

bootstrap_download() {
    local url="$1"
    local dest="$2"

    bootstrap_scheme_allowed "$url" ||
        bootstrap_die "Refusing a non-HTTPS download URL: $url (set ARCHKDE_ALLOW_INSECURE_SOURCE=1 only for local testing)."

    if [[ "$url" == file://* ]]; then
        if ! cp -- "${url#file://}" "$dest"; then
            bootstrap_die "Could not copy the local installer archive: ${url#file://}"
        fi
        return 0
    fi

    if command -v curl >/dev/null 2>&1; then
        if [[ "$url" == https://* ]]; then
            if ! curl -fL --proto '=https' --proto-redir '=https' --tlsv1.2 \
                --retry 2 --connect-timeout 15 --max-time 180 \
                -o "$dest" -- "$url"; then
                bootstrap_die "Download failed: $url"
            fi
        elif ! curl -fL --retry 2 --connect-timeout 15 --max-time 180 \
            -o "$dest" -- "$url"; then
            bootstrap_die "Download failed: $url"
        fi
        return 0
    fi

    if command -v wget >/dev/null 2>&1; then
        if [[ "$url" == https://* ]]; then
            if ! wget -q --https-only --timeout=30 --tries=2 -O "$dest" -- "$url"; then
                bootstrap_die "Download failed: $url"
            fi
        elif ! wget -q --timeout=30 --tries=2 -O "$dest" -- "$url"; then
            bootstrap_die "Download failed: $url"
        fi
        return 0
    fi

    bootstrap_die "curl or wget is required to download the installer."
}

bootstrap_file_sha256() {
    local file="$1"
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum -- "$file" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 -- "$file" | awk '{print $1}'
    else
        return 1
    fi
}

bootstrap_verify_manifest() {
    local root="$1"
    local manifest="$2"
    local required

    command -v sha256sum >/dev/null 2>&1 ||
        bootstrap_die "sha256sum is required to verify the downloaded installer."
    if ! awk '
        {
            path = $0
            sub(/^[^[:space:]]+[[:space:]]+\*?/, "", path)
            if (path ~ /^\// || path ~ /(^|\/)\.\.(\/|$)/) {
                exit 1
            }
        }
    ' "$manifest"; then
        bootstrap_die "SHA256SUMS contains an unsafe path."
    fi
    for required in \
        install.sh \
        lib/common.sh \
        lib/modules.sh \
        lib/ui.sh \
        lib/preflight.sh \
        modules/01-system.sh \
        config/packages.conf; do
        if ! awk -v file="$required" '$2 == file { found = 1 } END { exit !found }' "$manifest"; then
            bootstrap_die "SHA256SUMS does not cover a required file: $required"
        fi
    done
    if ! (cd "$root" && sha256sum -c --strict --quiet -- "$manifest"); then
        bootstrap_die "Checksum verification failed. The download may be corrupt or tampered with. Delete the file and try again."
    fi
}

bootstrap_remote_installer() {
    local archive manifest listing verbose extract root actual status entry
    local persist=1 persist_root staging expected_entry entry_hash verify_entry=0
    local -a top_entries=()

    for entry in "$@"; do
        case "$entry" in
            --help|-h|--version|--list-modules|--check|--preflight|--dry-run)
                persist=0
                ;;
        esac
    done

    [[ "$ARCHKDE_REPO" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*/[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] ||
        bootstrap_die "ARCHKDE_REPO must look like owner/repository."
    [[ "$ARCHKDE_REPO" != *".."* ]] ||
        bootstrap_die "ARCHKDE_REPO contains an unsafe path segment."
    [[ "$ARCHKDE_REF" =~ ^[A-Za-z0-9][A-Za-z0-9._/-]*$ ]] ||
        bootstrap_die "ARCHKDE_REF contains unsupported characters."
    if [[ "$ARCHKDE_REF" == *".."* || "$ARCHKDE_REF" == *"//"* || "$ARCHKDE_REF" == */ ]]; then
        bootstrap_die "ARCHKDE_REF contains an unsafe path segment."
    fi

    if [[ "${ARCHKDE_BOOTSTRAPPED:-0}" == "1" ]]; then
        bootstrap_die "The downloaded installer is incomplete (lib/ or modules/ is missing)."
    fi

    command -v tar >/dev/null 2>&1 ||
        bootstrap_die "tar is required to unpack the installer."

    if [[ "${ARCHKDE_SKIP_CHECKSUM:-0}" == "1" &&
        "${ARCHKDE_ALLOW_INSECURE_SOURCE:-0}" != "1" ]]; then
        bootstrap_die "Refusing to skip checksum verification for a remote installer. Use a local test source or verify SHA256SUMS."
    fi

    trap bootstrap_cleanup EXIT
    BOOTSTRAP_TMP="$(mktemp -d)" ||
        bootstrap_die "Could not create a temporary directory."
    chmod 700 -- "$BOOTSTRAP_TMP"

    printf '\narchKDE-play remote installer\n'
    printf 'Repository: %s (%s)\n' "$ARCHKDE_REPO" "$ARCHKDE_REF"
    printf 'Downloading the repository archive over HTTPS...\n'

    archive="$BOOTSTRAP_TMP/archkde-play.tar.gz"
    bootstrap_download "$ARCHKDE_ARCHIVE_URL" "$archive"
    [[ -s "$archive" ]] || bootstrap_die "The downloaded archive is empty."

    # If the user pinned the archive hash, verify it before unpacking anything.
    if [[ -n "${ARCHKDE_SHA256:-}" ]]; then
        actual="$(bootstrap_file_sha256 "$archive")" ||
            bootstrap_die "sha256sum or shasum is required to verify ARCHKDE_SHA256."
        if [[ "${actual,,}" != "${ARCHKDE_SHA256,,}" ]]; then
            bootstrap_die "Archive SHA256 does not match ARCHKDE_SHA256."
        fi
        printf '  [OK] Archive SHA256 matches ARCHKDE_SHA256.\n'
    else
        actual="$(bootstrap_file_sha256 "$archive" || true)"
        if [[ -n "$actual" ]]; then
            printf '  Archive SHA256: %s\n' "$actual"
        fi
        printf '  Set ARCHKDE_SHA256=<hash> to pin the archive hash as well.\n'
    fi

    listing="$BOOTSTRAP_TMP/archive.list"
    if ! tar -tzf "$archive" >"$listing" 2>/dev/null; then
        bootstrap_die "The downloaded file is not a valid .tar.gz archive."
    fi
    while IFS= read -r entry; do
        [[ -n "$entry" ]] || continue
        case "$entry" in
            /*) bootstrap_die "Archive contains an absolute path: $entry" ;;
        esac
        case "/$entry/" in
            */../*) bootstrap_die "Archive contains an unsafe path: $entry" ;;
        esac
    done <"$listing"

    verbose="$BOOTSTRAP_TMP/archive.verbose"
    if ! tar -tvzf "$archive" >"$verbose" 2>/dev/null; then
        bootstrap_die "Could not inspect the installer archive."
    fi
    while IFS= read -r entry; do
        case "${entry:0:1}" in
            -|d) ;;
            *) bootstrap_die "Archive contains an unsupported entry type: $entry" ;;
        esac
    done <"$verbose"

    extract="$BOOTSTRAP_TMP/extract"
    mkdir -p -- "$extract"
    if ! tar -xzf "$archive" -C "$extract" \
        --no-same-owner --no-same-permissions 2>/dev/null; then
        bootstrap_die "Could not unpack the installer archive."
    fi

    shopt -s nullglob
    top_entries=("$extract"/*)
    shopt -u nullglob
    ((${#top_entries[@]} == 1)) ||
        bootstrap_die "Unexpected archive layout; expected one top-level directory."
    root="${top_entries[0]}"
    [[ -d "$root" ]] || bootstrap_die "The unpacked installer directory is missing."

    local required
    for required in \
        install.sh \
        lib/common.sh \
        lib/modules.sh \
        lib/ui.sh \
        lib/preflight.sh \
        modules/01-system.sh \
        config/packages.conf; do
        [[ -f "$root/$required" ]] ||
            bootstrap_die "The downloaded installer is incomplete: missing $required"
    done

    if [[ "${ARCHKDE_SKIP_CHECKSUM:-0}" == "1" ]]; then
        printf 'WARNING: checksum verification skipped (ARCHKDE_SKIP_CHECKSUM=1).\n' >&2
    else
        printf 'Downloading SHA256SUMS and verifying installer files...\n'
        manifest="$BOOTSTRAP_TMP/SHA256SUMS"
        bootstrap_download "$ARCHKDE_CHECKSUM_URL" "$manifest"
        bootstrap_verify_manifest "$root" "$manifest"
        printf '  [OK] Installer files match SHA256SUMS.\n'

        # On the default main branch, verify the entry script itself against the
        # same manifest. This catches a stale or modified downloaded entry file.
        if [[ -f "${BASH_SOURCE[0]}" ]]; then
            if [[ "$ARCHKDE_REF" == "main" &&
                "$ARCHKDE_ARCHIVE_URL" == "${ARCHKDE_REPO_URL}/archive/main.tar.gz" &&
                "$ARCHKDE_CHECKSUM_URL" == "${ARCHKDE_RAW_URL}/SHA256SUMS" ]]; then
                verify_entry=1
            fi
            if [[ "${ARCHKDE_ALLOW_INSECURE_SOURCE:-0}" == "1" ]]; then
                verify_entry=1
            fi
        fi
        if ((verify_entry)); then
            expected_entry="$(awk '$2 == "install.sh" { print $1; exit }' "$manifest")"
            entry_hash="$(bootstrap_file_sha256 "${BASH_SOURCE[0]}" || true)"
            if [[ -n "$expected_entry" && -n "$entry_hash" &&
                "$entry_hash" != "$expected_entry" ]]; then
                bootstrap_die "The downloaded entry script does not match SHA256SUMS. Delete it, download it again, and retry."
            fi
            printf '  [OK] Entry script matches SHA256SUMS.\n'
        fi
    fi

    if ((persist)) && [[ -n "${HOME:-}" ]]; then
        persist_root="${XDG_DATA_HOME:-${HOME}/.local/share}/archkde-play/source"
        staging="${persist_root}.new.$$"
        if ! mkdir -p -- "$(dirname -- "$persist_root")"; then
            printf 'WARNING: could not create the installer source directory; continuing from a temporary directory.\n' >&2
        elif {
            rm -rf -- "$staging"
            cp -a -- "$root" "$staging"
        }; then
            rm -rf -- "$persist_root"
            if mv -- "$staging" "$persist_root"; then
                root="$persist_root"
                chmod 700 -- "$root" 2>/dev/null || true
                printf '  Installer source saved to: %s\n' "$root"
            else
                rm -rf -- "$staging"
                printf 'WARNING: could not save the installer source; continuing from a temporary directory.\n' >&2
            fi
        else
            rm -rf -- "$staging"
            printf 'WARNING: could not save the installer source; continuing from a temporary directory.\n' >&2
        fi
    fi

    export ARCHKDE_BOOTSTRAPPED=1
    export ARCHKDE_VERSION="$ARCHKDE_REF"
    printf '\nLaunching the installer...\n\n'

    if bash "$root/install.sh" "$@"; then
        exit 0
    else
        status=$?
        exit "$status"
    fi
}

if [[ ! -f "$ROOT_DIR/lib/common.sh" ||
    ! -f "$ROOT_DIR/lib/modules.sh" ||
    ! -f "$ROOT_DIR/lib/ui.sh" ||
    ! -f "$ROOT_DIR/lib/preflight.sh" ||
    ! -f "$ROOT_DIR/config/packages.conf" ||
    ! -d "$ROOT_DIR/modules" ]]; then
    bootstrap_remote_installer "$@"
fi

source "$ROOT_DIR/lib/common.sh"
source "$ROOT_DIR/lib/modules.sh"
source "$ROOT_DIR/lib/ui.sh"
source "$ROOT_DIR/lib/preflight.sh"

DRY_RUN=0
SELECTION=""
SELECTION_SET=0
FULL_INSTALL=0
PROFILE=""
PROFILE_SET=0
CHECK_ONLY=0
MENU_SELECTED=0
CURRENT_MODULE=""
CURRENT_MODULE_LABEL=""
MODULES_COMPLETED=()

usage() {
    cat <<'EOF'
Usage: ./install.sh [options]
       bash archkde-install.sh [options]   (downloaded entry script)

One-command install:
  curl -fsSL https://raw.githubusercontent.com/Sopanhaa/archKDE-play/main/install.sh -o archkde-install.sh
  bash archkde-install.sh

Recommended:
  ./install.sh                  Show the setup menu.
  ./install.sh --recommended    Install the recommended gaming setup.
  ./install.sh --gaming         Install gaming tools only (KDE already installed).
  ./install.sh --dry-run        Preview everything without changing anything.

Options:
  --dry-run       Preview every action without changing the system.
  --full          Install all modules, including optional virtualization.
  --recommended   Install the recommended gaming setup (modules 01-07).
  --gaming        Install gaming essentials only (modules 03, 05, 06, 07).
  --modules LIST  Install selected modules (e.g. 03,05,06 or 3-5).
  --check         Run preflight checks only and exit.
  --list-modules  Show module numbers, titles, and descriptions.
  --version       Show the project version.
  --quiet         Show warnings and errors only (everything is still logged).
  --no-color      Disable coloured terminal output.
  --help, -h      Show this help.

Menu options:
  1  Quick Setup (recommended)
  2  Custom Setup
  3  GPU Drivers
  4  Gaming Apps
  5  Performance Tools
  6  System Check
  0  Exit

Advanced custom selection:
  Enter module numbers such as:
    03 05 06        specific modules
    03-06           a range
    all             every module

No option ever formats disks, edits bootloader entries, or reboots.
EOF
}

project_version() {
    local version=""
    if command -v git >/dev/null 2>&1 &&
        git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        version="$(git -C "$ROOT_DIR" describe --tags --always --dirty 2>/dev/null || true)"
    fi
    printf '%s\n' "${version:-${ARCHKDE_VERSION:-dev}}"
}

while (($#)); do
    case "$1" in
        --dry-run) DRY_RUN=1 ;;
        --full|--all) FULL_INSTALL=1 ;;
        --recommended|--recommend) PROFILE="recommended"; PROFILE_SET=1 ;;
        --gaming|--gaming-only) PROFILE="gaming"; PROFILE_SET=1 ;;
        --modules)
            (($# >= 2)) || die "--modules requires a comma-separated module list."
            SELECTION="$2"
            SELECTION_SET=1
            shift
            ;;
        --modules=*)
            SELECTION="${1#*=}"
            SELECTION_SET=1
            ;;
        --check|--preflight) CHECK_ONLY=1 ;;
        --list-modules) list_modules; exit 0 ;;
        --version) printf 'archKDE-play %s\n' "$(project_version)"; exit 0 ;;
        --quiet) SETUP_QUIET=1; export SETUP_QUIET ;;
        --no-color) export NO_COLOR=1 ;;
        --help|-h) usage; exit 0 ;;
        *) die "Unknown option: $1 (use --help)." ;;
    esac
    shift
done

selected_modes=$((FULL_INSTALL + PROFILE_SET + SELECTION_SET))
if ((selected_modes > 1)); then
    die "Use only one of --full, --recommended, --gaming, or --modules."
fi
if ((SELECTION_SET)) && [[ -z "${SELECTION//[[:space:]]/}" ]]; then
    die "--modules requires at least one module number."
fi

print_common_fixes() {
    printf '  Common fixes:\n'
    printf '    - Check your internet connection and try again.\n'
    printf '    - If pacman is locked, wait for other updates to finish.\n'
    printf '    - If a package is missing, run: sudo pacman -Syu\n'
    printf '    - For NVIDIA with Secure Boot, sign your kernel modules first.\n'
}

on_error() {
    local status="$1"
    local line="$2"
    local command="$3"
    trap - ERR

    printf '\n'
    log ERROR "Setup stopped unexpectedly (exit status $status, line $line)."
    log ERROR "Failed command: $command"
    if [[ -n "$CURRENT_MODULE" ]]; then
        log ERROR "While running module $CURRENT_MODULE: $CURRENT_MODULE_LABEL"
    fi
    log ERROR "No changes were rolled back automatically."
    if ((DRY_RUN || CHECK_ONLY)); then
        log ERROR "Logging is disabled in dry-run/check mode."
    else
        log ERROR "Read the full log here: $LOG_FILE"
    fi
    log ERROR "Review project-managed changes with: bash \"$ROOT_DIR/scripts/rollback.sh\" --dry-run"
    log ERROR "Fix the problem above, then rerun the same command. Completed modules are safe to rerun."
    print_common_fixes
    exit "$status"
}

on_interrupt() {
    local signal="$1"
    trap - INT TERM
    printf '\n'
    log WARN "Installation interrupted ($signal). No automatic rollback was performed."
    if ((DRY_RUN || CHECK_ONLY)); then
        log WARN "Logging is disabled in dry-run/check mode."
    else
        log WARN "Review the log before rerunning: $LOG_FILE"
    fi
    exit 130
}

trap 'on_error "$?" "$LINENO" "$BASH_COMMAND"' ERR
trap 'on_interrupt INT' INT
trap 'on_interrupt TERM' TERM

if ((SELECTION_SET)); then
    requested_selection="$SELECTION"
    if ! SELECTION="$(parse_module_selection "$requested_selection")"; then
        die "Invalid module selection: '$requested_selection'. Use numbers from 01 to 08, a range like 03-05, or all."
    fi
fi

choose_modules() {
    if ((MENU_SELECTED)); then
        return 0
    fi

    if ((SELECTION_SET)); then
        SELECTED_MODULES="$SELECTION"
        return 0
    fi

    if ((FULL_INSTALL)); then
        SELECTED_MODULES="$ALL_MODULES"
        return 0
    fi

    if ((PROFILE_SET)); then
        SELECTED_MODULES="$(profile_modules "$PROFILE")" || {
            die "Unknown setup profile: $PROFILE"
        }
        return 0
    fi

    if [[ ! -t 0 ]]; then
        die "Interactive input is unavailable. Use --recommended, --gaming, --full, --modules LIST, or --check."
    fi
    interactive_select
}

# Show the setup menu before the checks so the user can also choose the
# "System Check" option.
if ((!CHECK_ONLY && !SELECTION_SET && !FULL_INSTALL && !PROFILE_SET)); then
    if [[ ! -t 0 ]]; then
        printf 'Interactive input is unavailable. Use --recommended, --gaming, --full, --modules LIST, or --check.\n' >&2
        exit 1
    fi
    if ! interactive_select; then
        printf '\n  Installation cancelled. Nothing was changed.\n'
        exit 0
    fi
fi

# Initialize logging after the menu so interactive UI output stays out of the
# log file and quitting from the menu does not create state files.
if ((DRY_RUN || CHECK_ONLY)); then
    export LOG_FILE="/dev/null"
    export LOG_TEE=0
else
    init_logging
    export LOG_FILE
    export LOG_TEE=1
    exec > >(tee -a "$LOG_FILE") 2>&1
fi

if ((DRY_RUN || CHECK_ONLY)); then
    log WARN "Log file: not written (dry-run/check mode)."
else
    log INFO "Log file: $LOG_FILE"
fi

if ! run_preflight_checks; then
    exit 1
fi
show_hardware_summary

if ((CHECK_ONLY)); then
    section "Check complete"
    log INFO "Preflight checks finished. No packages or configuration files were changed."
    exit 0
fi

show_recommendation

if ! choose_modules; then
    log INFO "Installation cancelled. Nothing was changed."
    exit 0
fi

show_selection
read -r -a selected_module_numbers <<<"$SELECTED_MODULES"
module_count="${#selected_module_numbers[@]}"

# Fail before changing anything if a configured module has no script.
declare -A module_paths=()
for number in "${selected_module_numbers[@]}"; do
    module_file="$(module_script "$number")" || true
    [[ -n "$module_file" ]] || die "Module $number is missing from $ROOT_DIR/modules."
    module_paths["$number"]="$module_file"
done

if ((DRY_RUN)); then
    log WARN "Dry run enabled; commands are printed but no system changes will be made."
else
    printf '\nThe installer will use sudo to install packages and enable services.\n'
    printf 'It never formats disks, edits bootloader entries, or reboots automatically.\n'
    read -r -p "Proceed with installation? [y/N] " answer || answer=""
    if [[ ! "$answer" =~ ^[Yy]$ ]]; then
        log INFO "Installation cancelled. Nothing was changed."
        exit 0
    fi
    command -v sudo >/dev/null 2>&1 || die "sudo is required for system changes."
    log INFO "Requesting sudo access..."
    sudo -v || die "sudo authentication failed; nothing was changed."
fi

# Steam needs [multilib]. Enable it before any module runs so the GPU module
# also installs matching 32-bit graphics libraries.
if [[ " $SELECTED_MODULES " == *" 05 "* ]]; then
    if ! ensure_multilib; then
        log WARN "Continuing without [multilib]; Steam and some 32-bit libraries may be skipped."
    fi
fi

module_index=0
for number in "${selected_module_numbers[@]}"; do
    module_index=$((module_index + 1))
    CURRENT_MODULE="$number"
    CURRENT_MODULE_LABEL="$(module_title "$number")"

    if ((!DRY_RUN)) && ! sudo -v; then
        die "sudo authentication failed; rerun after fixing your sudo access."
    fi

    while true; do
        ui_step "[$module_index/$module_count] $CURRENT_MODULE_LABEL"
        log INFO "Starting module $number ($module_index/$module_count)."
        module_start=$SECONDS

        if DRY_RUN="$DRY_RUN" SETUP_MODULE_NUMBER="$number" \
            SETUP_MODULE_INDEX="$module_index" SETUP_MODULE_TOTAL="$module_count" \
            bash "${module_paths[$number]}"; then
            elapsed=$((SECONDS - module_start))
            MODULES_COMPLETED+=("$number")
            ui_done "[$module_index/$module_count] $CURRENT_MODULE_LABEL ($(format_duration "$elapsed"))"
            log INFO "Module $number finished successfully in $(format_duration "$elapsed")."
            break
        else
            status=$?
            ui_error_step "[$module_index/$module_count] $CURRENT_MODULE_LABEL failed"
            log ERROR "Module $number ($CURRENT_MODULE_LABEL) failed with exit status $status."
            log ERROR "No changes were rolled back automatically. Review the log: $LOG_FILE"
            log ERROR "Fix the reported problem, then rerun this module with: bash \"$ROOT_DIR/install.sh\" --modules $number"
            print_common_fixes

            if ((DRY_RUN)) || [[ ! -t 0 ]]; then
                exit "$status"
            fi

            read -r -p "Retry this module? [y/N] " retry || retry=""
            if [[ "$retry" =~ ^[Yy]$ ]]; then
                log WARN "Retrying module $number..."
                continue
            fi
            exit "$status"
        fi
    done
done

CURRENT_MODULE=""
CURRENT_MODULE_LABEL=""

section "Setup complete"
if ((${#MODULES_COMPLETED[@]})); then
    for number in "${MODULES_COMPLETED[@]}"; do
        ui_done "$number  $(module_title "$number")"
    done
fi
if ((DRY_RUN)); then
    printf '  Mode: dry run (nothing was changed)\n'
else
    printf '  Mode: installation\n'
fi
if ((DRY_RUN)); then
    printf '  Log file: not written (dry run)\n'
else
    printf '  Log file: %s\n' "$LOG_FILE"
fi
if ((!DRY_RUN)); then
    printf '  Tracked configuration changes: %s\n' "$(tracked_change_count)"
    printf '  Review rollback with: bash %q --dry-run\n' "$ROOT_DIR/scripts/rollback.sh"
fi
printf '\nNext steps:\n'
if [[ " $SELECTED_MODULES " == *" 02 "* || " $SELECTED_MODULES " == *" 03 "* ]]; then
    printf '  - Reboot when convenient so the new kernel and GPU drivers load.\n'
fi
if [[ " $SELECTED_MODULES " == *" 08 "* ]]; then
    printf '  - Sign out and back in if this setup added you to the libvirt group.\n'
fi
printf '  - Run bash %q to verify the installation.\n' "$ROOT_DIR/scripts/health-check.sh"
if [[ " $SELECTED_MODULES " == *" 02 "* ]]; then
    printf '  - Check your bootloader menu before rebooting to use linux-zen.\n'
fi
printf '  - Launch Steam from the application menu, then enable Steam Play in Settings.\n'
printf '\nThis installer did not reboot your computer or modify boot entries.\n'
