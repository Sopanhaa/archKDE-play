#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="$ROOT_DIR/SHA256SUMS"

usage() {
    cat <<'EOF'
Usage: bash scripts/checksums.sh [--check]

Without options, regenerate SHA256SUMS for the runtime shell files.
With --check, fail if SHA256SUMS is missing or out of date.
EOF
}

check=0
case "${1:-}" in
    "") ;;
    --check) check=1 ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'Unknown option: %s (use --help).\n' "$1" >&2; exit 1 ;;
esac

if ! command -v sha256sum >/dev/null 2>&1; then
    printf 'sha256sum is required (install coreutils).\n' >&2
    exit 1
fi

cd "$ROOT_DIR"
mapfile -t files < <(
    find . -type f \( -name '*.sh' -o -path './config/*' \) \
        -not -path './.git/*' -not -path './.idea/*' -not -path './tests/*' -print |
        sed 's|^\./||' |
        LC_ALL=C sort
)
((${#files[@]})) || {
    printf 'No shell files were found.\n' >&2
    exit 1
}

tmp="$(mktemp)"
trap 'rm -f -- "$tmp"' EXIT
sha256sum "${files[@]}" >"$tmp"

if ((check)); then
    if [[ ! -f "$TARGET" ]]; then
        printf 'SHA256SUMS is missing; run: bash scripts/checksums.sh\n' >&2
        exit 1
    fi
    if ! diff -u "$TARGET" "$tmp"; then
        printf '\nSHA256SUMS is out of date; run: bash scripts/checksums.sh\n' >&2
        exit 1
    fi
    printf 'SHA256SUMS is up to date (%d files).\n' "${#files[@]}"
    exit 0
fi

mv -- "$tmp" "$TARGET"
printf 'Updated SHA256SUMS with %d files.\n' "${#files[@]}"
