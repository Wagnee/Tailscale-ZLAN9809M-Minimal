# Histórico da investigação e desenvolvimento

Este documento registra a conversa que levou ao projeto **Tailscale ZLAN9809M Minimal**, entre 23 e 24 de junho de 2026. Ele preserva pedidos, sintomas, decisões, erros encontrados e correções aplicadas.

## Nota de segurança

- Auth keys, tokens e qualquer outro segredo foram substituídos por `[REDACTED — REVOGADA]`.
- Uma auth key chegou a aparecer em um log da conversa. O usuário confirmou que ela foi revogada.
- O texto é um registro técnico sanitizado, não uma transcrição que replique segredos.
- O repositório é público; nunca devem ser adicionadas novas auth keys aos arquivos, issues ou logs.

## Repositórios envolvidos

- Projeto offline original: `Wagnee/Tailscale-ZLAN9809M--Off-Line`.
- Projeto online usado como referência: `Wagnee/Tailscale-ZLAN9809M---OnlineOptimized`.
- Primeira abordagem híbrida: `Wagnee/Tailscale-ZLAN9809M-Hybrid`.
- Projeto final focado apenas no Tailscale: `Wagnee/Tailscale-ZLAN9809M-Minimal`.

## 1. Problemas do projeto offline original

### Pedido inicial

O usuário pediu a leitura completa da documentação do repositório offline e a correção dos erros de instalação no ZLAN9809M. Também autorizou que as alterações fossem enviadas diretamente ao GitHub.

### Primeiro erro de OPKG

```text
Collected errors:
 * opkg_conf_parse_file: Duplicate src declaration (openwrt_core https://downloads.openwrt.org/releases/21.02.0/targets/ramips/mt76x8/packages). Skipping.
 * opkg_conf_load: Could not create lock file /var/lock/opkg.lock: No such file or directory.
```

As primeiras ações trataram:

- diretório ausente para o lock do OPKG;
- feeds duplicados;
- preparação do OPKG antes de instalar pacotes.

### Segundo erro de feeds

Depois da primeira correção, o OPKG tentou usar fontes inválidas:

```text
Downloading https://openwrt.org/Packages.gz
Failed to decode signature
Signature check failed.

Downloading https://downloads.openwrt.org/releases/21.02.0/packages/mipsel_24kc/lora/Packages.gz
*** Failed to download the package list
```

O usuário pediu que os pacotes fossem baixados e instalados sequencialmente, em vez de baixar todos antes de instalar.

### Terceiro erro: script AWK incompatível

```text
awk: bad regex '^https?:\/\/downloads\.openwrt\.org\/releases\/[^': Missing ']'
```

Esse erro reforçou que o ambiente utiliza BusyBox/awk reduzido e que expressões aceitas em ambientes GNU não eram necessariamente portáveis para o firmware.

## 2. Auditoria real do equipamento

O usuário forneceu um probe somente leitura do hardware e pediu que nenhuma nova atualização fosse feita sem considerar o equipamento real.

### Hardware confirmado

- equipamento: ZLAN9809M CAT1, identificado como `ZLAN zlan-cat1 (16M flash)`;
- SoC: MediaTek MT7628AN;
- CPU: MIPS 24KEc, 580 MHz, um núcleo;
- arquitetura: little-endian `mipsel_24kc`, soft-float;
- RAM reportada: 123.060 KB, sem swap;
- flash SPI NOR: 16 MB;
- firmware: OpenWrt 21.02.0 r16279;
- kernel customizado: 5.4.143;
- target: `ramips/mt76x8`;
- TUN já carregado e disponível em `/dev/net/tun`.

### Armazenamento confirmado

```text
/rom      7936 KB  squashfs somente leitura
/overlay  6080 KB  JFFS2 gravável
/tmp     61528 KB  tmpfs em RAM
```

Na auditoria inicial, aproximadamente 5.280 KB estavam livres no overlay e 53.008 KB no tmpfs.

### Decisão importante sobre remoções

Foi concluído que OpenVPN, WireGuard, L2TP, traduções chinesas, diagnóstico e menus LuCI presentes no `/rom` não podem ser removidos para recuperar overlay. O `/rom` é squashfs somente leitura. Uma remoção pelo overlay criaria whiteouts e poderia **aumentar** o consumo de JFFS2.

Por isso:

- arquivos dos projetos anteriores gravados no `/overlay/upper` podem ser removidos;
- arquivos de fábrica no `/rom` são preservados;
- uma remoção real do firmware de fábrica exigiria recompilar e gravar uma imagem completa, com risco de brick;
- PPP/celular, TUN, network, firewall e mwan3 nunca devem ser removidos.

### Incompatibilidade dos feeds oficiais

O kernel do fabricante usa ABI customizada. Instalar `kmod-tun` ou outros módulos do feed oficial OpenWrt 21.02 poderia substituir módulos compatíveis por pacotes com outro hash de ABI. A estratégia final eliminou completamente o uso de `opkg`.

## 3. Abordagem híbrida anterior

O usuário pediu um projeto do zero combinando:

- todas as funções do repositório offline;
- o método de carregamento do `tailscale.combined` do projeto online;
- armazenamento persistente para configuração/telemetria;
- download dinâmico do Tailscale para `/tmp` quando houvesse internet.

Foi criado o projeto híbrido com LuCI, MQTT, Modbus e Tailscale dinâmico.

### Keepalive MQTT

O usuário perguntou em qual tópico o keepalive era publicado. Pelo código híbrido:

```text
<prefixo>/system/keepalive
```

Com o prefixo padrão `zlan9809m`, o tópico era:

```text
zlan9809m/system/keepalive
```

### Primeiro daemon Tailscale funcionando parcialmente

O `tailscale.combined` v1.96.2 iniciou o engine, criou TUN e configurou iptables, mas permaneceu sem login:

```text
Switching ipn state NoState -> NeedsLogin (WantRunning=false, nm=false)
health(warnable=wantrunning-false): error: Tailscale is stopped.
```

O processo combinado expandia para aproximadamente 38,8 MB. Executar daemon e CLI com o mesmo binário combinado duplicava grande parte desse código na memória durante `tailscale up`, situação inadequada para os aproximadamente 37–51 MB de memória disponível observados.

## 4. Mudança de escopo: somente Tailscale

O usuário decidiu que MQTT, Modbus e LuCI não eram essenciais. O novo objetivo passou a ser:

- fazer somente o Tailscale funcionar;
- anunciar a LAN para a Tailnet;
- aceitar configuração somente por SSH;
- remover do overlay os projetos antigos;
- carregar os binários em `/tmp`;
- manter apenas identidade/configuração na flash;
- recompilar o Tailscale removendo recursos não necessários.

Foi criado o repositório `Tailscale-ZLAN9809M-Minimal`.

## 5. Arquitetura mínima escolhida

### Versão e target

- Tailscale oficial v1.98.5;
- tag assinada `v1.98.5`;
- commit `295179bf294d3d076397bcef6815b1d6854e197d`;
- Go 1.26.3;
- `GOOS=linux`;
- `GOARCH=mipsle`;
- `GOMIPS=softfloat`;
- `CGO_ENABLED=0`;
- compactação UPX 5.2.0.

### Daemon e CLI separados

Em vez de `tailscale.combined`, foram produzidos:

- `tailscaled.min` para o daemon;
- `tailscale.min` para a CLI temporária.

Isso reduz o pico de memória durante login e configuração.

### Recursos preservados na versão final

```text
advertiseroutes
osrouter
iptables
ipnbus
unixsocketidentity
bakedroots
```

Função de cada recurso:

- `advertiseroutes`: anúncio da subnet;
- `osrouter`: TUN e rotas do sistema;
- `iptables`: regras de encaminhamento e SNAT;
- `ipnbus`: fluxo de login e `tailscale up`;
- `unixsocketidentity`: identificação do UID root na LocalAPI;
- `bakedroots`: raízes ISRG X1/X2 usadas como fallback TLS em dispositivos antigos.

### Recursos removidos

Entre os recursos omitidos estão TPM, DNS do sistema, netstack/gVisor, SSH do Tailscale, Taildrop, Serve/Funnel, exit node, update automático, Kubernetes, AWS, BGP, captura, métricas, postura, logtail, proxy, web client, QR code e integrações desktop/systemd.

### Persistência e boot

- identidade: `/etc/tailscale/tailscaled.state`;
- configuração UCI: `/etc/config/zlan_ts_minimal`;
- daemon e CLI: `/tmp/zlan-ts-minimal/`;
- log: `/tmp/zlan-ts-minimal.log`;
- URL pendente de autenticação: `/tmp/zlan-ts-auth-url`;
- serviço: `/etc/init.d/zlan-ts-minimal`, habilitado no boot.

Após reiniciar, `/tmp` é limpo. O loader baixa novamente os binários, valida SHA-256, inicia o daemon com a identidade persistida e reaplica a rota anunciada. Se não houver internet, tenta novamente a cada 60 segundos.

## 6. Iterações do projeto mínimo

### 0.1.0 — primeira versão mínima

Implementou:

- instalador sem OPKG;
- validação exata do hardware;
- remoção segura dos arquivos conhecidos no overlay;
- migração de configuração/estado dos projetos anteriores;
- daemon e CLI separados;
- limites `GOMEMLIMIT`;
- `netfilter-mode=on`;
- detecção da LAN `192.168.8.0/24`;
- build reproduzível e GitHub Actions.

O CI inicialmente encontrou dois problemas do processo de build:

1. `UPX` era usado como variável de ambiente, mas esse nome é reservado pelo próprio programa. Foi substituído por `UPX_BIN`.
2. O UPX no Linux recusava os artefatos sem bit executável. O build passou a usar `0755` durante a compactação e retornar os arquivos publicados para `0644`.

Também foi detectada diferença entre builds hospedados no Windows e Linux por causa do checkout/terminadores de linha. Os artefatos oficiais passaram a ser os reproduzidos byte a byte pelo CI Linux.

### Falha 0.1.0: LocalAPI negando root

Sintoma:

```text
Access denied: status access denied
```

O build mínimo havia removido `unixsocketidentity`. Sem peer credentials no socket Unix, o Tailscale tratava a conexão como desconhecida e somente leitura, mesmo executada por root.

### 0.1.1 — restauração da identidade do socket Unix

Foi preservado `unixsocketidentity` e adicionado um teste de regressão no CI para impedir que `ts_omit_unixsocketidentity` volte ao build.

Depois disso:

```text
zlan-ts status
Logged out.
```

Esse resultado confirmou que daemon, socket e LocalAPI já estavam funcionando. Restava somente a autenticação no controle.

### Falha de download por IPv6

Sintoma:

```text
Connecting to 2606:50c0:8003::154:443
Connection error: Connection failed
```

O firmware resolvia o registro AAAA do GitHub, mas não possuía rota IPv6 funcional.

### 0.1.2 — downloads forçados por IPv4

Todos os downloads passaram a usar `wget -4`:

- bootstrap do instalador;
- payload persistente;
- daemon;
- CLI;
- ferramentas auxiliares documentadas.

### Falha de certificado do firmware

Sintoma:

```text
Connecting to 185.199.108.133:443
Connection error: Invalid SSL certificate
```

O conjunto de CAs do firmware de 2021 não validava a cadeia TLS atual do GitHub.

### 0.1.3 — IPv4, compatibilidade TLS e cadeia de hashes

Os downloads passaram a usar:

```text
wget -4 --no-check-certificate
```

Para não confiar cegamente no conteúdo recebido, foi criada uma cadeia de integridade:

1. o operador confere o SHA-256 do `install.sh`;
2. o `install.sh` contém o SHA-256 fixo do payload;
3. o payload contém os SHA-256 fixos do daemon e da CLI;
4. o CI valida toda a cadeia antes e depois do build.

### Auth key não autenticava e não havia URL

O usuário instalou a 0.1.3, informou hostname `sr2`, subnet `192.168.8.0/24` e uma auth key. O serviço ficou:

```text
versao: 0.1.3
loader: running
LocalAPI: ready
login: sem URL pendente
```

E a CLI respondeu:

```text
Logged out.
```

A auth key presente no transcript foi revogada e não é reproduzida neste histórico:

```text
[REDACTED — REVOGADA]
```

### Causa final: raízes TLS internas removidas

O mecanismo oficial de feature tags havia removido `bakedroots`. No código do Tailscale, esse recurso incorpora ISRG Root X1 e X2 e existe especificamente como fallback para equipamentos antigos sem CAs atuais.

Sem `bakedroots`, o daemon dependia exclusivamente das raízes do firmware, que já haviam falhado ao validar o GitHub. Assim, ele não conseguia completar a comunicação TLS com o controle Tailscale para validar a auth key ou gerar a URL de login.

### 0.1.4 — restauração das raízes TLS do Tailscale

Foi preservado `bakedroots` e adicionado um teste de regressão que impede `ts_omit_bakedroots`.

Artefatos finais 0.1.4:

| Artefato | Tamanho UPX | SHA-256 |
|---|---:|---|
| `tailscaled.min` | 3.271.136 bytes | `155723559fc24ef478685e7b73bc6cea1207c497eba5088342146d0934b7c598` |
| `tailscale.min` | 2.431.808 bytes | `9294228f2ebc7009b919f43145d08f4f076a3d8a8855f986631445b7c1f362c5` |

O custo de restaurar as raízes TLS foi de poucos kilobytes compactados.

## 7. Resultado final confirmado

Depois da versão 0.1.4, o usuário confirmou:

> agora funcionou

O resultado final atende ao objetivo principal:

- Tailscale autenticado no ZLAN9809M;
- daemon compatível com MIPS 24KEc/soft-float;
- consumo adequado à RAM disponível;
- binários dinâmicos em `/tmp`;
- identidade persistente no overlay;
- subnet `192.168.8.0/24` anunciada;
- reconexão automática após reboot;
- tentativas automáticas quando a internet não está disponível no boot;
- nenhuma dependência de OPKG ou módulos de feeds públicos.

## 8. Procedimento final utilizado

O hash do instalador muda a cada versão e deve sempre ser obtido no README atual. O fluxo é:

```sh
uci -q delete zlan_ts_minimal.main.auth_key
uci commit zlan_ts_minimal

wget -4 --no-check-certificate -O /tmp/install-ts-minimal.sh \
  'https://raw.githubusercontent.com/Wagnee/Tailscale-ZLAN9809M-Minimal/main/install.sh'

# Conferir o SHA-256 publicado no README antes de executar.
sha256sum /tmp/install-ts-minimal.sh

sh /tmp/install-ts-minimal.sh
sleep 25
/etc/init.d/zlan-ts-minimal status
cat /tmp/zlan-ts-auth-url
```

Se necessário, a URL pode ser solicitada diretamente:

```sh
zlan-ts login
```

Depois do login:

```sh
zlan-ts status
```

## 9. Operação após reinicialização

O usuário perguntou se os dispositivos voltariam a conectar depois de reiniciar. A resposta final foi sim, desde que:

- o dispositivo continue autorizado na Tailnet;
- a identidade em `/etc/tailscale/tailscaled.state` seja preservada;
- o serviço permaneça habilitado;
- exista internet em algum momento após o boot;
- a rota anunciada continue aprovada no painel Tailscale.

Verificação do autostart:

```sh
/etc/init.d/zlan-ts-minimal enabled && echo "Autostart habilitado"
```

## 10. Lições técnicas consolidadas

1. O firmware do fabricante não deve ser tratado como um OpenWrt 21.02 genérico.
2. Módulos do kernel dos feeds públicos não são compatíveis com a ABI customizada.
3. Espaço em `/rom` não pode ser recuperado por remoções no overlay.
4. Scripts destinados ao equipamento devem ser compatíveis com BusyBox ash/awk/wget.
5. O equipamento resolve IPv6 mesmo sem rota IPv6; downloads devem forçar IPv4.
6. A cadeia de CAs do firmware é antiga; downloads precisam de hashes fixos.
7. `unixsocketidentity` é necessário para a CLI root acessar a LocalAPI.
8. `bakedroots` é necessário para o daemon falar com o controle Tailscale em firmwares antigos.
9. O binário combinado desperdiça memória durante `tailscale up`; daemon e CLI separados são mais adequados.
10. CI que apenas compila não é suficiente: os artefatos publicados, permissões, arquitetura, UPX e cadeia de hashes precisam ser reproduzidos e comparados.

## 11. Commits principais

- `864212f` — primeira implementação mínima;
- `a68a111` — normalização de permissões antes do UPX;
- `4d477c3` — artefatos MIPS reproduzíveis em Linux;
- `c313399` — restauração da autorização root na LocalAPI;
- `4e73927` — downloads forçados por IPv4;
- `0f60fce` — cadeia de hashes para clientes TLS antigos;
- `b14db8e` — restauração das raízes TLS para login no controle.

## 12. Estado de segurança ao encerrar a conversa

- auth keys expostas: revogadas pelo usuário;
- auth keys registradas neste documento: nenhuma;
- configuração recomendada: autenticação interativa por URL;
- segredos persistentes: somente o estado criptográfico normal do Tailscale em `/etc/tailscale/tailscaled.state` no equipamento.

## 13. Falha quando somente o 4G estava conectado

Depois de confirmar o funcionamento pela WAN Ethernet, o usuário informou que o Tailscale parava de conectar quando a internet vinha exclusivamente do modem 4G. Um novo probe foi executado com o cabo WAN removido.

Os logs demonstraram simultaneamente:

- `wan` offline e `wan_4g` online no `mwan3`;
- ping IPv4 e download HTTPS funcionando pelo 4G;
- default route da Ethernet ainda presente na tabela `main` com métrica 1;
- default route do `usb0` presente na tabela 2 e na `main` com métrica 2;
- tentativas IPv4 do controle/DERP do Tailscale expirando;
- netcheck sem UDP, IPv4 ou região DERP disponível.

As regras relevantes eram:

```text
1310: from all fwmark 0x80000/0xff0000 lookup main
1330: from all fwmark 0x80000/0xff0000 lookup default
1350: from all fwmark 0x80000/0xff0000 unreachable
2002: from all fwmark 0x200/0x3f00 lookup 2
```

O Tailscale detecta `mwan3` no OpenWrt e desloca suas regras para a faixa 1300. Entretanto seu fwmark consultava a tabela principal na prioridade 1310, antes da regra 2002 do `mwan3`, e escolhia a WAN Ethernet inativa.

A correção temporária abaixo foi aplicada e o usuário confirmou que funcionou:

```sh
ip -4 rule add pref 1305 fwmark 0x80000/0xff0000 lookup 2
ip route flush cache
```

## 14. Versão 0.2.0 — failover WAN/4G automático

A correção confirmada foi incorporada de forma dinâmica e idempotente:

- helper `/usr/bin/zlan-ts-mwan3`;
- regra instalada somente quando `wan` está offline, `wan_4g` online e a tabela 2 possui default route;
- remoção automática quando a WAN retorna ou o 4G deixa de estar utilizável;
- proteção contra conflito na prioridade 1305;
- monitoramento a cada 15 segundos;
- sincronização por hotplug de interface;
- status integrado ao init script;
- testes de regressão com WAN, 4G, idempotência e conflito de prioridade.

Também foi esclarecida a diferença de persistência:

- reboot e queda de energia preservam `/overlay` e a identidade;
- factory reset apaga o overlay e restaura `/rom`;
- sobreviver a factory reset requer firmware customizado ou suporte persistente documentado pelo fabricante;
- partições MTD reservadas não devem ser usadas sem documentação e método de recuperação.

## 15. Versão 0.3.0 — painel LuCI do Tailscale

Depois de validar o retorno automático do 4G para a WAN, o usuário pediu um menu chamado **Tailscale** na interface web para acompanhar a operação sem depender do SSH.

Foi criado um painel somente leitura em **Serviços → Tailscale**. Ele consulta a LocalAPI uma única vez ao carregar a página e mostra:

- estado do backend e versões;
- IP Tailscale, hostname, DNS e nome da tailnet;
- rota anunciada configurada no UCI;
- saída de internet atual pela WAN ou pelo 4G;
- quantidade de peers online, ativos e conhecidos;
- tabela de peers com IP, sistema operacional e conexão direta/DERP;
- autenticação pendente, memória, diagnóstico do serviço/failover e log recente.

Nenhum novo daemon foi adicionado. A CLI temporária já existente executa apenas durante a consulta da página e permanece sujeita ao limite de memória configurado. O painel não permite alterar configuração, iniciar ou parar serviços, reduzindo a superfície de erro e mantendo o SSH/UCI como caminho administrativo.

O CI passou a validar o controller com Lua 5.1 e a sintaxe dos blocos Lua do template LuCI, correspondente à geração usada pelo OpenWrt 21.02.

## 16. Versão 0.4.0 — prioridade WAN, Wi-Fi e 4G

O usuário observou que o equipamento também possui Wi-Fi e definiu a prioridade correta de saída para o Tailscale:

```text
WAN com internet → Wi-Fi com internet → 4G
```

A implementação não considera uma associação Wi-Fi como conectividade suficiente. Ela detecta interfaces `mode=sta` no UCI, cruza-as com as interfaces configuradas no `mwan3` e só seleciona o Wi-Fi quando o `mwan3` reporta `online`, isto é, depois do teste de rastreamento configurado pelo firmware.

Também foi removida a dependência de uma tabela 4G fixa. A tabela de cada interface é derivada da ordem das seções `config interface` do `mwan3`, compatível com a forma como o mwan3 2.10 do OpenWrt 21.02 atribui seus IDs. Assim, adicionar o Wi-Fi antes ou depois do 4G não direciona o fwmark do Tailscale para uma tabela errada.

## 17. Versão 0.5.0 — inventário de dispositivos locais

O usuário perguntou se o OpenWrt consegue ver todos os dispositivos conectados, inclusive os que não receberam DHCP. A resposta técnica é que DHCP não é a única fonte: ARP/neighbor cache fornece IP e MAC de equipamentos estáticos que tenham falado com o roteador; a bridge e o Wi-Fi fornecem MACs de equipamentos vistos na camada 2.

Não existe uma forma passiva de saber o IP de um dispositivo com endereço estático que nunca transmite pacotes. Para não adicionar scanner, tráfego ou dependências ao ZLAN9809M, foi criado o menu **Serviços → Dispositivos locais**. A página combina leases DHCP, `/proc/net/arp`, `ip neigh`, FDB da bridge e estações Wi-Fi associadas. Ela informa a fonte de cada dado e mantém MACs vistos sem IP em uma linha própria do inventário.
