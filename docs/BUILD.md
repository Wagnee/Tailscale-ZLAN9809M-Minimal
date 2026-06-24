# Build mínimo

O build usa o mecanismo oficial `cmd/featuretags` do Tailscale. A lista positiva está em `build/KEEP_FEATURES`; todas as demais features omissíveis recebem automaticamente `ts_omit_*`.

## Windows

Defina Go 1.26.3 e UPX 5.2.0:

```powershell
$env:GO_EXE = "C:\caminho\go.exe"
$env:UPX_EXE = "C:\caminho\upx.exe"
powershell -ExecutionPolicy Bypass -File .\build\build.ps1
```

## Linux

```sh
UPX_BIN=/caminho/upx ./build/build.sh
```

O processo clona exatamente a tag/commit fixados, produz daemon e CLI separados, comprime, testa os arquivos UPX, atualiza SHA-256 e gera o payload persistente. Também fixa no instalador o hash do payload e gera `install.sh.sha256`. O workflow repete o build completo em cada push.

O limite de 6,5 MB aplica-se à soma dos binários compactados. O payload persistente nunca contém os binários Tailscale.
