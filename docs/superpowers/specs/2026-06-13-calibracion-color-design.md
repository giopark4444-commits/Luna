# Diseño: Calibración de color entre monitores (Luna)

Fecha: 2026-06-13
Estado: aprobado (diseño) — pendiente plan de implementación

## Objetivo

Permitir igualar **al ojo** los grises y colores de los monitores conectados, para
que se vean casi idénticos entre sí. Sin colorímetro: emparejamiento visual con
patrones de prueba y ajustes por monitor.

## Restricción fundamental

La calibración por software reforma la curva de color que la GPU envía a cada
monitor (LUT de gamma) o usa DDC para cambiar las ganancias del propio monitor.
En esta máquina:

- **C49RG9x** y **Wokyis**: aceptan gamma (y DDC). → calibración real.
- **LC49G95T** (5120×1440@120Hz, alto ancho de banda/DSC): **ignora gamma y falla
  por DDC** (comprobado en sesión 2026-06-13; misma razón por la que el brillo usa
  overlay). → solo aproximación por capa de color (overlay).

Decisión del usuario: enfoque **mixto** — calibrar de verdad los dos que responden
y aproximar el LC49G95T por overlay. Nivel de control: **completo** (R/G/B + Gamma
+ Negros + Brillo) en los que responden.

## Enfoque elegido

**Gamma LUT por canal + overlay de respaldo.**

- Color en monitores con gamma: `CGSetDisplayTransferByFormula(id, rMin,rMax,rGamma,
  gMin,gMax,gGamma, bMin,bMax,bGamma)`.
  - Ganancia Rojo/Verde/Azul → `rMax`/`gMax`/`bMax` (0.5–1.0, punto blanco).
  - Gamma → `rGamma=gGamma=bGamma` (≈0.5–2.0, def. 1.0).
  - Negros → `rMin=gMin=bMin` (0–0.2, def. 0; "lift").
- Color en monitores sin gamma (LC49G95T): overlay de color. Se exponen
  **Temperatura/Tinte + Brillo** (mapeados a color+alfa de la capa); R/G/B, Gamma y
  Negros quedan deshabilitados con nota "no soportado en este monitor".
- **Brillo**: sigue por overlay en los 3 (estado compartido con la UI principal;
  fluido y uniforme, como ya quedó). El LUT reforma color; el overlay oscurece encima.

Descartados: DDC puro (lento/intermitente, reañadir m1ddc, control tosco) y overlay
puro para todos (lava negros, sin gamma).

## Componentes

- **`Calibration.swift`** — modelo `DisplayCalibration` (rGain, gGain, bGain, gamma,
  black; Codable) + almacén en `UserDefaults` por nombre de monitor + función de
  aplicar: elige gamma-LUT u overlay-tinte según el monitor. Detección de método:
  por defecto gamma; el usuario puede marcar "este monitor usa capa de color" si no
  ve efecto (override manual persistido).
- **`CalibrationController.swift`** — gestiona las ventanas de patrón a pantalla
  completa (una por `NSScreen`) y el ciclo de vida del modo calibración.
- **`CalibrationView.swift`** — panel flotante: selector de monitor + "Referencia",
  selector de patrón, sliders, y botones Restablecer este / Restablecer todo / Listo.
- **`OverlayDimmer`** — se extiende para aceptar un color de tinte (hoy solo negro),
  combinando brillo (alfa) y desplazamiento de punto blanco.
- **Enganche** — botón "Calibrar monitores…" en `LunaView`; `AppDelegate` abre el modo.

## Patrones de prueba

Gris 50%, escalera de grises, blanco, negro, barras de color, y **degradado continuo
mapeado por coordenada X global** (los dos 49" forman una sola rampa sin costura si
están bien igualados). Una ventana por monitor, a pantalla completa, click-through
salvo el panel.

## Flujo

1. Usuario abre "Calibrar monitores…" → entra a modo calibración (patrones + panel).
2. Elige un monitor de referencia y ajusta los demás hasta que coincidan al ojo.
3. Cambia de patrón según lo que afine (grises, blancos, color).
4. "Listo"/Esc sale del modo; la calibración queda aplicada.

## Persistencia

Calibración por monitor (clave por nombre) en `UserDefaults`, reaplicada al iniciar
Luna (en `DisplayManager.refresh()`, junto al brillo). Se distribuye con la app:
cualquiera puede calibrar su propio set. "Restablecer" limpia la del monitor.

## Límites (honestos)

- Sin colorímetro = igualar **al ojo** (objetivo declarado), no exactitud medida.
- El LC49G95T queda **parecido, no idéntico** (no acepta calibración real; overlay
  aproxima punto blanco/brillo pero no gamma ni ganancia por canal, y levanta algo
  los negros).
- No corrige gamut físico (un panel no puede mostrar colores fuera de su rango).

## Fuera de alcance (YAGNI)

Soporte de colorímetro/hardware, perfiles ICC, importación de perfiles externos,
calibración automática.
