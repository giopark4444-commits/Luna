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

# ── 1. Compilar binario UNIVERSAL (arm64 + x86_64) ─────────────────
# Se usa swiftc + lipo para no requerir Xcode completo (basta con
# Command Line Tools). Así Luna corre en Apple Silicon e Intel.
echo "🌙  Compilando $APP_NAME (universal: arm64 + x86_64)..."
cd "$SCRIPT_DIR"
BUILD_TMP=$(mktemp -d)
swiftc -O -target arm64-apple-macos13  Sources/Luna/*.swift -o "$BUILD_TMP/$APP_NAME-arm64"
swiftc -O -target x86_64-apple-macos13 Sources/Luna/*.swift -o "$BUILD_TMP/$APP_NAME-x86_64"
lipo -create "$BUILD_TMP/$APP_NAME-arm64" "$BUILD_TMP/$APP_NAME-x86_64" -o "$BUILD_TMP/$APP_NAME"

# ── 2. Crear estructura .app ───────────────────────────────────────
echo "📦  Empaquetando $APP_NAME.app..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BUILD_TMP/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
rm -rf "$BUILD_TMP"
echo "  ✓  Binario universal: $(lipo -archs "$APP_BUNDLE/Contents/MacOS/$APP_NAME")"

# Ícono de la app
if [ -f "$SCRIPT_DIR/Luna.icns" ]; then
    cp "$SCRIPT_DIR/Luna.icns" "$APP_BUNDLE/Contents/Resources/Luna.icns"
    echo "  ✓  Ícono incluido"
fi

# ── 3. Info.plist ─────────────────────────────────────────────────
cat > "$APP_BUNDLE/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Luna</string>
    <key>CFBundleIconFile</key>
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

# ── 4. Firma ad-hoc (evita el warning de "dañada" en macOS) ───────
echo "✍️   Firmando app (ad-hoc)..."
codesign --force --deep --sign - "$APP_BUNDLE" 2>&1
echo "  ✓  Firmada"

# ── 5. Crear DMG ──────────────────────────────────────────────────
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
  1. Arrastra Luna.app a /Aplicaciones.
  2. La PRIMERA vez: clic derecho sobre Luna.app → "Abrir" → "Abrir".
     (macOS muestra un aviso porque la app no está notarizada por Apple;
     esto solo pasa la primera vez.)
     Alternativa por Terminal:
       xattr -dr com.apple.quarantine /Applications/Luna.app
  3. El ícono ☽ aparecerá en la barra de menú.

REQUISITOS
  • macOS 13 (Ventura) o superior
  • Cualquier Mac: Apple Silicon (M1/M2/M3/M4…) o Intel (binario universal)

CÓMO FUNCIONA
  El brillo se controla con una capa de atenuado por software, así que
  funciona con CUALQUIER monitor y conexión (HDMI, USB-C, integrada, etc.).
  Solo puede oscurecer respecto al brillo físico actual del panel.
  Night Shift usa la API CBBlueLightClient de macOS, sin permisos extra.
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
