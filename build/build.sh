#!/bin/sh

set -eu

TAILSCALE_VERSION="1.98.5"
TAILSCALE_TAG_OBJECT="8f8fe6a2e167459ed0f62616287b61b0b0a54eb5"
TAILSCALE_COMMIT="295179bf294d3d076397bcef6815b1d6854e197d"
SCRIPT_DIR="$(dirname -- "$0")"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WORK="$ROOT/build/work"
SOURCE="$WORK/tailscale"
DIST="$ROOT/dist"
UPX_BIN="${UPX_BIN:-upx}"
KEEP_FEATURES="$(tr -d '\r\n' < "$ROOT/build/KEEP_FEATURES")"

for command in git go "$UPX_BIN" sha256sum tar sed; do
    command -v "$command" >/dev/null 2>&1 || { echo "Missing command: $command" >&2; exit 1; }
done

case "$WORK" in "$ROOT"/build/work) ;; *) echo "Unsafe work path" >&2; exit 1 ;; esac
rm -rf "$WORK"
mkdir -p "$WORK" "$DIST" "$ROOT/assets" "$ROOT/release"

git clone --depth 1 --branch "v$TAILSCALE_VERSION" https://github.com/tailscale/tailscale.git "$SOURCE"
[ "$(git -C "$SOURCE" rev-parse HEAD)" = "$TAILSCALE_COMMIT" ] || { echo "Unexpected Tailscale commit" >&2; exit 1; }
[ "$(git -C "$SOURCE" rev-parse "refs/tags/v$TAILSCALE_VERSION")" = "$TAILSCALE_TAG_OBJECT" ] || { echo "Unexpected Tailscale tag object" >&2; exit 1; }

TAGS="$(cd "$SOURCE" && go run ./cmd/featuretags -min -add "$KEEP_FEATURES")"
printf '%s\n' "$TAGS" > "$DIST/build-tags.txt"

(cd "$SOURCE" && CGO_ENABLED=0 GOOS=linux GOARCH=mipsle GOMIPS=softfloat \
    go build -buildvcs=false -trimpath -tags "$TAGS" -ldflags '-s -w -buildid=' \
    -o "$DIST/tailscaled" ./cmd/tailscaled)
(cd "$SOURCE" && CGO_ENABLED=0 GOOS=linux GOARCH=mipsle GOMIPS=softfloat \
    go build -buildvcs=false -trimpath -tags "$TAGS" -ldflags '-s -w -buildid=' \
    -o "$DIST/tailscale" ./cmd/tailscale)

cp "$DIST/tailscaled" "$ROOT/assets/tailscaled.min"
cp "$DIST/tailscale" "$ROOT/assets/tailscale.min"
"$UPX_BIN" --best --lzma "$ROOT/assets/tailscaled.min"
"$UPX_BIN" --best --lzma "$ROOT/assets/tailscale.min"
"$UPX_BIN" -t "$ROOT/assets/tailscaled.min" "$ROOT/assets/tailscale.min"

DAEMON_SIZE="$(wc -c < "$ROOT/assets/tailscaled.min")"
CLI_SIZE="$(wc -c < "$ROOT/assets/tailscale.min")"
[ "$DAEMON_SIZE" -le 4000000 ] || { echo "tailscaled.min too large: $DAEMON_SIZE" >&2; exit 1; }
[ "$CLI_SIZE" -le 3000000 ] || { echo "tailscale.min too large: $CLI_SIZE" >&2; exit 1; }
[ "$((DAEMON_SIZE + CLI_SIZE))" -le 6500000 ] || { echo "Runtime too large" >&2; exit 1; }

DAEMON_SHA="$(sha256sum "$ROOT/assets/tailscaled.min" | sed 's/[[:space:]].*//')"
CLI_SHA="$(sha256sum "$ROOT/assets/tailscale.min" | sed 's/[[:space:]].*//')"
printf '%s  tailscaled.min\n%s  tailscale.min\n' "$DAEMON_SHA" "$CLI_SHA" > "$ROOT/assets/SHA256SUMS"

DEFAULTS="$ROOT/rootfs/usr/share/zlan-ts-minimal/defaults/zlan_ts_minimal"
sed -i "s/option daemon_sha256 '[^']*'/option daemon_sha256 '$DAEMON_SHA'/" "$DEFAULTS"
sed -i "s/option cli_sha256 '[^']*'/option cli_sha256 '$CLI_SHA'/" "$DEFAULTS"

ARCHIVE="$ROOT/release/zlan-ts-minimal.tar.gz"
rm -f "$ARCHIVE" "$ARCHIVE.sha256"
tar -czf "$ARCHIVE" -C "$ROOT/rootfs" .
ARCHIVE_SHA="$(sha256sum "$ARCHIVE" | sed 's/[[:space:]].*//')"
printf '%s  zlan-ts-minimal.tar.gz\n' "$ARCHIVE_SHA" > "$ARCHIVE.sha256"

echo "tailscaled.min: $DAEMON_SIZE bytes ($DAEMON_SHA)"
echo "tailscale.min:  $CLI_SIZE bytes ($CLI_SHA)"
echo "payload:        $(wc -c < "$ARCHIVE") bytes ($ARCHIVE_SHA)"
