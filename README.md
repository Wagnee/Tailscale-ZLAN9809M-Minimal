# Tailscale ZLAN9809M Minimal

Runtime exclusivo para transformar o ZLAN9809M em um subnet router Tailscale. Não instala telemetria, MQTT ou Modbus. A operação continua disponível por SSH/UCI e um menu LuCI somente leitura apresenta o estado do Tailscale.

O projeto usa o Tailscale oficial **v1.98.5**, compilado para `linux/mipsle` com soft-float. Daemon e CLI são binários separados e recebem somente as features necessárias para TUN, autenticação, iptables e anúncio de sub-redes.

## Resultado do build mínimo

| Componente | Descompactado | UPX em `/tmp` |
|---|---:|---:|
| `tailscaled.min` | 14.287.005 bytes | aproximadamente 3,27 MB |
| `tailscale.min` | 10.092.701 bytes | aproximadamente 2,43 MB |
| Total dinâmico | 24,38 MB | aproximadamente 5,70 MB |

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
wget -4 --no-check-certificate -O /tmp/install-ts-minimal.sh \
  https://raw.githubusercontent.com/Wagnee/Tailscale-ZLAN9809M-Minimal/main/install.sh
echo '4d1b5d11ff751a68b5fa2ca9a8046ed74733537e6e30a047132c69d0a81b1fa7  /tmp/install-ts-minimal.sh' | sha256sum -c -
sh /tmp/install-ts-minimal.sh
```

O firmware não consegue validar a cadeia TLS atual do GitHub. O SHA-256 acima autentica o script obtido; o script contém o hash fixo do payload, e o payload contém os hashes fixos dos dois binários.

O instalador:

- valida o equipamento e não usa `opkg`;
- força IPv4 nos downloads porque o firmware resolve AAAA sem possuir rota IPv6 funcional;
- tolera a cadeia de certificados antiga do firmware e valida o payload com SHA-256 fixado no instalador;
- preserva `/etc/tailscale/tailscaled.state`;
- remove do overlay os componentes dos projetos híbrido/offline anteriores;
- não grava os binários Tailscale na flash;
- detecta automaticamente uma LAN `/24` pelo UCI;
- baixa daemon e CLI separadamente para `/tmp`, com SHA-256 fixado;
- limita o heap do daemon a 32 MiB e o da CLI a 12 MiB;
- monitora o `mwan3` e corrige automaticamente a rota do Tailscale com prioridade WAN → Wi-Fi → 4G;
- instala o painel leve **Serviços → Tailscale** sem criar outro daemon;
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

## Interface LuCI

O menu **Serviços → Tailscale** consulta a LocalAPI somente quando a página é carregada. Ele mostra:

- estado e versões do serviço;
- saída atual pela WAN, Wi-Fi ou 4G;
- IP, hostname, nome DNS e tailnet;
- rota anunciada configurada;
- quantidade de peers online, ativos e conhecidos;
- lista de dispositivos com IP, sistema e conexão direta/DERP;
- memória, estado do failover e últimas linhas do log.

O painel é somente leitura: não altera configuração nem mantém processos adicionais na RAM. Se o menu não aparecer logo após atualizar, recarregue a interface; o instalador limpa os caches do LuCI automaticamente.

## Dispositivos locais no LuCI

O menu **Serviços → Dispositivos locais** é um inventário somente leitura da rede local. Ele cruza:

- leases DHCP, incluindo hostname quando informado;
- cache ARP e neighbor IPv4/IPv6, que revela dispositivos com IP estático após comunicação;
- tabela MAC da bridge, para dispositivos Ethernet vistos mesmo sem DHCP;
- estações Wi-Fi associadas ao rádio do roteador.

Não há como descobrir com certeza o IP de um equipamento estático que nunca transmite tráfego. Nessa situação a tela pode mostrar o MAC e a interface, mas não um IP. O painel não faz varredura ativa e não instala pacotes adicionais.

## Failover WAN/Wi-Fi/4G

O firmware mantém a rota da WAN Ethernet desconectada na tabela principal. Como o fwmark do Tailscale consulta essa tabela antes das regras do `mwan3`, o controle e os DERPs ficavam inacessíveis quando apenas uma rota alternativa estava online.

Desde a versão 0.4.0, a ordem é `wan` → Wi-Fi cliente → `wan_4g`. O Wi-Fi só é escolhido quando uma interface `mode=sta` também está configurada e monitorada no `mwan3`, cujo status esteja `online`. A tabela de rota é derivada da própria configuração do `mwan3`; portanto, continua correta mesmo se a ordem das interfaces mudar.

```sh
/usr/bin/zlan-ts-mwan3 status
ip -4 rule show
```

Caso o Wi-Fi cliente use um nome não detectável automaticamente, informe-o uma vez:

```sh
uci set zlan_ts_minimal.main.mwan3_wifi_interface='wan_wifi'
uci set zlan_ts_minimal.main.mwan3_wifi_table='auto'
uci commit zlan_ts_minimal
/usr/bin/zlan-ts-mwan3 sync
```

Detalhes técnicos, configuração e rollback estão em [docs/FAILOVER_4G.md](docs/FAILOVER_4G.md).

## Reboot e factory reset

Reboot ou queda de energia preservam configuração e identidade; os binários são baixados novamente para `/tmp`. Um factory reset pelo botão apaga o `/overlay`, portanto remove o projeto e a identidade Tailscale. Sobreviver a esse reset exige firmware customizado com o bootstrap em `/rom` ou um mecanismo persistente oficialmente suportado pelo fabricante. Não é seguro usar partições MTD reservadas sem documentação do ZLAN.

## Features mantidas

- `advertiseroutes` e sua dependência de controle `c2n`;
- `osrouter` para interface TUN e rotas do kernel;
- `iptables` para encaminhamento/NAT do subnet router;
- `ipnbus` para login e comando `tailscale up`;
- `unixsocketidentity` para reconhecer o UID 0 e autorizar a CLI root na LocalAPI;
- `bakedroots` para validar o controle Tailscale mesmo com as CAs antigas do firmware;
- CLI separada, não embutida no daemon.

O modo netfilter padrão é `on`, para que o Tailscale conecte suas chains ao `FORWARD` e aplique o SNAT da subnet. `nodivert` continua disponível na configuração, mas exige regras iptables externas e não é usado como padrão neste firmware.

Entre as features removidas estão TPM, DNS, netstack/gVisor, SSH, Taildrop, Serve/Funnel, exit node, update automático, Kubernetes, AWS, BGP, captura, métricas, postura, logtail, proxy, web client, QR code e integrações desktop/systemd.

## VPNs e menus do firmware

O relatório mostra `/rom` squashfs de 7,9 MB e overlay originalmente usando apenas 858 KB. Os módulos WireGuard/L2TP e a maior parte do LuCI/idiomas estão no `/rom`. Apagá-los pelo overlay não recupera a flash física; apenas cria whiteouts e pode aumentar o uso do JFFS2.

Por isso o instalador remove somente arquivos dos projetos anteriores que realmente foram gravados no overlay. Para auditar o equipamento:

```sh
wget -4 --no-check-certificate -O /tmp/audit.sh \
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

Consulte [docs/HARDWARE.md](docs/HARDWARE.md), [docs/BUILD.md](docs/BUILD.md), [docs/TRIMMING.md](docs/TRIMMING.md), [docs/FAILOVER_4G.md](docs/FAILOVER_4G.md) e o [histórico completo da investigação](docs/CONVERSATION_HISTORY.md).

## Licença

BSD-3-Clause. Os binários derivados do Tailscale mantêm a licença oficial em [THIRD_PARTY_LICENSES/Tailscale.txt](THIRD_PARTY_LICENSES/Tailscale.txt).
