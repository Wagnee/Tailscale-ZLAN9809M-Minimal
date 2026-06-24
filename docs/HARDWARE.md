# Auditoria do ZLAN9809M

## Plataforma

- máquina: `ZLAN zlan-cat1 (16M flash)`;
- SoC: MediaTek MT7628AN;
- CPU: MIPS 24KEc, 580 MHz, um núcleo;
- firmware: OpenWrt 21.02.0 r16279;
- arquitetura: `mipsel_24kc` com soft-float;
- kernel: 5.4.143, ABI customizado `fe24b4bf9114ead2296e0f8cacdd593a`;
- RAM reportada: 123.060 KB;
- swap: inexistente;
- TUN: integrado e disponível em `/dev/net/tun`.
- WAN: IPv4 funcional; o firmware pode resolver endereços IPv6 mesmo sem rota IPv6 utilizável.
- TLS: a cadeia de certificados embarcada pode rejeitar o certificado atual do GitHub; os downloads usam hashes fixos para manter a verificação de integridade.

## Armazenamento

| Área | Tamanho | Característica |
|---|---:|---|
| `/rom` | 7.936 KB | squashfs somente leitura, totalmente ocupado |
| `/overlay` | 6.080 KB | JFFS2 gravável; 5.280 KB livres na auditoria inicial |
| `/tmp` | 61.528 KB | RAM; 53.008 KB livres na auditoria inicial |

O firmware e os pacotes de fábrica vivem no squashfs. Uma remoção via overlay não reescreve a imagem de firmware e não recupera os 7.936 KB do `/rom`.

## Memória e módulos

Na auditoria inicial havia cerca de 51 MB em `MemAvailable`. O kernel carregava TUN, WireGuard e componentes L2TP. Tailscale usa TUN em userspace e não depende do módulo WireGuard do kernel.

O runtime mínimo reduz simultaneamente:

- código mapeado pelo daemon: de aproximadamente 38,8 MB para 14,2 MB;
- código mapeado pelo cliente durante `tailscale up`: de aproximadamente 38,8 MB para 10,1 MB;
- arquivos em tmpfs: de 7,78 MB para aproximadamente 5,70 MB.

`GOMEMLIMIT` é um limite suave do heap Go, não um limite total de RSS. O kernel ainda pode encerrar o processo em pressão extrema; por isso o loader registra linhas do OOM killer após uma queda.

## ABI

Não instale `kmod-tun` dos feeds oficiais. O módulo existente corresponde ao kernel do fabricante; o feed OpenWrt público possui outro hash de ABI. O projeto não altera feeds nem executa `opkg update`.
