#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 DIST_DIR RUN_FILENAME" >&2
  exit 2
fi

dist_dir=$1
run_filename=$2
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
installer="$script_dir/installer.sh"

[[ -d "$dist_dir" ]] || { echo "Missing dist directory: $dist_dir" >&2; exit 1; }
[[ -f "$installer" ]] || { echo "Missing installer stub: $installer" >&2; exit 1; }
[[ "$run_filename" != */* && "$run_filename" == *.run ]] \
  || { echo "RUN_FILENAME must be a .run basename" >&2; exit 1; }
[[ $(tail -n 1 "$installer") == '__NIKKI_PAYLOAD_BELOW__' ]] \
  || { echo "Installer payload marker is missing" >&2; exit 1; }

(
  cd "$dist_dir"
  sha256sum -c SHA256SUMS
)

shopt -s nullglob
expect_one() {
  local pattern=$1
  local matches=("$dist_dir"/$pattern)
  [[ ${#matches[@]} -eq 1 && -f ${matches[0]} ]] \
    || { echo "Expected exactly one file matching $pattern" >&2; exit 1; }
  printf '%s\n' "${matches[0]}"
}

mihomo_ipk=$(expect_one 'mihomo-meta_*.ipk')
nikki_ipk=$(expect_one 'nikki_*.ipk')
luci_ipk=$(expect_one 'luci-app-nikki_*.ipk')
language_ipk=$(expect_one 'luci-i18n-nikki-zh-cn_*.ipk')

payload_dir=$(mktemp -d)
archive=$(mktemp)
cleanup() {
  rm -rf -- "$payload_dir"
  rm -f -- "$archive"
}
trap cleanup EXIT

cp "$mihomo_ipk" \
  "$nikki_ipk" \
  "$luci_ipk" \
  "$language_ipk" \
  "$dist_dir/BUILD_INFO.txt" \
  "$dist_dir/SHA256SUMS" \
  "$payload_dir/"

tar -C "$payload_dir" -czf "$archive" .
output="$dist_dir/$run_filename"
rm -f -- "$output" "$output.sha256"
cat "$installer" "$archive" > "$output"
chmod 0755 "$output"
(
  cd "$dist_dir"
  sha256sum "$run_filename" > "$run_filename.sha256"
)

echo "Created $output"
