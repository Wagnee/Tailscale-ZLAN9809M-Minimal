# Tailscale ZLAN9809M Minimal

Runtime exclusivo para transformar o ZLAN9809M em um subnet router Tailscale. Não instala telemetria, MQTT, Modbus ou menus LuCI. Toda a configuração é feita por SSH/UCI.

O projeto usa o Tailscale oficial **v1.98.5**, compilado para `linux/mipsle` com soft-float. Daemon e CLI são binários separados e recebem somente as features necessárias para TUN, autenticação, iptables e anúncio de sub-redes.

## Resultado do build mínimo

| Componente | Descompactado | UPX em `/tmp` |
|---|---:|---:|
| `tailscaled.min` | 14.155.933 bytes | aproximadamente 3,26 MB |
| `tailscale.min` | 10.092.701 bytes | aproximadamente 2,43 MB |
| Total dinâmico | 24,25 MB | aproximadamente 5,69 MB |

O binário combinado anterior expandia para aproximadamente 38,8 MB em cada processo. Separar a CLI evita carregar novamente todo o daemon durante `tailscale up`.

## Hardware validado

- ZLAN9809M CAT1, flash SPI NOR de 16 MB;
- MediaTek MT7628AN, MIPS 24KEc a 580 MHz;
- 128 MB de RAM, sem swap;
- OpenWrt 21.02.0 `ramips/mt76x8`, kernel 5.4.143 customizado;
- `/dev/net/tun` já funcional;
- overlay JFFS2 de 6.080 KB;
- `/tmp` de aproximadamente 60 MB.

## Instalação ou atualização

```sh
wget -O /tmp/install-ts-minimal.sh \
  https://raw.githubusercontent.com/Wagnee/Tailscale-ZLAN9809M-Minimal/main/install.sh
sh /tmp/install-ts-minimal.sh
```

O instalador:

- valida o equipamento e não usa `opkg`;
- preserva `/etc/tailscale/tailscaled.state`;
- remove do overlay os componentes dos projetos híbrido/offline anteriores;
- não grava os binários Tailscale na flash;
- detecta automaticamente uma LAN `/24` pelo UCI;
- baixa daemon e CLI separadamente para `/tmp`, com SHA-256 fixado;
- limita o heap do daemon a 32 MiB e o da CLI a 12 MiB;
- habilita `net.ipv4.ip_forward` e inicia o serviço.

Se a auth key não for informada durante a instalação, obtenha a URL de login com:

```sh
/etc/init.d/zlan-ts-minimal status
```

Para operação totalmente automática, gere uma auth key no painel Tailscale. Em uma instalação nova, informe a chave no prompt. Em uma instalação já existente, grave-a antes de reiniciar:

```sh
uci set zlan_ts_minimal.main.auth_key='tskey-auth-...'
uci commit zlan_ts_minimal
/etc/init.d/zlan-ts-minimal restart
```

## Configuração por SSH

```sh
uci show zlan_ts_minimal
uci set zlan_ts_minimal.main.hostname='zlan9809m'
uci set zlan_ts_minimal.main.routes='192.168.8.0/24'
uci commit zlan_ts_minimal
/etc/init.d/zlan-ts-minimal restart
```

Com base no log do equipamento analisado, a LAN atual é `192.168.8.0/24`. Depois da conexão, aprove essa rota no painel administrativo da Tailnet, salvo quando houver `autoApprovers` configurado.

Estado e logs:

```sh
/etc/init.d/zlan-ts-minimal status
zlan-ts status
tail -f /tmp/zlan-ts-minimal.log
free
df -h /overlay /tmp
```

## Features mantidas

- `advertiseroutes` e sua dependência de controle `c2n`;
- `osrouter` para interface TUN e rotas do kernel;
- `iptables` para encaminhamento/NAT do subnet router;
- `ipnbus` para login e comando `tailscale up`;
- CLI separada, não embutida no daemon.

O modo netfilter padrão é `on`, para que o Tailscale conecte suas chains ao `FORWARD` e aplique o SNAT da subnet. `nodivert` continua disponível na configuração, mas exige regras iptables externas e não é usado como padrão neste firmware.

Entre as features removidas estão TPM, DNS, netstack/gVisor, SSH, Taildrop, Serve/Funnel, exit node, update automático, Kubernetes, AWS, BGP, captura, métricas, postura, logtail, proxy, web client, QR code e integrações desktop/systemd.

## VPNs e menus do firmware

O relatório mostra `/rom` squashfs de 7,9 MB e overlay originalmente usando apenas 858 KB. Os módulos WireGuard/L2TP e a maior parte do LuCI/idiomas estão no `/rom`. Apagá-los pelo overlay não recupera a flash física; apenas cria whiteouts e pode aumentar o uso do JFFS2.

Por isso o instalador remove somente arquivos dos projetos anteriores que realmente foram gravados no overlay. Para auditar o equipamento:

```sh
wget -O /tmp/audit.sh \
  https://raw.githubusercontent.com/Wagnee/Tailscale-ZLAN9809M-Minimal/main/tools/audit-storage.sh
sh /tmp/audit.sh
```

Depois que o acesso pela Tailnet estiver confirmado, serviços VPN extras podem ser desativados para economizar RAM usando `tools/disable-other-vpns.sh`. PPP/celular e TUN nunca são removidos.

## Build reproduzível

Os scripts em `build/` fixam:

- tag Tailscale `v1.98.5`, objeto assinado `8f8fe6a2e167459ed0f62616287b61b0b0a54eb5` e commit `295179bf294d3d076397bcef6815b1d6854e197d`;
- Go 1.26.3;
- `GOARCH=mipsle`, `GOMIPS=softfloat`, `CGO_ENABLED=0`;
- UPX 5.2.0;
- orçamento máximo de 6,5 MB para os dois arquivos dinâmicos.

Consulte [docs/HARDWARE.md](docs/HARDWARE.md), [docs/BUILD.md](docs/BUILD.md) e [docs/TRIMMING.md](docs/TRIMMING.md).

## Licença

BSD-3-Clause. Os binários derivados do Tailscale mantêm a licença oficial em [THIRD_PARTY_LICENSES/Tailscale.txt](THIRD_PARTY_LICENSES/Tailscale.txt).
