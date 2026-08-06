#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
ENGINE_DIR="$ROOT_DIR/engine"
RELEASE_DIR="$ENGINE_DIR/release"
PACKAGE_DIR="$RELEASE_DIR/web"
TMP_DIR="$ROOT_DIR/tmp/web-package"
NZP_GAME_PK3_URL="https://raw.githubusercontent.com/nzp-team/nzp-team.github.io/main/nzp/game.pk3"
NZP_QC_ZIP_URL="https://github.com/nzp-team/quakec/releases/download/bleeding-edge/fte-nzp-qc.zip"
NZP_QC_REPO_URL="https://github.com/nzp-team/quakec.git"
NZP_QC_BRANCH="main"
MENU_PATCH_DIR="$ENGINE_DIR/web/nzp-menu-patch"

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

# IMPORTANT: fte-nzp-qc.zip already contains the correct, fully-themed NZ:P menu.dat
# (the actual "MAIN MENU / SOLO / COOPERATIVE / CONFIGURATION / CHARACTER BIOS / CREDITS"
# screen), plus the matching csprogs.dat/qwprogs.dat (client/server game logic). Those
# two we always take verbatim from the official release -- we have no local source for
# them and no business touching them.
#
# menu.dat is different: we carry a small, intentional patch on top of NZ:P's own
# source/menu/menu_main.qc (vendored at engine/web/nzp-menu-patch/menu_main.qc) that adds
# a real "JOIN SILLY SERVER" button to the actual in-game MAIN MENU, using NZ:P's own
# Menu_Coop_Connect pattern (Menu_PlaySound -> m_toggle(false) -> localcmd("connect ...")).
# So: clone the real nzp-team/quakec source, drop our patched menu_main.qc in, and
# recompile ONLY the menu target with their own bundled fteqcc. If anything about that
# goes wrong (no network, upstream menu source changed shape, etc.) we fall back to the
# official prebuilt menu.dat from the zip so the build never breaks over this.
NZP_QC_SRC_DIR="$TMP_DIR/quakec-src"
CUSTOM_MENU_OK=0

if git clone --depth 1 --branch "$NZP_QC_BRANCH" "$NZP_QC_REPO_URL" "$NZP_QC_SRC_DIR" >/dev/null 2>&1; then
	cp "$MENU_PATCH_DIR/menu_main.qc" "$NZP_QC_SRC_DIR/source/menu/menu_main.qc"

	FTEQCC_BIN="fteqcc-cli-lin"
	case "$(uname -s)" in
		Darwin) FTEQCC_BIN="fteqcc-cli-mac" ;;
	esac
	chmod +x "$NZP_QC_SRC_DIR/bin/$FTEQCC_BIN" 2>/dev/null || true

	if (
		cd "$NZP_QC_SRC_DIR" \
		&& mkdir -p build/fte \
		&& "bin/$FTEQCC_BIN" -O3 -DFTE -Wall -srcfile progs/menu.src
	) >"$TMP_DIR/menu-compile.log" 2>&1; then
		if [ -f "$NZP_QC_SRC_DIR/build/fte/menu.dat" ] \
			&& ! grep -qE "error" "$TMP_DIR/menu-compile.log"; then
			cp "$NZP_QC_SRC_DIR/build/fte/menu.dat" "$TMP_DIR/qc/menu.dat"
			CUSTOM_MENU_OK=1
		fi
	fi
fi

if [ "$CUSTOM_MENU_OK" -eq 1 ]; then
	echo "web-package: using custom menu.dat (with JOIN SILLY SERVER button)"
else
	echo "web-package: WARNING - could not build custom menu.dat, falling back to official menu.dat (no Join Silly Server button in this build)" >&2
fi

(
	cd "$TMP_DIR/qc"
	zip -q -r "$PACKAGE_DIR/nzp/progs.pk3" csprogs.dat qwprogs.dat menu.dat csprogs.lno
)

rm -rf "$TMP_DIR"
