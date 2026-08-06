#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
ENGINE_DIR="$ROOT_DIR/engine"
RELEASE_DIR="$ENGINE_DIR/release"
PACKAGE_DIR="$RELEASE_DIR/web"
TMP_DIR="$ROOT_DIR/tmp/web-package"
NZP_GAME_PK3_URL="https://raw.githubusercontent.com/nzp-team/nzp-team.github.io/main/nzp/game.pk3"
NZP_QC_ZIP_URL="https://github.com/nzp-team/quakec/releases/download/bleeding-edge/fte-nzp-qc.zip"

mkdir -p "$ROOT_DIR/tmp"
rm -rf "$TMP_DIR" "$PACKAGE_DIR"
mkdir -p "$TMP_DIR" "$PACKAGE_DIR/nzp"

"$ROOT_DIR/tools/build-nzp-web.sh"

cp "$RELEASE_DIR/ftewebgl.js" "$PACKAGE_DIR/ftewebgl.js"
cp "$RELEASE_DIR/ftewebgl.wasm" "$PACKAGE_DIR/ftewebgl.wasm"
cp "$ENGINE_DIR/web/nzp-index.html" "$PACKAGE_DIR/index.html"
cp "$ENGINE_DIR/web/nzp-default.fmf" "$PACKAGE_DIR/default.fmf"
cp "$ENGINE_DIR/client/nzportable.ico" "$PACKAGE_DIR/nzportable.ico"

# The engine build always emits a generic, unbranded ftewebgl.html (fteshell.html)
# with no NZ:P game/progs files preloaded, so it boots into the plain vanilla Quake
# menu instead of NZ:P. Anyone hitting that URL out of habit sees the "old UI".
# Replace it with a redirect to the real NZ:P-themed index.html so that trap can't happen.
cat > "$PACKAGE_DIR/ftewebgl.html" <<'EOF'
<!doctype html>
<html lang="en-us"><head><meta charset="utf-8">
<meta http-equiv="refresh" content="0; url=index.html">
<title>NZ: Portable</title>
</head><body>
<p>Redirecting to <a href="index.html">index.html</a>&hellip;</p>
</body></html>
EOF

for gz_file in ftewebgl.js.gz ftewebgl.wasm.gz; do
	if [ -f "$RELEASE_DIR/$gz_file" ]; then
		cp "$RELEASE_DIR/$gz_file" "$PACKAGE_DIR/$gz_file"
	fi
done

wget -q "$NZP_GAME_PK3_URL" -O "$PACKAGE_DIR/nzp/game.pk3"
wget -q "$NZP_QC_ZIP_URL" -O "$TMP_DIR/fte-nzp-qc.zip"
unzip -q "$TMP_DIR/fte-nzp-qc.zip" -d "$TMP_DIR/qc"

if command -v fteqcc >/dev/null 2>&1; then
	FTEQCC_BIN="$(command -v fteqcc)"
elif [ -x "$RELEASE_DIR/fteqcc" ]; then
	FTEQCC_BIN="$RELEASE_DIR/fteqcc"
else
	(
		cd "$ENGINE_DIR"
		make qcc-rel -j"$(getconf _NPROCESSORS_ONLN)"
	)
	FTEQCC_BIN="$RELEASE_DIR/fteqcc"
fi

(
	cd "$ROOT_DIR/quakec/menusys"
	"$FTEQCC_BIN" -srcfile menu.src >/dev/null
)
cp "$ROOT_DIR/quakec/menu.dat" "$TMP_DIR/qc/menu.dat"
rm -f "$ROOT_DIR/quakec/menu.dat"

(
	cd "$TMP_DIR/qc"
	zip -q -r "$PACKAGE_DIR/nzp/progs.pk3" csprogs.dat qwprogs.dat menu.dat csprogs.lno
)

rm -rf "$TMP_DIR"
