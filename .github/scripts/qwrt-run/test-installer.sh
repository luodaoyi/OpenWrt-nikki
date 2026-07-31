#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
installer="$script_dir/installer.sh"
temp_dir=$(mktemp -d)
trap 'rm -rf "$temp_dir"' EXIT

mock_dir="$temp_dir/bin"
log_file="$temp_dir/opkg.log"
mkdir -p "$mock_dir"

cat > "$mock_dir/opkg" <<'EOF'
#!/bin/sh
echo "$*" >> "$OPKG_TEST_LOG"

print_architectures() {
	echo "arch all 1"
	if [ "$OPKG_TEST_MODE" != "missing-router" ]; then
		echo "arch aarch64_cortex-a73_neon-vfpv4 10"
	fi
	if [ "$OPKG_TEST_MODE" = "both" ] || [ "${1:-}" = "with-a53" ]; then
		echo "arch aarch64_cortex-a53 5"
	fi
}

case "${1:-}" in
	print-architecture)
		print_architectures
		;;
	--help)
		echo "  --add-arch <arch>:<prio>  Register architecture with given priority"
		;;
	--add-arch)
		[ "${2:-}" = "aarch64_cortex-a53:5" ] || exit 40
		[ "${3:-}" = "print-architecture" ] || exit 41
		print_architectures with-a53
		;;
	*)
		exit 42
		;;
esac
EOF
chmod +x "$mock_dir/opkg"

run_check() {
	local mode=$1
	: > "$log_file"
	env PATH="$mock_dir:$PATH" OPKG_TEST_LOG="$log_file" OPKG_TEST_MODE="$mode" \
		sh "$installer" --check-architecture
}

run_check both
if grep -Fq -- '--add-arch' "$log_file"; then
	echo "registered package architecture should not invoke --add-arch" >&2
	exit 1
fi

run_check a73-only
grep -Fxq -- '--add-arch aarch64_cortex-a53:5 print-architecture' "$log_file"

if run_check missing-router >"$temp_dir/missing-router.out" 2>&1; then
	echo "missing router architecture unexpectedly passed" >&2
	exit 1
fi
grep -Fq 'unsupported router architecture; expected aarch64_cortex-a73_neon-vfpv4' \
	"$temp_dir/missing-router.out"

echo "Installer architecture tests passed."
