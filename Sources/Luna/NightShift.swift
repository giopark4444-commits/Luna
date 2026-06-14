import Cocoa

/// Night Shift propio de Luna.
///
/// El Night Shift del sistema (CBBlueLightClient) no afecta a estos monitores
/// externos. Aquí el calentado lo aplica `DisplayManager`:
/// - Monitores con gamma: multiplicando las ganancias de color (look natural,
///   negros intactos, como Apple).
/// - Monitores que ignoran gamma (LC49G95T): con una capa ámbar (aproximado).
@MainActor
class NightShiftManager: ObservableObject {
    static let shared = NightShiftManager()

    @Published var isEnabled: Bool = false
    @Published var strength: Double = 0.5      // 0.0 – 1.0
    @Published var isAvailable: Bool = true     // siempre: es por software

    /// Aviso cuando cambia (DisplayManager reaplica el color).
    var onChange: (() -> Void)?

    private let enabledKey = "luna.nightshift.enabled"
    private let strengthKey = "luna.nightshift.strength"

    private init() {
        isEnabled = UserDefaults.standard.bool(forKey: enabledKey)
        strength = UserDefaults.standard.object(forKey: strengthKey) as? Double ?? 0.5
    }

    func readStatus() {}   // compatibilidad; ya no hay estado del sistema

    func setEnabled(_ on: Bool) {
        isEnabled = on
        UserDefaults.standard.set(on, forKey: enabledKey)
        onChange?()
    }

    func setStrength(_ value: Double) {
        strength = max(0.0, min(1.0, value))
        UserDefaults.standard.set(strength, forKey: strengthKey)
        onChange?()
    }

    /// Ganancias multiplicativas para monitores con gamma (1.0 = sin cambio).
    /// Baja sobre todo el azul y un poco el verde → blanco cálido, negros intactos.
    func warmGains() -> (r: Double, g: Double, b: Double) {
        guard isEnabled else { return (1, 1, 1) }
        return (1.0, 1.0 - 0.10 * strength, 1.0 - 0.45 * strength)
    }

    /// Intensidad de la capa ámbar para monitores que no responden a gamma.
    var overlayStrength: Double { isEnabled ? strength : 0 }
}
