#!/bin/sh

set -eu

SCRIPT_DIR="$(dirname -- "$0")"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HELPER="$ROOT/rootfs/usr/bin/zlan-ts-mwan3"
WORK="${TMPDIR:-/tmp}/zlan-ts-mwan3-test.$$"
BIN="$WORK/bin"
RULES="$WORK/rules"
STATUS="$WORK/status"
CALLS="$WORK/calls"

cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT INT TERM
mkdir -p "$BIN"
: > "$RULES"
: > "$CALLS"

cat > "$BIN/uci" <<'EOF'
#!/bin/sh
[ "${1:-}" != "-q" ] || shift
case "${1:-}" in
    get)
        case "${2:-}" in
            *.mwan3_failover) printf '%s\n' "${MOCK_FAILOVER:-1}" ;;
            *.mwan3_rule_pref) echo 1305 ;;
            *.mwan3_4g_table) echo auto ;;
            *.mwan3_wan_interface) echo wan ;;
            *.mwan3_wifi_interface) printf '%s\n' "${MOCK_WIFI_INTERFACE:-off}" ;;
            *.mwan3_wifi_table) echo auto ;;
            *.mwan3_4g_interface) echo wan_4g ;;
            wireless.sta.mode) echo sta ;;
            wireless.sta.network) echo wan_wifi ;;
            *) exit 1 ;;
        esac
        ;;
    show)
        case "${2:-}" in
            mwan3)
                cat <<'CONFIG'
mwan3.wan=interface
mwan3.wan_4g=interface
mwan3.wan_wifi=interface
CONFIG
                ;;
            wireless)
                echo 'wireless.sta=wifi-iface'
                ;;
            *) exit 1 ;;
        esac
        ;;
    *) exit 1 ;;
esac
EOF

cat > "$BIN/mwan3" <<'EOF'
#!/bin/sh
[ "${1:-}" = "status" ] || exit 1
cat "$MOCK_STATUS"
EOF

cat > "$BIN/ip" <<'EOF'
#!/bin/sh
case "${1:-} ${2:-} ${3:-}" in
    "-4 rule show")
        cat "$MOCK_RULES"
        ;;
    "-4 route show")
        [ "${4:-}" = "table" ] || exit 1
        for table in ${MOCK_ROUTE_DEFAULT_TABLES:-2}; do
            [ "$table" = "${5:-}" ] && echo "default via 10.0.0.1 dev test0 table $table"
        done
        ;;
    "-4 rule add")
        [ "${4:-}" = "pref" ] && [ "${5:-}" = "1305" ] || exit 1
        [ "${6:-}" = "fwmark" ] && [ "${7:-}" = "0x80000/0xff0000" ] || exit 1
        [ "${8:-}" = "lookup" ] || exit 1
        echo "1305: from all fwmark 0x80000/0xff0000 lookup ${9:-}" >> "$MOCK_RULES"
        echo "add:${9:-}" >> "$MOCK_CALLS"
        ;;
    "-4 rule del")
        [ "${4:-}" = "pref" ] && [ "${5:-}" = "1305" ] || exit 1
        [ "${6:-}" = "fwmark" ] && [ "${7:-}" = "0x80000/0xff0000" ] || exit 1
        [ "${8:-}" = "lookup" ] || exit 1
        grep -F -v "fwmark 0x80000/0xff0000 lookup ${9:-}" "$MOCK_RULES" > "$MOCK_RULES.tmp" || true
        mv "$MOCK_RULES.tmp" "$MOCK_RULES"
        echo "del:${9:-}" >> "$MOCK_CALLS"
        ;;
    "route flush cache")
        echo flush >> "$MOCK_CALLS"
        ;;
    *)
        echo "unexpected ip call: $*" >&2
        exit 1
        ;;
esac
EOF
chmod +x "$BIN/uci" "$BIN/mwan3" "$BIN/ip"

export MOCK_RULES="$RULES" MOCK_STATUS="$STATUS" MOCK_CALLS="$CALLS"
export MOCK_ROUTE_DEFAULT_TABLES="2 3"
export ZLAN_UCI_BIN="$BIN/uci" ZLAN_MWAN3_BIN="$BIN/mwan3" ZLAN_IP_BIN="$BIN/ip"

set_status() {
    printf '%s\n%s\n' \
        " interface wan is $1 00h:00m:00s, uptime 00h:00m:00s and tracking is active" \
        " interface wan_4g is $2 00h:00m:00s, uptime 00h:00m:00s and tracking is active" > "$STATUS"
}

set_status_with_wifi() {
    printf '%s\n%s\n%s\n' \
        " interface wan is $1 00h:00m:00s, uptime 00h:00m:00s and tracking is active" \
        " interface wan_wifi is $2 00h:00m:00s, uptime 00h:00m:00s and tracking is active" \
        " interface wan_4g is $3 00h:00m:00s, uptime 00h:00m:00s and tracking is active" > "$STATUS"
}

assert_contains() {
    case "$1" in *"$2"*) ;; *) echo "missing '$2' in '$1'" >&2; exit 1 ;; esac
}

export MOCK_WIFI_INTERFACE=off
set_status offline online
output="$("$HELPER" sync)"
assert_contains "$output" "changed:4g-ativo-regra-1305-tabela-2"
grep -qF "fwmark 0x80000/0xff0000 lookup 2" "$RULES"

: > "$CALLS"
output="$("$HELPER" sync)"
[ -z "$output" ] || { echo "idempotency failed: $output" >&2; exit 1; }
[ ! -s "$CALLS" ] || { echo "idempotency generated ip calls" >&2; exit 1; }

set_status online online
output="$("$HELPER" sync)"
assert_contains "$output" "changed:regra-1305-removida"
[ ! -s "$RULES" ] || { echo "managed rule was not removed" >&2; exit 1; }

set_status offline online
echo "1305: from all lookup 99" > "$RULES"
: > "$CALLS"
output="$("$HELPER" sync || true)"
assert_contains "$output" "warning:prioridade-1305-ocupada"
[ ! -s "$CALLS" ] || { echo "conflicting rule was modified" >&2; exit 1; }
grep -qF "lookup 99" "$RULES"

: > "$RULES"
: > "$CALLS"
export MOCK_WIFI_INTERFACE=auto
set_status_with_wifi offline online online
output="$("$HELPER" sync)"
assert_contains "$output" "changed:wifi-ativo-regra-1305-tabela-3"
grep -qF "fwmark 0x80000/0xff0000 lookup 3" "$RULES"

set_status_with_wifi offline offline online
output="$("$HELPER" sync)"
assert_contains "$output" "changed:4g-ativo-regra-1305-tabela-2"
grep -qF "fwmark 0x80000/0xff0000 lookup 2" "$RULES"
if grep -qF "lookup 3" "$RULES"; then echo "wifi rule was not removed" >&2; exit 1; fi

set_status_with_wifi online online online
output="$("$HELPER" sync)"
assert_contains "$output" "changed:regra-1305-removida"
[ ! -s "$RULES" ] || { echo "WAN did not regain priority" >&2; exit 1; }

echo "mwan3 failover tests passed"
