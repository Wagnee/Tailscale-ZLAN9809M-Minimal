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
[ "${1:-}" = "get" ] || exit 1
case "${2:-}" in
    *.mwan3_failover) printf '%s\n' "${MOCK_FAILOVER:-1}" ;;
    *.mwan3_rule_pref) echo 1305 ;;
    *.mwan3_4g_table) echo 2 ;;
    *.mwan3_wan_interface) echo wan ;;
    *.mwan3_4g_interface) echo wan_4g ;;
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
case "$*" in
    "-4 rule show")
        cat "$MOCK_RULES"
        ;;
    "-4 route show table 2")
        [ "${MOCK_ROUTE_DEFAULT:-0}" = "1" ] && echo "default via 10.0.0.1 dev usb0 table 2"
        ;;
    "-4 rule add pref 1305 fwmark 0x80000/0xff0000 lookup 2")
        echo "1305: from all fwmark 0x80000/0xff0000 lookup 2" >> "$MOCK_RULES"
        echo add >> "$MOCK_CALLS"
        ;;
    "-4 rule del pref 1305 fwmark 0x80000/0xff0000 lookup 2")
        grep -F -v "fwmark 0x80000/0xff0000 lookup 2" "$MOCK_RULES" > "$MOCK_RULES.tmp" || true
        mv "$MOCK_RULES.tmp" "$MOCK_RULES"
        echo del >> "$MOCK_CALLS"
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
export MOCK_ROUTE_DEFAULT=1
export ZLAN_UCI_BIN="$BIN/uci" ZLAN_MWAN3_BIN="$BIN/mwan3" ZLAN_IP_BIN="$BIN/ip"

set_status() {
    printf '%s\n%s\n' \
        " interface wan is $1 00h:00m:00s, uptime 00h:00m:00s and tracking is active" \
        " interface wan_4g is $2 00h:00m:00s, uptime 00h:00m:00s and tracking is active" > "$STATUS"
}

assert_contains() {
    case "$1" in *"$2"*) ;; *) echo "missing '$2' in '$1'" >&2; exit 1 ;; esac
}

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

echo "mwan3 failover tests passed"
