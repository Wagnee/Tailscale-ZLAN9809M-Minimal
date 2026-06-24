param(
    [string]$GoExe = $env:GO_EXE,
    [string]$UpxExe = $env:UPX_EXE
)

$ErrorActionPreference = "Stop"
$TailscaleVersion = "1.98.5"
$TailscaleTagObject = "8f8fe6a2e167459ed0f62616287b61b0b0a54eb5"
$TailscaleCommit = "295179bf294d3d076397bcef6815b1d6854e197d"
$Root = Split-Path $PSScriptRoot -Parent
$Work = Join-Path $Root "build\work"
$Source = Join-Path $Work "tailscale"
$Dist = Join-Path $Root "dist"
$Assets = Join-Path $Root "assets"
$Release = Join-Path $Root "release"
$KeepFeatures = (Get-Content -Raw (Join-Path $Root "build\KEEP_FEATURES")).Trim()

if (-not $GoExe) { $GoExe = (Get-Command go -ErrorAction SilentlyContinue).Source }
if (-not $UpxExe) { $UpxExe = (Get-Command upx -ErrorAction SilentlyContinue).Source }
if (-not $GoExe) { throw "Go 1.26.3 nao encontrado. Defina GO_EXE." }
if (-not $UpxExe) { throw "UPX 5.2.0 nao encontrado. Defina UPX_EXE." }

$resolvedRoot = [IO.Path]::GetFullPath($Root)
$resolvedWork = [IO.Path]::GetFullPath($Work)
if (-not $resolvedWork.StartsWith((Join-Path $resolvedRoot "build"), [StringComparison]::OrdinalIgnoreCase)) {
    throw "Caminho de build inseguro: $resolvedWork"
}
if (Test-Path $resolvedWork) { Remove-Item -LiteralPath $resolvedWork -Recurse -Force }
New-Item -ItemType Directory -Force $Work, $Dist, $Assets, $Release | Out-Null

& git clone --depth 1 --branch "v$TailscaleVersion" https://github.com/tailscale/tailscale.git $Source
if ($LASTEXITCODE -ne 0) { throw "git clone falhou" }
$commit = (& git -C $Source rev-parse HEAD).Trim()
if ($commit -ne $TailscaleCommit) { throw "Commit Tailscale inesperado: $commit" }
$tagObject = (& git -C $Source rev-parse "refs/tags/v$TailscaleVersion").Trim()
if ($tagObject -ne $TailscaleTagObject) { throw "Objeto da tag Tailscale inesperado: $tagObject" }

Push-Location $Source
try {
    $tags = (& $GoExe run ./cmd/featuretags -min -add $KeepFeatures).Trim()
    if ($LASTEXITCODE -ne 0) { throw "featuretags falhou" }
    Set-Content -Encoding ascii -Path (Join-Path $Dist "build-tags.txt") -Value $tags

    $old = @($env:GOOS, $env:GOARCH, $env:GOMIPS, $env:CGO_ENABLED)
    try {
        $env:GOOS = "linux"; $env:GOARCH = "mipsle"; $env:GOMIPS = "softfloat"; $env:CGO_ENABLED = "0"
        & $GoExe build -buildvcs=false -trimpath -tags $tags -ldflags "-s -w -buildid=" -o (Join-Path $Dist "tailscaled") ./cmd/tailscaled
        if ($LASTEXITCODE -ne 0) { throw "build tailscaled falhou" }
        & $GoExe build -buildvcs=false -trimpath -tags $tags -ldflags "-s -w -buildid=" -o (Join-Path $Dist "tailscale") ./cmd/tailscale
        if ($LASTEXITCODE -ne 0) { throw "build tailscale falhou" }
    }
    finally {
        $env:GOOS=$old[0]; $env:GOARCH=$old[1]; $env:GOMIPS=$old[2]; $env:CGO_ENABLED=$old[3]
    }
}
finally { Pop-Location }

$Daemon = Join-Path $Assets "tailscaled.min"
$Cli = Join-Path $Assets "tailscale.min"
Copy-Item -Force (Join-Path $Dist "tailscaled") $Daemon
Copy-Item -Force (Join-Path $Dist "tailscale") $Cli
& $UpxExe --best --lzma $Daemon
if ($LASTEXITCODE -ne 0) { throw "UPX tailscaled falhou" }
& $UpxExe --best --lzma $Cli
if ($LASTEXITCODE -ne 0) { throw "UPX tailscale falhou" }
& $UpxExe -t $Daemon $Cli
if ($LASTEXITCODE -ne 0) { throw "Teste UPX falhou" }

$daemonSize = (Get-Item $Daemon).Length
$cliSize = (Get-Item $Cli).Length
if ($daemonSize -gt 4000000 -or $cliSize -gt 3000000 -or ($daemonSize + $cliSize) -gt 6500000) {
    throw "Orcamento excedido: daemon=$daemonSize cli=$cliSize"
}
$daemonSha = (Get-FileHash -Algorithm SHA256 $Daemon).Hash.ToLowerInvariant()
$cliSha = (Get-FileHash -Algorithm SHA256 $Cli).Hash.ToLowerInvariant()
Set-Content -Encoding ascii -Path (Join-Path $Assets "SHA256SUMS") -Value "$daemonSha  tailscaled.min`n$cliSha  tailscale.min"

$Defaults = Join-Path $Root "rootfs\usr\share\zlan-ts-minimal\defaults\zlan_ts_minimal"
$config = Get-Content -Raw $Defaults
$config = [regex]::Replace($config, "option daemon_sha256 '[^']*'", "option daemon_sha256 '$daemonSha'")
$config = [regex]::Replace($config, "option cli_sha256 '[^']*'", "option cli_sha256 '$cliSha'")
[IO.File]::WriteAllText($Defaults, $config, [Text.UTF8Encoding]::new($false))

$Archive = Join-Path $Release "zlan-ts-minimal.tar.gz"
if (Test-Path $Archive) { Remove-Item -Force $Archive }
& tar.exe -czf $Archive -C (Join-Path $Root "rootfs") .
if ($LASTEXITCODE -ne 0) { throw "Empacotamento falhou" }
$archiveSha = (Get-FileHash -Algorithm SHA256 $Archive).Hash.ToLowerInvariant()
Set-Content -Encoding ascii -Path "$Archive.sha256" -Value "$archiveSha  zlan-ts-minimal.tar.gz"

Write-Host "tailscaled.min: $daemonSize bytes ($daemonSha)"
Write-Host "tailscale.min:  $cliSize bytes ($cliSha)"
Write-Host "payload:        $((Get-Item $Archive).Length) bytes ($archiveSha)"
