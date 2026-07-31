#!/bin/sh
set -eu

SELF="$0"
MARKER="__NIKKI_PAYLOAD_BELOW__"
PACKAGE_ARCH="aarch64_cortex-a53"
PACKAGE_ARCH_PRIORITY=5
ROUTER_ARCH="aarch64_cortex-a73_neon-vfpv4"
OPKG_NEEDS_PACKAGE_ARCH=0
TMP_DIR=""
SERVICE_SNAPSHOT_ACTIVE=0
NIKKI_WAS_INSTALLED=0
NIKKI_WAS_RUNNING=0
NIKKI_CONFIG_ENABLED=0
NIKKI_RC_ENABLED=0
OPENCLASH_WAS_RUNNING=0

die() {
	echo "ERROR: $*" >&2
	exit 1
}

package_installed() {
	opkg status "$1" 2>/dev/null | grep -q '^Status: .* installed'
}

opkg_architecture_registered() {
	opkg print-architecture | awk '{print $2}' | grep -Fx "$1" >/dev/null 2>&1
}

configure_opkg_architecture() {
	command -v opkg >/dev/null 2>&1 || die "opkg was not found"
	opkg_architecture_registered "$ROUTER_ARCH" \
		|| die "unsupported router architecture; expected $ROUTER_ARCH"

	if opkg_architecture_registered "$PACKAGE_ARCH"; then
		OPKG_NEEDS_PACKAGE_ARCH=0
		return
	fi

	opkg --help 2>&1 | grep -Fq -- '--add-arch' \
		|| die "opkg cannot temporarily register the bundled package architecture: $PACKAGE_ARCH"
	opkg --add-arch "$PACKAGE_ARCH:$PACKAGE_ARCH_PRIORITY" print-architecture \
		| awk '{print $2}' | grep -Fx "$PACKAGE_ARCH" >/dev/null 2>&1 \
		|| die "opkg failed to register the bundled package architecture: $PACKAGE_ARCH"
	OPKG_NEEDS_PACKAGE_ARCH=1
	echo "Using temporary opkg architecture: $PACKAGE_ARCH"
}

opkg_install() {
	if [ "$OPKG_NEEDS_PACKAGE_ARCH" -eq 1 ]; then
		opkg --add-arch "$PACKAGE_ARCH:$PACKAGE_ARCH_PRIORITY" install "$@"
	else
		opkg install "$@"
	fi
}

restore_service_state() {
	if [ ! -x /etc/init.d/nikki ] || [ ! -f /etc/config/nikki ]; then
		return
	fi

	if [ "$OPENCLASH_WAS_RUNNING" -eq 1 ]; then
		uci set nikki.config.enabled='0'
		uci commit nikki
		/etc/init.d/nikki stop >/dev/null 2>&1 || true
		/etc/init.d/nikki disable >/dev/null 2>&1 || true
		if [ -x /etc/init.d/openclash ] && ! /etc/init.d/openclash status >/dev/null 2>&1; then
			/etc/init.d/openclash start >/dev/null 2>&1 || true
		fi
		return
	fi

	if [ "$NIKKI_WAS_INSTALLED" -eq 0 ]; then
		uci set nikki.config.enabled='0'
		uci commit nikki
		/etc/init.d/nikki stop >/dev/null 2>&1 || true
		/etc/init.d/nikki disable >/dev/null 2>&1 || true
		return
	fi

	uci set nikki.config.enabled="$NIKKI_CONFIG_ENABLED"
	uci commit nikki
	if [ "$NIKKI_RC_ENABLED" -eq 1 ]; then
		/etc/init.d/nikki enable >/dev/null 2>&1 || true
	else
		/etc/init.d/nikki disable >/dev/null 2>&1 || true
	fi
	if [ "$NIKKI_WAS_RUNNING" -eq 1 ]; then
		/etc/init.d/nikki restart >/dev/null 2>&1 || /etc/init.d/nikki start >/dev/null 2>&1 || true
	else
		/etc/init.d/nikki stop >/dev/null 2>&1 || true
	fi
}

cleanup() {
	status=$?
	trap - EXIT HUP INT TERM
	if [ "$SERVICE_SNAPSHOT_ACTIVE" -eq 1 ]; then
		restore_service_state || true
	fi
	if [ -n "$TMP_DIR" ] && [ -d "$TMP_DIR" ]; then
		rm -rf "$TMP_DIR"
	fi
	exit "$status"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

payload_line() {
	awk -v marker="$MARKER" '$0 == marker { print NR + 1; exit }' "$SELF"
}

extract_payload() {
	destination="$1"
	line="$(payload_line)"
	[ -n "$line" ] || die "embedded payload marker not found"
	mkdir -p "$destination"
	tail -n "+$line" "$SELF" | tar -xzf - -C "$destination"
}

prepare_payload() {
	TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nikki-qwrt-a73.XXXXXX")" \
		|| die "failed to create temporary directory"
	extract_payload "$TMP_DIR"
	(
		cd "$TMP_DIR"
		sha256sum -c SHA256SUMS
	) || die "payload checksum verification failed"
}

single_package() {
	pattern="$1"
	set -- "$TMP_DIR"/$pattern
	[ "$#" -eq 1 ] && [ -f "$1" ] || die "expected exactly one package matching $pattern"
	printf '%s\n' "$1"
}

show_info() {
	prepare_payload
	cat "$TMP_DIR/BUILD_INFO.txt"
	echo "packages:"
	find "$TMP_DIR" -maxdepth 1 -type f -name '*.ipk' -exec basename {} \; | sort
}

verify_only() {
	prepare_payload
	echo "Payload verification passed."
}

extract_only() {
	destination="${1:-}"
	[ -n "$destination" ] || die "--extract requires a destination directory"
	[ ! -e "$destination" ] || die "destination already exists: $destination"
	extract_payload "$destination"
	(
		cd "$destination"
		sha256sum -c SHA256SUMS
	) || die "extracted payload checksum verification failed"
	echo "Extracted to: $destination"
}

install_packages() {
	[ "$(id -u)" = "0" ] || die "installation must run as root"
	command -v fw4 >/dev/null 2>&1 || die "firewall4/fw4 was not found"
	configure_opkg_architecture

	for dependency in firewall4 kmod-inet-diag kmod-nft-socket kmod-nft-tproxy kmod-tun; do
		package_installed "$dependency" || die "required firmware package is missing: $dependency"
	done

	missing=""
	for dependency in ca-bundle curl ip-full yq; do
		if ! package_installed "$dependency"; then
			missing="$missing $dependency"
		fi
	done
	if [ -n "$missing" ]; then
		echo "Installing missing user-space dependencies:$missing"
		opkg update
		opkg install $missing
	fi

	prepare_payload
	mihomo_ipk="$(single_package 'mihomo-meta_*.ipk')"
	nikki_ipk="$(single_package 'nikki_*.ipk')"
	luci_ipk="$(single_package 'luci-app-nikki_*.ipk')"
	language_ipk="$(single_package 'luci-i18n-nikki-zh-cn_*.ipk')"

	if package_installed nikki; then
		NIKKI_WAS_INSTALLED=1
		NIKKI_CONFIG_ENABLED="$(uci -q get nikki.config.enabled || echo 0)"
		if /etc/init.d/nikki running >/dev/null 2>&1; then
			NIKKI_WAS_RUNNING=1
		fi
		if /etc/init.d/nikki enabled >/dev/null 2>&1; then
			NIKKI_RC_ENABLED=1
		fi
	fi
	if [ -x /etc/init.d/openclash ] && /etc/init.d/openclash status >/dev/null 2>&1; then
		OPENCLASH_WAS_RUNNING=1
	fi

	timestamp="$(date +%Y%m%d-%H%M%S)"
	backup_dir="/root/nikki-run-backup-$timestamp-$$"
	umask 077
	mkdir -p "$backup_dir"
	opkg list-installed > "$backup_dir/packages.before.txt"
	uci export firewall > "$backup_dir/firewall.uci" 2>/dev/null || true
	uci export openclash > "$backup_dir/openclash.uci" 2>/dev/null || true
	uci export nikki > "$backup_dir/nikki.uci" 2>/dev/null || true
	nft list ruleset > "$backup_dir/nft.before.txt" 2>/dev/null || true

	SERVICE_SNAPSHOT_ACTIVE=1
	if [ "$NIKKI_WAS_INSTALLED" -eq 1 ]; then
		uci set nikki.config.enabled='0'
		uci commit nikki
		/etc/init.d/nikki stop >/dev/null 2>&1 || true
	fi

	opkg_install "$mihomo_ipk"
	opkg_install "$nikki_ipk"
	opkg_install "$luci_ipk"
	opkg_install "$language_ipk"
	rm -f /tmp/luci-indexcache
	rm -rf /tmp/luci-modulecache/* 2>/dev/null || true

	restore_service_state
	SERVICE_SNAPSHOT_ACTIVE=0

	echo "Installation completed."
	if [ "$OPENCLASH_WAS_RUNNING" -eq 1 ]; then
		echo "OpenClash remains running; Nikki remains stopped and disabled."
	elif [ "$NIKKI_WAS_RUNNING" -eq 1 ]; then
		echo "Nikki was restarted because it was running before the upgrade."
	else
		echo "Nikki remains stopped until it is configured and enabled."
	fi
	echo "Backup: $backup_dir"
	echo "LuCI: /cgi-bin/luci/admin/services/nikki"
}

usage() {
	cat <<'EOF'
Usage:
  sh OpenWrt-nikki-QWRT-A73.run --verify
  sh OpenWrt-nikki-QWRT-A73.run --info
  sh OpenWrt-nikki-QWRT-A73.run --extract DIR
  sh OpenWrt-nikki-QWRT-A73.run --check-architecture
  sh OpenWrt-nikki-QWRT-A73.run --install

With no argument, the installer runs --install.
The installer verifies its embedded files, backs up router state, installs the
four bundled packages, and preserves the active OpenClash/Nikki service choice.
EOF
}

case "${1:---install}" in
	--install) install_packages ;;
	--verify) verify_only ;;
	--info) show_info ;;
	--extract) shift; extract_only "${1:-}" ;;
	--check-architecture) configure_opkg_architecture; echo "Architecture check passed." ;;
	--help|-h) usage ;;
	*) usage; exit 2 ;;
esac

exit 0
__NIKKI_PAYLOAD_BELOW__
