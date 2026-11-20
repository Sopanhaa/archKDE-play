#!/usr/bin/env bash
set -Eeuo pipefail

# Optional integration test for the interactive menu and dry-run flow.
# It runs inside a bubblewrap namespace with mocked system tools, so the host
# is never modified. Skips cleanly when bwrap or script is unavailable.

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v bwrap >/dev/null 2>&1 || ! command -v script >/dev/null 2>&1; then
    printf 'skip - bwrap or script is unavailable\n'
    exit 0
fi
if ! bwrap --dev-bind / / true >/dev/null 2>&1; then
    printf 'skip - bwrap cannot create a user namespace here\n'
    exit 0
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf -- "$tmp_dir"' EXIT

mkdir -p -- "$tmp_dir/etc" "$tmp_dir/bin"
cp /etc/passwd /etc/group /etc/nsswitch.conf "$tmp_dir/etc/"
if [[ -d /etc/alternatives ]]; then
    cp -a /etc/alternatives "$tmp_dir/etc/"
fi
if [[ -e /etc/localtime ]]; then
    cp -a /etc/localtime "$tmp_dir/etc/"
fi
printf 'Arch Linux\n' >"$tmp_dir/etc/arch-release"
cat >"$tmp_dir/etc/pacman.conf" <<'EOF'
[options]
HoldPkg = pacman glibc

#[multilib]
#Include = /etc/pacman.d/mirrorlist
EOF

cat >"$tmp_dir/bin/pacman" <<'EOF'
#!/usr/bin/env bash
case " $* " in
    *" -Q "*) exit 1 ;;
    *" -Si "*) exit 0 ;;
    *" -S "* | *" -Syu "* | *" -Sy "*) printf 'pacman %s\n' "$*" >>"$SETUP_TEST_MARKER" ;;
esac
exit 0
EOF
cat >"$tmp_dir/bin/sudo" <<'EOF'
#!/usr/bin/env bash
[[ "$1" == "-n" || "$1" == "-v" ]] && exit 0
printf 'sudo %s\n' "$*" >>"$SETUP_TEST_MARKER"
exit 0
EOF
cat >"$tmp_dir/bin/curl" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat >"$tmp_dir/bin/lspci" <<'EOF'
#!/usr/bin/env bash
printf '01:00.0 VGA compatible controller: NVIDIA Corporation (10de:2504)\n'
EOF
cat >"$tmp_dir/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
case "$1" in
    is-enabled | is-active) exit 1 ;;
    enable | start) printf 'systemctl %s\n' "$*" >>"$SETUP_TEST_MARKER" ;;
esac
exit 0
EOF
cat >"$tmp_dir/bin/flatpak" <<'EOF'
#!/usr/bin/env bash
case "$1" in
    install | remote-add) printf 'flatpak %s\n' "$*" >>"$SETUP_TEST_MARKER" ;;
    remotes) exit 0 ;;
    info | remote-info) exit 1 ;;
esac
exit 0
EOF
cat >"$tmp_dir/bin/findmnt" <<'EOF'
#!/usr/bin/env bash
printf '/dev/sda1\n'
EOF
cat >"$tmp_dir/bin/lsblk" <<'EOF'
#!/usr/bin/env bash
printf '0\n'
EOF
cat >"$tmp_dir/bin/bootctl" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat >"$tmp_dir/bin/mokutil" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$tmp_dir/bin"/*

marker="$tmp_dir/system-changes"

cat >"$tmp_dir/run.sh" <<EOF
#!/usr/bin/env bash
exec bwrap --dev-bind / / \
    --bind '$tmp_dir/etc' /etc \
    --bind '$tmp_dir/bin' /usr/local/bin \
    --setenv PATH '/usr/local/bin:/usr/bin:/bin' \
    --setenv SETUP_TEST_MARKER '$marker' \
    --chdir '$ROOT_DIR' \
    bash '$ROOT_DIR/install.sh' "\$@"
EOF

run_with_input() {
    local input="$1"
    shift
    printf '%s\n' "$input" |
        SHELL=/bin/bash script -qec "bash '$tmp_dir/run.sh' $*" /dev/null \
            >"$tmp_dir/output.txt" 2>&1
    tr -d '\r' <"$tmp_dir/output.txt" >"$tmp_dir/output.clean"
    mv -- "$tmp_dir/output.clean" "$tmp_dir/output.txt"
}

tests_run=0
tests_failed=0

assert_output() {
    local description="$1"
    local status="$2"
    local expected="$3"
    tests_run=$((tests_run + 1))
    if ((status == 0)) && grep -Fq -- "$expected" "$tmp_dir/output.txt"; then
        printf 'ok - %s\n' "$description"
    else
        printf 'not ok - %s\n' "$description"
        sed 's/^/    /' "$tmp_dir/output.txt"
        tests_failed=$((tests_failed + 1))
    fi
}

run_with_input 1 --dry-run --no-color
status=$?
assert_output "interactive menu shows the recommended setup option" "$status" "[1] Recommended Gaming Setup"
assert_output "recommended dry-run completes" "$status" "Setup complete"
assert_output "dry-run reports that nothing changed" "$status" "Mode: dry run"

run_with_input $'2\n03' --dry-run --no-color
status=$?
assert_output "custom installation accepts module numbers" "$status" "03  GPU drivers and Vulkan"
assert_output "custom dry-run completes" "$status" "Setup complete"

run_with_input 4 --dry-run --no-color
status=$?
assert_output "gaming applications option selects gaming tools" "$status" "05  Gaming tools"
assert_output "gaming applications dry-run completes" "$status" "Setup complete"

run_with_input 6 --no-color
status=$?
assert_output "menu option 6 checks compatibility" "$status" "Check complete"

run_with_input 0 --no-color
status=$?
assert_output "menu option 0 exits without changes" "$status" "Installation cancelled"

if [[ -e "$marker" ]]; then
    printf 'not ok - interactive flow tried to change the system\n'
    sed 's/^/    /' "$marker"
    tests_failed=$((tests_failed + 1))
else
    printf 'ok - interactive flow made no system changes\n'
fi
tests_run=$((tests_run + 1))

printf '\n%d interactive tests, %d failures\n' "$tests_run" "$tests_failed"
((tests_failed == 0))
