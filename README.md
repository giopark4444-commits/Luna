# 🌙 Luna

App nativa de macOS en la **barra de menú** para controlar el **brillo de monitores externos** y **Night Shift**, pensada para Apple Silicon.

Surgió de una necesidad concreta: controlar el brillo de varios monitores externos desde un solo sitio, sin botones físicos del monitor, con Night Shift integrado.

## ✨ Características

- Control de brillo de monitores externos desde la barra de menú.
- **DDC** (control por hardware) para monitores conectados por USB-C / Thunderbolt, vía [`m1ddc`](https://github.com/waydabber/m1ddc) — incluido dentro de la app.
- **Brillo por software** (gamma) como respaldo para monitores conectados por HDMI, donde DDC no está disponible.
- **Night Shift** integrado mediante la API privada `CBBlueLightClient` de CoreBrightness.
- App ligera tipo agente (`LSUIElement`): solo vive en la barra de menú.

## 📦 Instalación (usuarios)

Descarga el `.dmg` desde la pestaña [**Releases**](../../releases), ábrelo y arrastra `Luna.app` a `/Aplicaciones`.

Si macOS muestra un aviso de seguridad en el primer arranque:

```bash
xattr -dr com.apple.quarantine /Applications/Luna.app
```

### Requisitos

- macOS 13 (Ventura) o superior
- Mac con Apple Silicon (M1 / M2 / M3 / M4 …)
- DDC solo funciona en monitores por USB-C / Thunderbolt. Los monitores por HDMI usan brillo por software.

## 🛠️ Compilar desde el código

```bash
git clone https://github.com/giopark4444-commits/Luna.git
cd Luna
bash build.sh
```

`build.sh` compila en release, empaqueta `Luna.app` (bundleando `m1ddc` si está instalado vía Homebrew), la firma ad-hoc y genera el `.dmg`.

## 📁 Estructura

| Archivo | Responsabilidad |
|---|---|
| `Sources/Luna/main.swift` | Punto de entrada |
| `Sources/Luna/AppDelegate.swift` | Ciclo de vida de la app y barra de menú |
| `Sources/Luna/DisplayManager.swift` | Brillo (DDC vía `m1ddc` + gamma por software) |
| `Sources/Luna/NightShift.swift` | Night Shift (`CBBlueLightClient`) |
| `Sources/Luna/LunaView.swift` | Interfaz (SwiftUI) |

## 📄 Licencia

Uso personal. Sin garantía.
