#!/bin/sh

# Somente leitura. Nao altera pacotes, modulos ou configuracoes.

echo "===== MEMORIA ====="
free 2>&1 || true
echo "===== FLASH ====="
df -k /rom /overlay /tmp 2>&1 || true
echo "===== OVERLAY REAL ====="
du -ak /overlay/upper 2>/dev/null | sort -n | tail -n 40
echo "===== MODULOS VPN CARREGADOS ====="
lsmod 2>/dev/null | grep -i -e wireguard -e l2tp -e ipsec -e gre -e tun || true
echo "===== SERVICOS VPN ====="
for service in openvpn strongswan ipsec zerotier xl2tpd pptpd; do
    [ ! -e "/etc/init.d/$service" ] || ls -l "/etc/init.d/$service"
done
echo "===== PACOTES/MENUS CANDIDATOS ====="
for list in /usr/lib/opkg/info/*.list; do
    [ -f "$list" ] || continue
    package="${list##*/}"
    package="${package%.list}"
    case "$package" in
        *openvpn*|*wireguard*|*strongswan*|*ipsec*|*zerotier*|*pptp*|*l2tp*|luci-i18n-*-zh-cn|luci-app-diag*) ;;
        *) continue ;;
    esac
    rom_files=0
    overlay_files=0
    while IFS= read -r path; do
        case "$path" in /*) ;; *) path="/$path" ;; esac
        [ ! -e "/rom$path" ] || rom_files=$((rom_files + 1))
        [ ! -e "/overlay/upper$path" ] || overlay_files=$((overlay_files + 1))
    done < "$list"
    echo "$package: rom=$rom_files overlay=$overlay_files"
done
echo "Arquivos somente em /rom nao podem ser removidos para liberar overlay."
