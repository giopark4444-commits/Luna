import Cocoa

/// Night Shift propio de Luna mediante una capa cálida (overlay).
///
/// El Night Shift del sistema (CBBlueLightClient) no afecta a estos monitores
/// externos (igual que el LUT de gamma, que el LC49G95T ignora). Esta versión
/// superpone una capa ámbar translúcida por monitor: funciona en CUALQUIER
/// monitor, es instantánea y convive con el brillo y la calibración.
@MainActor
class NightShiftManager: ObservableObject {
    static let shared = NightShiftManager()

    @Published var isEnabled: Bool = false
    @Published var strength: Double = 0.5      // 0.0 – 1.0
    @Published var isAvailable: Bool = true     // siempre: es por software

    private let enabledKey = "luna.nightshift.enabled"
    private let strengthKey = "luna.nightshift.strength"

    private init() {
        isEnabled = UserDefaults.standard.bool(forKey: enabledKey)
        strength = UserDefaults.standard.object(forKey: strengthKey) as? Double ?? 0.5
        apply()
    }

    /// Compatibilidad con llamadas previas; ya no lee estado del sistema.
    func readStatus() {}

    func setEnabled(_ on: Bool) {
        isEnabled = on
        UserDefaults.standard.set(on, forKey: enabledKey)
        apply()
    }

    func setStrength(_ value: Double) {
        strength = max(0.0, min(1.0, value))
        UserDefaults.standard.set(strength, forKey: strengthKey)
        apply()
    }

    /// Aplica (o quita) la capa cálida en todos los monitores conectados.
    func apply() {
        let s = isEnabled ? strength : 0.0
        for screen in NSScreen.screens {
            guard let id = screen.cgDisplayID else { continue }
            OverlayDimmer.shared.setWarm(strength: s, for: id)
        }
    }
}
