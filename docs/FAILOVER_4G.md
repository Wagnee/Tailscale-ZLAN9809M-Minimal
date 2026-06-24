# Failover automático WAN/4G

## Causa confirmada no ZLAN9809M

Com o cabo WAN desconectado, o `mwan3` marcava o 4G (`wan_4g`) como online e o tráfego comum saía corretamente pela tabela 2/`usb0`. O Tailscale, porém, usa seu próprio fwmark e cria regras antes das regras de política do `mwan3`:

```text
1310: from all fwmark 0x80000/0xff0000 lookup main
1330: from all fwmark 0x80000/0xff0000 lookup default
1350: from all fwmark 0x80000/0xff0000 unreachable
2002: from all fwmark 0x200/0x3f00 lookup 2
```

A tabela `main` ainda mantinha a WAN Ethernet desconectada com métrica 1 e o 4G com métrica 2. Por isso os pacotes marcados pelo Tailscale encontravam a regra 1310 primeiro e tentavam usar a WAN sem conectividade. O `mwan3` nunca tinha a oportunidade de redirecioná-los para a tabela 2.

## Correção implementada

O serviço `/usr/bin/zlan-ts-mwan3` observa o estado real do `mwan3`:

- WAN online: remove o override e deixa o Tailscale usar a rota principal;
- WAN offline e `wan_4g` online, com default route na tabela 2: instala a regra abaixo;
- nenhuma saída disponível: remove o override;
- prioridade 1305 ocupada por outra regra: não altera nada e registra um aviso.

```sh
ip -4 rule add pref 1305 fwmark 0x80000/0xff0000 lookup 2
ip route flush cache
```

A prioridade 1305 é anterior à regra 1310 do Tailscale. O seletor usa somente o fwmark interno do Tailscale e não muda a rota do tráfego comum do roteador.

A sincronização ocorre:

- antes e depois da inicialização do `tailscaled`;
- a cada 15 segundos enquanto o daemon está ativo;
- em eventos de interface do hotplug do OpenWrt.

## Configuração

Os valores padrão correspondem ao firmware analisado:

```text
option mwan3_failover '1'
option mwan3_rule_pref '1305'
option mwan3_4g_table '2'
option mwan3_wan_interface 'wan'
option mwan3_4g_interface 'wan_4g'
option mwan3_check_interval '15'
```

Estado atual:

```sh
/usr/bin/zlan-ts-mwan3 status
/etc/init.d/zlan-ts-minimal status
```

Desativação e remoção imediata da regra gerenciada:

```sh
uci set zlan_ts_minimal.main.mwan3_failover='0'
uci commit zlan_ts_minimal
/usr/bin/zlan-ts-mwan3 sync
```

## Persistência e factory reset

Reboot e queda de energia preservam o projeto porque scripts, configuração e identidade ficam no JFFS2 de `/overlay`. Os binários em `/tmp` são baixados e validados novamente quando a internet retorna.

O botão de factory reset do OpenWrt apaga o `/overlay` e restaura o conteúdo somente leitura de `/rom`. Portanto uma instalação comum não pode sobreviver a esse reset. Para isso seria necessário:

1. gerar e gravar uma imagem de firmware customizada com o bootstrap em `/rom`; ou
2. usar um mecanismo de provisionamento persistente oficialmente documentado pelo fabricante.

Não se deve gravar diretamente nas partições MTD `factory` ou `config` sem documentação e procedimento de recuperação do fabricante. Elas podem conter calibração, parâmetros do modem ou dados necessários ao boot. A identidade Tailscale também não deve ser colocada em firmware público; o provisionamento precisa usar uma credencial segura por dispositivo.
