#!/bin/sh

set -u

BASE_URL="${ZLAN_RELEASE_URL:-https://raw.githubusercontent.com/Wagnee/Tailscale-ZLAN9809M-Minimal/main/release}"
ARCHIVE_URL="$BASE_URL/zlan-ts-minimal.tar.gz"
ARCHIVE_SHA256='cbadfc8d622d9ac41d8ee01592e17307c8bc6eae607347de0ebfd92c1cfca57b'
WORK="/tmp/zlan-ts-install.$$"
ARCHIVE="$WORK/payload.tar.gz"
PAYLOAD="$WORK/payload"
NEW_CONFIG=0

cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT INT TERM
fail() { echo "ERRO: $*" >&2; exit 1; }

release_value() {
    sed -n "s/^$1=['\"]\([^'\"]*\)['\"].*/\1/p" /etc/openwrt_release 2>/dev/null | sed -n '1p'
}

check_hardware() {
    [ "$(id -u 2>/dev/null)" = "0" ] || fail "execute como root"
    [ "$(release_value DISTRIB_RELEASE)" = "21.02.0" ] || fail "requer OpenWrt 21.02.0"
    [ "$(release_value DISTRIB_TARGET)" = "ramips/mt76x8" ] || fail "requer target ramips/mt76x8"
    grep -qi -e 'MT7628' -e 'MIPS 24KEc' /proc/cpuinfo || fail "CPU MT7628/MIPS 24KEc nao detectada"
    [ -c /dev/net/tun ] || fail "/dev/net/tun nao existe"
    for command in wget sha256sum tar uci; do
        command -v "$command" >/dev/null 2>&1 || fail "$command nao encontrado"
    done
    memory="$(sed -n 's/^MemTotal:[[:space:]]*\([0-9][0-9]*\).*/\1/p' /proc/meminfo)"
    if [ -z "$memory" ] || [ "$memory" -lt 110000 ]; then
        fail "RAM insuficiente: ${memory:-0} KB"
    fi
    free_overlay="$(df -k /overlay 2>/dev/null | awk 'NR>1 {v=$4} END {print v}')"
    if [ -z "$free_overlay" ] || [ "$free_overlay" -lt 256 ]; then
        fail "overlay com menos de 256 KB livres"
    fi
}

verify_payload() {
    expected="$(printf '%s' "$ARCHIVE_SHA256" | tr 'A-F' 'a-f')"
    actual="$(sha256sum "$ARCHIVE" | sed 's/[[:space:]].*//' | tr 'A-F' 'a-f')"
    [ "${#expected}" = "64" ] || fail "manifesto SHA-256 invalido"
    [ "$actual" = "$expected" ] || fail "SHA-256 do payload nao confere"
}

stop_service() {
    name="$1"
    if [ -x "/etc/init.d/$name" ]; then
        "/etc/init.d/$name" stop >/dev/null 2>&1 || true
        "/etc/init.d/$name" disable >/dev/null 2>&1 || true
    fi
}

stop_legacy() {
    for service in zlan-ts-minimal zlan-tailscale zlan-telemetry tailscale-loader tailscale mqtt-daemon modbus-daemon cpufreq-manager auto-update; do
        stop_service "$service"
    done
    killall tailscaled 2>/dev/null || true
    killall tailscale.combined 2>/dev/null || true
    killall zlan-telemetryd 2>/dev/null || true
}

remove_legacy_overlay() {
    # Remove somente arquivos gravados pelos projetos anteriores no overlay.
    # Nao remove pacotes do squashfs e preserva /etc/tailscale/tailscaled.state.
    remove_overlay_file \
        /etc/init.d/zlan-tailscale /etc/init.d/zlan-telemetry \
        /etc/init.d/tailscale-loader /etc/init.d/tailscale \
        /etc/init.d/mqtt-daemon /etc/init.d/modbus-daemon \
        /etc/init.d/auto-update /etc/init.d/cpufreq-manager \
        /usr/bin/zlan-tailscale-loader /usr/bin/zlan-telemetryd \
        /usr/bin/zlan-hybrid-status /usr/bin/zlan-hybrid-cleanup \
        /usr/bin/zlan-hybrid-update /usr/bin/zlan-hybrid-uninstall \
        /usr/bin/zlan-system /usr/bin/tailscale-loader.sh \
        /usr/bin/tailscale-loader /usr/sbin/tailscale \
        /usr/sbin/tailscaled /usr/sbin/tailscaled.xz \
        /usr/bin/mqtt-daemon /usr/bin/modbus-daemon \
        /etc/auto-update-whitelist.conf /var/log/auto-update-daemon.log \
        /etc/config/zlan_modbus /etc/config/zlan_mqtt \
        /usr/lib/lua/luci/controller/zlan_hybrid.lua \
        /usr/lib/lua/luci/model/cbi/zlan_tailscale.lua \
        /usr/lib/lua/luci/model/cbi/zlan_modbus.lua \
        /usr/lib/lua/luci/model/cbi/zlan_mqtt.lua \
        /usr/lib/lua/luci/controller/tailscale_zlan.lua \
        /usr/lib/lua/luci/controller/admin/tailscale.lua \
        /usr/lib/lua/luci/controller/admin/tailscale_status.lua \
        /usr/lib/lua/luci/controller/admin/modbus.lua \
        /usr/lib/lua/luci/controller/admin/mqtt.lua \
        /usr/lib/lua/luci/controller/cpufreq.lua \
        /usr/lib/lua/luci/model/cbi/tailscale.lua \
        /usr/lib/lua/luci/model/cbi/modbus.lua \
        /usr/lib/lua/luci/model/cbi/mqtt.lua \
        /usr/lib/lua/luci/model/cbi/cpufreq.lua
    remove_overlay_tree \
        /usr/share/zlan-hybrid /usr/lib/auto-update \
        /var/lib/auto-update-executed \
        /usr/lib/lua/luci/view/zlan_hybrid \
        /usr/lib/lua/luci/view/tailscale_zlan \
        /usr/lib/lua/luci/view/tailscale \
        /usr/lib/lua/luci/view/modbus \
        /usr/lib/lua/luci/view/mqtt \
        /usr/lib/lua/luci/view/cpufreq
    rm -f /tmp/tailscale /tmp/tailscaled /tmp/tailscale.combined /tmp/tailscale.combined.part
    rm -rf /tmp/tailscale-runtime /tmp/zlan-telemetry
}

remove_overlay_file() {
    for target in "$@"; do
        upper="/overlay/upper$target"
        if [ -e "$upper" ] || [ -L "$upper" ]; then rm -f "$target"; fi
    done
}

remove_overlay_tree() {
    for target in "$@"; do
        upper="/overlay/upper$target"
        if [ -e "$upper" ] || [ -L "$upper" ]; then rm -rf "$target"; fi
    done
}

default_option() {
    sed -n "s/^[[:space:]]*option[[:space:]]*$1[[:space:]]*'\([^']*\)'.*/\1/p" \
        /usr/share/zlan-ts-minimal/defaults/zlan_ts_minimal | sed -n '1p'
}

migrate_old_uci() {
    if [ -f /etc/config/zlan_tailscale ]; then
        for field in hostname routes auth_key port; do
            value="$(uci -q get "zlan_tailscale.main.$field" 2>/dev/null)"
            [ -z "$value" ] || uci set "zlan_ts_minimal.main.$field=$value"
        done
    fi
    if [ -f /etc/config/tailscale ]; then
        value="$(uci -q get tailscale.tailscale.auth_key 2>/dev/null)"
        [ -z "$value" ] || uci set "zlan_ts_minimal.main.auth_key=$value"
        value="$(uci -q get tailscale.tailscale.advertise_routes 2>/dev/null)"
        [ -z "$value" ] || uci set "zlan_ts_minimal.main.routes=$value"
    fi
    if [ ! -f /etc/tailscale/tailscaled.state ] && [ -f /etc/tailscale/tailscale.state ]; then
        if cp /etc/tailscale/tailscale.state /etc/tailscale/tailscaled.state; then
            chmod 0600 /etc/tailscale/tailscaled.state
        fi
    fi
    [ ! -f /etc/tailscale/tailscaled.state ] || remove_overlay_file /etc/tailscale/tailscale.state
}

detect_lan_route() {
    [ -z "$(uci -q get zlan_ts_minimal.main.routes 2>/dev/null)" ] || return 0
    lan_ip="$(uci -q get network.lan.ipaddr 2>/dev/null)"
    lan_mask="$(uci -q get network.lan.netmask 2>/dev/null)"
    if [ "$lan_mask" = "255.255.255.0" ]; then
        case "$lan_ip" in
            *.*.*.*)
                route="${lan_ip%.*}.0/24"
                uci set "zlan_ts_minimal.main.routes=$route"
                echo "Rota LAN detectada: $route"
                ;;
        esac
    fi
}

install_config() {
    mkdir -p /etc/config /etc/tailscale
    chmod 0700 /etc/tailscale
    if [ ! -f /etc/config/zlan_ts_minimal ]; then
        cp /usr/share/zlan-ts-minimal/defaults/zlan_ts_minimal /etc/config/zlan_ts_minimal
        NEW_CONFIG=1
        migrate_old_uci
    fi

    # URLs e hashes acompanham cada release; configuracao operacional e preservada.
    for field in daemon_url daemon_sha256 cli_url cli_sha256; do
        value="$(default_option "$field")"
        uci set "zlan_ts_minimal.main.$field=$value"
    done
    detect_lan_route
    uci commit zlan_ts_minimal
    chmod 0600 /etc/config/zlan_ts_minimal
}

interactive_config() {
    [ "$NEW_CONFIG" = "1" ] && [ -t 0 ] || return 0
    hostname="$(uci -q get zlan_ts_minimal.main.hostname)"
    routes="$(uci -q get zlan_ts_minimal.main.routes)"
    printf 'Hostname Tailscale [%s]: ' "$hostname"
    read -r value
    [ -z "$value" ] || uci set "zlan_ts_minimal.main.hostname=$value"
    printf 'Subnet anunciada [%s]: ' "$routes"
    read -r value
    [ -z "$value" ] || uci set "zlan_ts_minimal.main.routes=$value"
    printf 'Auth key (opcional, entrada oculta): '
    stty -echo 2>/dev/null || true
    read -r value
    stty echo 2>/dev/null || true
    echo
    [ -z "$value" ] || uci set "zlan_ts_minimal.main.auth_key=$value"
    uci commit zlan_ts_minimal
}

echo "=========================================="
echo " Tailscale ZLAN9809M Minimal"
echo "=========================================="
check_hardware
mkdir -p "$WORK" "$PAYLOAD"
wget -4 --no-check-certificate -O "$ARCHIVE" "$ARCHIVE_URL" || fail "download IPv4 do payload falhou"
verify_payload
tar -xzf "$ARCHIVE" -C "$PAYLOAD" || fail "payload corrompido"
[ -f "$PAYLOAD/usr/bin/zlan-ts-minimal" ] || fail "payload incompleto"

stop_legacy
remove_legacy_overlay
cp -R "$PAYLOAD"/. / || fail "falha copiando payload"
chmod 0755 /usr/bin/zlan-ts-minimal /usr/bin/zlan-ts /etc/init.d/zlan-ts-minimal
find /usr/share/zlan-ts-minimal -type d -exec chmod 0755 {} \;
find /usr/share/zlan-ts-minimal -type f -exec chmod 0644 {} \;
install_config
interactive_config
remove_overlay_file /etc/config/zlan_tailscale /etc/config/tailscale
remove_overlay_file /etc/config/modbus /etc/config/mqtt
rm -f /tmp/luci-indexcache

mkdir -p /etc/sysctl.d
printf '%s\n' 'net.ipv4.ip_forward=1' > /etc/sysctl.d/99-zlan-ts-minimal.conf
echo 1 > /proc/sys/net/ipv4/ip_forward 2>/dev/null || true
/etc/init.d/zlan-ts-minimal enable
/etc/init.d/zlan-ts-minimal start

echo "Instalacao concluida."
echo "Status: /etc/init.d/zlan-ts-minimal status"
echo "Log: tail -f /tmp/zlan-ts-minimal.log"
echo "Config: /etc/config/zlan_ts_minimal"
