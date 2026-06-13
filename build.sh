#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────
#  Luna — Build script
#  Genera Luna.app (auto-contenida con m1ddc) + Luna-1.0.dmg
# ──────────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Luna"
VERSION="1.0"
APP_BUNDLE="$SCRIPT_DIR/$APP_NAME.app"
DMG_PATH="$SCRIPT_DIR/$APP_NAME-$VERSION.dmg"

# ── 1. Compilar ────────────────────────────────────────────────────
echo "🌙  Compilando $APP_NAME..."
cd "$SCRIPT_DIR"
swift build -c release 2>&1

# ── 2. Crear estructura .app ───────────────────────────────────────
echo "📦  Empaquetando $APP_NAME.app..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp ".build/release/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# ── 3. Bundlear m1ddc dentro de la app ────────────────────────────
M1DDC_SRC=""
for candidate in \
    "/opt/homebrew/bin/m1ddc" \
    "/usr/local/bin/m1ddc" \
    "$(which m1ddc 2>/dev/null || true)"; do
    if [ -x "$candidate" ]; then
        M1DDC_SRC="$candidate"
        break
    fi
done

if [ -n "$M1DDC_SRC" ]; then
    cp "$M1DDC_SRC" "$APP_BUNDLE/Contents/Resources/m1ddc"
    chmod +x "$APP_BUNDLE/Contents/Resources/m1ddc"
    echo "  ✓  m1ddc bundleado desde $M1DDC_SRC"
else
    echo "  ⚠  m1ddc no encontrado — los monitores DDC no funcionarán sin él"
fi

# ── 4. Info.plist ─────────────────────────────────────────────────
cat > "$APP_BUNDLE/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Luna</string>
    <key>CFBundleIdentifier</key>
    <string>com.luna.menubar</string>
    <key>CFBundleName</key>
    <string>Luna</string>
    <key>CFBundleDisplayName</key>
    <string>Luna</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF

# ── 5. Firma ad-hoc (evita el warning de "dañada" en macOS) ───────
echo "✍️   Firmando app (ad-hoc)..."
codesign --force --deep --sign - "$APP_BUNDLE" 2>&1
echo "  ✓  Firmada"

# ── 6. Crear DMG ──────────────────────────────────────────────────
echo "💿  Creando $APP_NAME-$VERSION.dmg..."
rm -f "$DMG_PATH"

# Directorio temporal con solo lo que va en el DMG
TMP_DIR=$(mktemp -d)
cp -r "$APP_BUNDLE" "$TMP_DIR/"

# README dentro del DMG
cat > "$TMP_DIR/Léeme.txt" << 'READMEEOF'
Luna — Control de brillo de monitores
======================================

INSTALAR
  1. Arrastra Luna.app a /Aplicaciones (o a donde prefieras).
  2. Abre Luna desde Launchpad o /Aplicaciones.
  3. En el primer arranque macOS puede mostrar un aviso de seguridad.
     Si ocurre, abre una Terminal y ejecuta:

       xattr -dr com.apple.quarantine /Applications/Luna.app

  4. El ícono ☽ aparecerá en la barra de menú.

REQUISITOS
  • macOS 13 (Ventura) o superior
  • Mac con chip Apple Silicon (M1 / M2 / M3 / M4 …)
  • m1ddc está incluido dentro de la app (no hace falta instalarlo).
    Solo funciona con monitores conectados por USB-C / Thunderbolt.
    Los monitores por HDMI usan control de brillo por software.

NOTA: Night Shift usa la API privada CBBlueLightClient de macOS.
      Funciona sin permisos adicionales.
READMEEOF

hdiutil create \
    -volname "$APP_NAME $VERSION" \
    -srcfolder "$TMP_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH" 2>&1

rm -rf "$TMP_DIR"

echo ""
echo "✅  Listo!"
echo ""
echo "   App:  $APP_BUNDLE"
echo "   DMG:  $DMG_PATH"
echo ""
echo "Guarda el DMG en un lugar seguro (iCloud, USB, etc.)"
echo "Para instalar en otro Mac: abre el DMG y arrastra Luna.app a /Aplicaciones"
