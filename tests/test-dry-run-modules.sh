#!/usr/bin/env bash
set -Eeuo pipefail

# Exercise every installer module in dry-run mode with mocked system tools.
# No package manager, service manager, or sudo command is ever executed.

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf -- "$tmp_dir"' EXIT

bin_dir="$tmp_dir/bin"
marker="$tmp_dir/system-changes"
mkdir -p -- "$bin_dir"

cat >"$bin_dir/sudo" <<'EOF'
#!/usr/bin/env bash
printf 'sudo %s\n' "$*" >>"$SETUP_TEST_MARKER"
exit 0
EOF

cat >"$bin_dir/pacman" <<'EOF'
#!/usr/bin/env bash
case " $* " in
    *" -S "* | *" -Syu "* | *" -Sy "* | *" -U "*)
        printf 'pacman %s\n' "$*" >>"$SETUP_TEST_MARKER"
        ;;
esac
case " $* " in
    *" -Q "*) exit 1 ;;
    *" -Si "*) exit 0 ;;
esac
exit 0
EOF

cat >"$bin_dir/systemctl" <<'EOF'
#!/usr/bin/env bash
case "$1" in
    list-unit-files)
        shift
        printf '%s\n' "${@: -1}"
        exit 0
        ;;
    is-enabled | is-active) exit 1 ;;
    enable | start | disable | stop | daemon-reload)
        printf 'systemctl %s\n' "$*" >>"$SETUP_TEST_MARKER"
        exit 0
        ;;
esac
exit 0
EOF

cat >"$bin_dir/flatpak" <<'EOF'
#!/usr/bin/env bash
case "$1" in
    install | remote-add | uninstall)
        printf 'flatpak %s\n' "$*" >>"$SETUP_TEST_MARKER"
        ;;
    remotes) exit 0 ;;
    info | remote-info) exit 1 ;;
esac
exit 0
EOF

cat >"$bin_dir/lspci" <<'EOF'
#!/usr/bin/env bash
printf '01:00.0 VGA compatible controller: NVIDIA Corporation (10de:2504)\n'
EOF

cat >"$bin_dir/findmnt" <<'EOF'
#!/usr/bin/env bash
printf '/dev/sda1\n'
EOF

cat >"$bin_dir/lsblk" <<'EOF'
#!/usr/bin/env bash
printf '0\n'
EOF

cat >"$bin_dir/bootctl" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

cat >"$bin_dir/mokutil" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF

chmod +x "$bin_dir"/*

export PATH="$bin_dir:$PATH"
export XDG_STATE_HOME="$tmp_dir/state"
export LOG_FILE="$tmp_dir/test.log"
export MANIFEST_FILE="$tmp_dir/rollback/manifest.txt"
export BACKUP_DIR="$tmp_dir/backups"
export PACMAN_CONF="$tmp_dir/pacman.conf"
export ARCHKDE_ALLOW_PACMAN_CONF_OVERRIDE=1
export SETUP_TEST_MARKER="$marker"
export DRY_RUN=1
export NO_COLOR=1
export TERM=dumb
export SETUP_QUIET=0

cat >"$PACMAN_CONF" <<'EOF'
[options]
HoldPkg = pacman glibc

#[multilib]
#Include = /etc/pacman.d/mirrorlist
EOF

tests_run=0
tests_failed=0

run_module() {
    local module="$1"
    local log="$tmp_dir/module-$module.log"
    tests_run=$((tests_run + 1))
    rm -f -- "$marker"

    if ! DRY_RUN=1 bash "$ROOT_DIR/modules/$module" >"$log" 2>&1; then
        printf 'not ok - module %s dry-run failed\n' "$module"
        sed 's/^/    /' "$log"
        tests_failed=$((tests_failed + 1))
        return 1
    fi
    if [[ -e "$marker" ]]; then
        printf 'not ok - module %s dry-run tried to change the system\n' "$module"
        sed 's/^/    /' "$marker"
        tests_failed=$((tests_failed + 1))
        return 1
    fi
    printf 'ok - module %s dry-run made no system changes\n' "$module"
}

for module in "$ROOT_DIR"/modules/*.sh; do
    run_module "$(basename -- "$module")" || true
done

printf '\n%d dry-run module tests, %d failures\n' "$tests_run" "$tests_failed"
((tests_failed == 0))
