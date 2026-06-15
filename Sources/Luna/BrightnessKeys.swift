import Cocoa
import ApplicationServices

extension Notification.Name {
    static let lunaBrightnessKey = Notification.Name("luna.brightnessKey")
}

// El tap se guarda fuera del actor para poder reactivarlo desde el callback C.
private var brightnessTap: CFMachPort?

private func brightnessTapCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    // Si el sistema desactiva el tap (timeout), reactivarlo.
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let t = brightnessTap { CGEvent.tapEnable(tap: t, enable: true) }
        return Unmanaged.passUnretained(event)
    }
    // Solo eventos "system defined" (tipo 14) con subtipo de teclas multimedia (8).
    guard type.rawValue == 14, let ns = NSEvent(cgEvent: event), ns.subtype.rawValue == 8 else {
        return Unmanaged.passUnretained(event)
    }
    let keyCode = (ns.data1 & 0xFFFF0000) >> 16
    let keyDown = ((ns.data1 & 0x0000FF00) >> 8) == 0x0A
    // NX_KEYTYPE_BRIGHTNESS_UP = 3, _DOWN = 4
    if keyCode == 3 || keyCode == 4 {
        if keyDown {
            NotificationCenter.default.post(name: .lunaBrightnessKey, object: nil,
                                            userInfo: ["up": keyCode == 3])
        }
        return nil   // consumir (macOS no controla estos externos de todos modos)
    }
    return Unmanaged.passUnretained(event)
}

/// Hace que las teclas de brillo (F1/F2) controlen el brillo de Luna.
/// Requiere permiso de Accesibilidad (para leer esas teclas del sistema).
@MainActor
final class BrightnessKeys: ObservableObject {
    static let shared = BrightnessKeys()

    @Published private(set) var isEnabled: Bool = false
    private let key = "luna.brightnessKeys"

    private init() { isEnabled = UserDefaults.standard.bool(forKey: key) }

    var hasPermission: Bool { AXIsProcessTrusted() }

    /// Llamar al arrancar: si estaba activado y hay permiso, enciende el tap.
    func startIfEnabled() { if isEnabled { _ = startTap() } }

    func setEnabled(_ on: Bool) {
        isEnabled = on
        UserDefaults.standard.set(on, forKey: key)
        if on {
            if !startTap() { promptPermission() }
        } else {
            stopTap()
        }
    }

    // MARK: - Tap

    @discardableResult
    private func startTap() -> Bool {
        if brightnessTap != nil { return true }
        guard AXIsProcessTrusted() else { return false }
        let mask = CGEventMask(1 << 14)   // NSEventType.systemDefined
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: brightnessTapCallback, userInfo: nil
        ) else { return false }
        brightnessTap = tap
        if let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) {
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func stopTap() {
        if let tap = brightnessTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
            brightnessTap = nil
        }
    }

    private func promptPermission() {
        let alert = NSAlert()
        alert.messageText = "Permiso de Accesibilidad"
        alert.informativeText = "Para que las teclas de brillo (F1/F2) controlen Luna, activa Luna en Ajustes del Sistema → Privacidad y seguridad → Accesibilidad, y vuelve a abrir Luna."
        alert.addButton(withTitle: "Abrir Ajustes")
        alert.addButton(withTitle: "Más tarde")
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        // Dispara también el aviso del sistema para añadir Luna a la lista.
        let opts = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }
}
