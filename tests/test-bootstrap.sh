#!/usr/bin/env bash
set -Eeuo pipefail

# Test the single-file remote entry point without network access.
# A local tarball and a local SHA256SUMS stand in for GitHub downloads.

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf -- "$tmp_dir"' EXIT

if ! command -v sha256sum >/dev/null 2>&1; then
    printf 'skip - sha256sum is unavailable\n'
    exit 0
fi
if [[ ! -f "$ROOT_DIR/SHA256SUMS" ]]; then
    printf 'not ok - SHA256SUMS is missing; run: bash scripts/checksums.sh\n'
    exit 1
fi

entry_dir="$tmp_dir/entry"
archive="$tmp_dir/archkde-play.tar.gz"
mkdir -p -- "$entry_dir"
cp -- "$ROOT_DIR/install.sh" "$entry_dir/install.sh"

repo_parent="$(dirname -- "$ROOT_DIR")"
repo_name="$(basename -- "$ROOT_DIR")"
tar --exclude='.git' --exclude='.idea' \
    -czf "$archive" -C "$repo_parent" "$repo_name"

tests_run=0
tests_failed=0

run_entry() {
    local checksum_url="$1"
    shift
    ARCHKDE_ARCHIVE_URL="file://$archive" \
        ARCHKDE_CHECKSUM_URL="file://$checksum_url" \
        ARCHKDE_ALLOW_INSECURE_SOURCE=1 \
        bash "$entry_dir/install.sh" "$@"
}

assert_ok() {
    local description="$1"
    shift
    tests_run=$((tests_run + 1))
    if "$@" >/dev/null 2>&1; then
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

bootstrap_help_works() {
    local output
    output="$(run_entry "$ROOT_DIR/SHA256SUMS" --help 2>&1)"
    [[ "$output" == *"One-command install:"* &&
        "$output" == *"Menu options:"* ]]
}
assert_ok "downloaded entry point verifies files and shows help" bootstrap_help_works

bootstrap_version_works() {
    local output
    output="$(run_entry "$ROOT_DIR/SHA256SUMS" --version 2>&1)"
    [[ "$(printf '%s\n' "$output" | tail -n1)" == "archKDE-play main" ]]
}
assert_ok "downloaded entry point reports the selected ref" bootstrap_version_works

bootstrap_cleans_temp_files() {
    run_entry "$ROOT_DIR/SHA256SUMS" --help >/dev/null 2>&1
    [[ "$(find "$entry_dir" -type f | wc -l)" == "1" ]]
}
assert_ok "downloaded entry point leaves no extracted files behind" bootstrap_cleans_temp_files

bootstrap_help_does_not_save_source() {
    local data_dir="$tmp_dir/help-data"
    XDG_DATA_HOME="$data_dir" run_entry "$ROOT_DIR/SHA256SUMS" --help >/dev/null 2>&1
    [[ ! -e "$data_dir/archkde-play/source" ]]
}
assert_ok "check/help runs do not save a persistent source copy" bootstrap_help_does_not_save_source

bootstrap_saves_verified_source() {
    local data_dir="$tmp_dir/saved-data"
    local state_dir="$tmp_dir/saved-state"
    local output
    output="$(XDG_DATA_HOME="$data_dir" XDG_STATE_HOME="$state_dir" \
        run_entry "$ROOT_DIR/SHA256SUMS" --modules 99 2>&1)" || true
    [[ "$output" == *"Installer source saved to:"* &&
        -f "$data_dir/archkde-play/source/install.sh" &&
        -f "$data_dir/archkde-play/source/lib/common.sh" &&
        -f "$data_dir/archkde-play/source/SHA256SUMS" ]]
}
assert_ok "install runs save a verified source copy for reruns" bootstrap_saves_verified_source

bootstrap_rejects_bad_checksum() {
    local bad_manifest="$tmp_dir/bad-SHA256SUMS"
    local output
    awk '$2 == "install.sh" { $1 = "0000000000000000000000000000000000000000000000000000000000000000" }
        { printf "%s  %s\n", $1, $2 }' "$ROOT_DIR/SHA256SUMS" >"$bad_manifest"
    if output="$(run_entry "$bad_manifest" --help 2>&1)"; then
        return 1
    fi
    [[ "$output" == *"Checksum verification failed"* ]]
}
assert_ok "downloaded entry point rejects a bad checksum" bootstrap_rejects_bad_checksum

bootstrap_rejects_malformed_manifest() {
    local bad_manifest="$tmp_dir/malformed-SHA256SUMS"
    local output
    awk '$2 == "install.sh" { $1 = "0000000000000000000000000000000000000000000000000000000000000000" }
        { print }' "$ROOT_DIR/SHA256SUMS" >"$bad_manifest"
    if output="$(run_entry "$bad_manifest" --help 2>&1)"; then
        return 1
    fi
    [[ "$output" == *"Checksum verification failed"* ]]
}
assert_ok "downloaded entry point rejects a malformed manifest" bootstrap_rejects_malformed_manifest

bootstrap_rejects_incomplete_manifest() {
    local bad_manifest="$tmp_dir/incomplete-SHA256SUMS"
    local output
    grep -v '  lib/common\.sh$' "$ROOT_DIR/SHA256SUMS" >"$bad_manifest"
    if output="$(run_entry "$bad_manifest" --help 2>&1)"; then
        return 1
    fi
    [[ "$output" == *"does not cover a required file"* ]]
}
assert_ok "downloaded entry point rejects a manifest missing required files" bootstrap_rejects_incomplete_manifest

bootstrap_rejects_modified_entry_script() {
    local tampered="$tmp_dir/tampered-entry.sh"
    local output
    cp -- "$ROOT_DIR/install.sh" "$tampered"
    printf '\n# tampered copy\n' >>"$tampered"
    if output="$(ARCHKDE_ARCHIVE_URL="file://$archive" \
        ARCHKDE_CHECKSUM_URL="file://$ROOT_DIR/SHA256SUMS" \
        ARCHKDE_ALLOW_INSECURE_SOURCE=1 \
        bash "$tampered" --help 2>&1)"; then
        return 1
    fi
    [[ "$output" == *"entry script does not match"* ]]
}
assert_ok "downloaded entry point rejects a modified entry script" bootstrap_rejects_modified_entry_script

bootstrap_accepts_pinned_archive_hash() {
    local archive_sha
    archive_sha="$(sha256sum -- "$archive" | awk '{print $1}')"
    ARCHKDE_SHA256="$archive_sha" \
        run_entry "$ROOT_DIR/SHA256SUMS" --help >/dev/null 2>&1
}
assert_ok "downloaded entry point accepts ARCHKDE_SHA256" bootstrap_accepts_pinned_archive_hash

bootstrap_rejects_wrong_archive_hash() {
    ARCHKDE_SHA256="0000000000000000000000000000000000000000000000000000000000000000" \
        run_entry "$ROOT_DIR/SHA256SUMS" --help >/dev/null 2>&1
}
assert_failure "downloaded entry point rejects a wrong ARCHKDE_SHA256" bootstrap_rejects_wrong_archive_hash

printf '\n%d bootstrap tests, %d failures\n' "$tests_run" "$tests_failed"
((tests_failed == 0))
