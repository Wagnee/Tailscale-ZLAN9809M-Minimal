#!/bin/sh

set -u
PURGE=0
[ "${1:-}" = "--purge" ] && PURGE=1

/etc/init.d/zlan-ts-minimal stop 2>/dev/null || true
/etc/init.d/zlan-ts-minimal disable 2>/dev/null || true
/usr/bin/zlan-ts-mwan3 remove >/dev/null 2>&1 || true
rm -f /etc/init.d/zlan-ts-minimal /usr/bin/zlan-ts-minimal /usr/bin/zlan-ts /usr/bin/zlan-ts-mwan3
rm -f /etc/hotplug.d/iface/95-zlan-ts-mwan3
rm -f /usr/lib/lua/luci/controller/zlan_tailscale.lua
rm -rf /usr/lib/lua/luci/view/zlan_tailscale
rm -f /usr/lib/lua/luci/controller/zlan_devices.lua
rm -rf /usr/lib/lua/luci/view/zlan_devices
rm -rf /usr/share/zlan-ts-minimal /tmp/zlan-ts-minimal
rm -f /tmp/zlan-ts-minimal.log /tmp/zlan-ts-auth-url
rm -f /etc/sysctl.d/99-zlan-ts-minimal.conf
rm -f /tmp/luci-indexcache
rm -rf /tmp/luci-modulecache

if [ "$PURGE" = "1" ]; then
    rm -f /etc/config/zlan_ts_minimal
    rm -rf /etc/tailscale
    echo "Configuracao e identidade removidas."
else
    echo "Configuracao e identidade em /etc/tailscale preservadas."
fi
echo "Tailscale minimal removido."
