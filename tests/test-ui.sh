#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/lib/common.sh"
source "$ROOT_DIR/lib/modules.sh"
source "$ROOT_DIR/lib/ui.sh"

tests_run=0
tests_failed=0

assert() {
    local description="$1"
    shift
    tests_run=$((tests_run + 1))
    if "$@"; then
        printf 'ok - %s\n' "$description"
    else
        printf 'not ok - %s\n' "$description"
        tests_failed=$((tests_failed + 1))
    fi
}

assert_failure() {
    local description="$1"
    shift
    tests_run=$((tests_run + 1))
    if "$@" >/dev/null 2>&1; then
        printf 'not ok - %s\n' "$description"
        tests_failed=$((tests_failed + 1))
    else
        printf 'ok - %s\n' "$description"
    fi
}

compact_menu_on_narrow_terminal() {
    COLUMNS=50 ui_use_compact_menu
}
assert "compact menu is used on narrow terminals" compact_menu_on_narrow_terminal

full_menu_on_wide_terminal() {
    ! COLUMNS=100 ui_use_compact_menu
}
assert "full menu is used on wide terminals" full_menu_on_wide_terminal

unicode_on_utf8_terminal() {
    TERM=xterm LANG=C.UTF-8 ui_use_unicode
}
assert "Unicode is used on a UTF-8 terminal" unicode_on_utf8_terminal

ascii_on_c_locale() {
    ! TERM=xterm LANG=C ui_use_unicode
}
assert "ASCII is used without a UTF-8 locale" ascii_on_c_locale

ascii_on_dumb_terminal() {
    ! TERM=dumb LANG=C.UTF-8 ui_use_unicode
}
assert "ASCII is used on a dumb terminal" ascii_on_dumb_terminal

progress_output_works() {
    local output
    output="$(TERM=xterm LANG=C.UTF-8 ui_step "Installing example")"
    [[ "$output" == *"Installing example"* ]]
}
assert "progress step output includes its message" progress_output_works

done_output_works() {
    local output
    output="$(TERM=xterm LANG=C.UTF-8 ui_done "Finished example")"
    [[ "$output" == *"Finished example"* ]]
}
assert "progress completion output includes its message" done_output_works

printf '\n%d UI tests, %d failures\n' "$tests_run" "$tests_failed"
((tests_failed == 0))
