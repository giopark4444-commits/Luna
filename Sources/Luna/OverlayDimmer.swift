import Cocoa

/// Atenuado por software mediante una ventana negra translúcida superpuesta.
///
/// Es el método más robusto: funciona en cualquier monitor sin importar si
/// responde a DDC o si su modo de vídeo (HDR, alta frecuencia con DSC, etc.)
/// hace que macOS ignore el LUT de gamma. Mantiene una ventana por monitor y
/// ajusta su opacidad: brillo 1.0 → sin capa, brillo bajo → capa más oscura.
///
/// Limitación inherente: solo puede *oscurecer* respecto al brillo físico del
/// panel; no puede subir más allá de lo que el monitor ya emite.
@MainActor
final class OverlayDimmer {
    static let shared = OverlayDimmer()

    private var windows: [CGDirectDisplayID: NSWindow] = [:]       // brillo (capa negra)
    private var tintWindows: [CGDirectDisplayID: NSWindow] = [:]   // tinte de color (calibración)
    private var warmWindows: [CGDirectDisplayID: NSWindow] = [:]   // Night Shift (capa cálida)

    /// Nunca dejamos la pantalla totalmente negra: tope de opacidad de la capa.
    private let maxDim = 0.92

    /// Color cálido del Night Shift (ámbar) y opacidad máxima a intensidad 1.0.
    private let warmColor = (r: 1.0, g: 0.42, b: 0.0)
    private let maxWarm = 0.55

    /// `brightness` en 0.05–1.0 (1.0 = sin atenuar).
    func setBrightness(_ brightness: Double, for cgID: CGDirectDisplayID) {
        let dim = max(0.0, min(maxDim, 1.0 - brightness))

        // Sin atenuar: no hace falta ventana (oculta la existente si la hay).
        if dim <= 0.001 {
            windows[cgID]?.orderOut(nil)
            return
        }

        guard let screen = Self.screen(for: cgID) else { return }
        let window = windows[cgID] ?? makeWindow()
        windows[cgID] = window
        // Reajustar al marco actual del monitor (por si cambió de resolución).
        window.setFrame(screen.frame, display: true)
        window.alphaValue = CGFloat(dim)
        window.orderFrontRegardless()
    }

    /// Capa de color para aproximar el punto blanco (método overlay de calibración).
    func setTint(r: Double, g: Double, b: Double, alpha: Double, for cgID: CGDirectDisplayID) {
        if alpha <= 0.001 {
            tintWindows[cgID]?.orderOut(nil)
            return
        }
        guard let screen = Self.screen(for: cgID) else { return }
        let window = tintWindows[cgID] ?? makeWindow()
        tintWindows[cgID] = window
        window.backgroundColor = NSColor(srgbRed: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: 1)
        window.setFrame(screen.frame, display: true)
        window.alphaValue = CGFloat(min(maxDim, alpha))
        window.orderFrontRegardless()
    }

    func clearTint(for cgID: CGDirectDisplayID) {
        tintWindows[cgID]?.orderOut(nil)
    }

    /// Capa cálida del Night Shift (overlay). `strength` 0–1 (0 = sin efecto).
    /// Funciona en cualquier monitor, a diferencia del Night Shift del sistema.
    func setWarm(strength: Double, for cgID: CGDirectDisplayID) {
        let alpha = max(0.0, min(maxWarm, strength * maxWarm))
        if alpha <= 0.001 {
            warmWindows[cgID]?.orderOut(nil)
            return
        }
        guard let screen = Self.screen(for: cgID) else { return }
        let window = warmWindows[cgID] ?? makeWindow()
        warmWindows[cgID] = window
        window.backgroundColor = NSColor(srgbRed: warmColor.r, green: warmColor.g, blue: warmColor.b, alpha: 1)
        window.setFrame(screen.frame, display: true)
        window.alphaValue = CGFloat(alpha)
        window.orderFrontRegardless()
    }

    /// Quita todas las capas (al salir de la app).
    func removeAll() {
        for window in windows.values { window.orderOut(nil) }
        for window in tintWindows.values { window.orderOut(nil) }
        for window in warmWindows.values { window.orderOut(nil) }
        windows.removeAll()
        tintWindows.removeAll()
        warmWindows.removeAll()
    }

    // MARK: - Private

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: .zero,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .black
        window.hasShadow = false
        window.ignoresMouseEvents = true              // clics pasan a través
        window.alphaValue = 0
        // .screenSaver compone de forma fiable en todos los monitores (incluido el
        // LC49G95T a 120Hz, donde CGShieldingWindowLevel no se mostraba). Cubre
        // contenido y pantalla completa; el cursor sigue visible por encima.
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        return window
    }

    private static func screen(for cgID: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { screen in
            (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == cgID
        }
    }
}
