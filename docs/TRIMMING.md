# Remoção e desativação de componentes

## O que realmente libera flash

Somente arquivos presentes em `/overlay/upper` consomem a partição JFFS2. O instalador remove do overlay:

- daemon de telemetria e ferramentas do projeto híbrido;
- páginas LuCI adicionadas pelos projetos anteriores;
- loaders e binários Tailscale persistentes antigos;
- configurações Modbus/MQTT que não fazem parte deste projeto.

A identidade `/etc/tailscale/tailscaled.state` é preservada.

## O que não libera flash

OpenVPN, WireGuard, L2TP, traduções chinesas, diagnóstico e menus LuCI podem estar no `/rom`. Removê-los com `opkg remove` gera whiteouts no overlay, sem diminuir o squashfs. A customização correta desses itens exigiria recompilar e gravar uma nova imagem completa do firmware do fabricante, operação com risco de brick e fora do escopo deste instalador.

## Economia de RAM

Depois de confirmar que o Tailscale e a subnet funcionam, `tools/disable-other-vpns.sh --apply` pode parar daemons VPN conhecidos e tentar descarregar módulos não utilizados. O script não toca em PPP/celular, TUN, network, firewall ou mwan3.

Não execute essa etapa antes de confirmar uma rota alternativa de administração do equipamento.
