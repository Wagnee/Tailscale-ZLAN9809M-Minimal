#!/bin/sh

if [ "${1:-}" != "--apply" ]; then
    echo "Uso: $0 --apply"
    echo "Execute somente depois de confirmar acesso pela Tailnet."
    exit 1
fi

echo "Desativando apenas daemons VPN conhecidos; PPP/celular e TUN serao preservados."
for service in openvpn strongswan ipsec zerotier xl2tpd pptpd; do
    if [ -x "/etc/init.d/$service" ]; then
        "/etc/init.d/$service" stop 2>/dev/null || true
        "/etc/init.d/$service" disable 2>/dev/null || true
        echo "servico desativado: $service"
    fi
done

for module in wireguard l2tp_ppp pppol2tp l2tp_ip l2tp_core; do
    if grep -q "^$module " /proc/modules 2>/dev/null; then
        rmmod "$module" 2>/dev/null && echo "modulo descarregado: $module" || echo "modulo em uso, preservado: $module"
    fi
done

echo "Concluido. Nenhum arquivo do squashfs foi apagado."
