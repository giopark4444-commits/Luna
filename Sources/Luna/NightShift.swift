import Cocoa

/// Night Shift propio de Luna (capa cálida por gamma/overlay vía DisplayManager).
///
/// Añade:
/// - Transición progresiva (~1 min) al encender/apagar, en vez de un cambio brusco.
/// - Horario: activar/desactivar a una hora del día.
@MainActor
class NightShiftManager: ObservableObject {
    static let shared = NightShiftManager()

    @Published var isEnabled: Bool = false      // intención (persistida)
    @Published var strength: Double = 0.5       // intensidad objetivo (persistida)
    @Published var isAvailable: Bool = true

    @Published var scheduleEnabled: Bool = false
    @Published var onMinutes: Int = 21 * 60     // 21:00
    @Published var offMinutes: Int = 7 * 60     // 07:00

    /// Aviso cuando cambia el calentado efectivo (DisplayManager reaplica el color).
    var onChange: (() -> Void)?

    /// Intensidad EFECTIVA (animada). Es la que produce el calentado real.
    private var currentStrength: Double = 0

    private let fadeDuration = 60.0             // ~1 minuto de transición
    private var fadeTimer: Timer?
    private var fadeStart = 0.0
    private var fadeTarget = 0.0
    private var fadeTick = 0
    private var fadeSteps = 60

    private var scheduleTimer: Timer?
    private var lastScheduleShould: Bool?

    private enum K {
        static let enabled = "luna.nightshift.enabled"
        static let strength = "luna.nightshift.strength"
        static let schedule = "luna.nightshift.schedule"
        static let onMin = "luna.nightshift.onMinutes"
        static let offMin = "luna.nightshift.offMinutes"
    }

    private init() {
        let d = UserDefaults.standard
        isEnabled = d.bool(forKey: K.enabled)
        strength = d.object(forKey: K.strength) as? Double ?? 0.5
        scheduleEnabled = d.bool(forKey: K.schedule)
        onMinutes = d.object(forKey: K.onMin) as? Int ?? 21 * 60
        offMinutes = d.object(forKey: K.offMin) as? Int ?? 7 * 60

        // Al abrir: si hay horario, sincroniza el estado a la ventana actual (instantáneo).
        if scheduleEnabled {
            let should = scheduleShouldBeOn()
            isEnabled = should
            lastScheduleShould = should
        }
        currentStrength = isEnabled ? strength : 0   // sin fade al arrancar
        startScheduleTimer()
    }

    func readStatus() {}

    // MARK: - Encendido / intensidad

    func setEnabled(_ on: Bool) {
        isEnabled = on
        UserDefaults.standard.set(on, forKey: K.enabled)
        startFade()                                  // transición progresiva
    }

    func setStrength(_ value: Double) {
        strength = max(0.0, min(1.0, value))
        UserDefaults.standard.set(strength, forKey: K.strength)
        if isEnabled {
            if fadeTimer == nil {
                currentStrength = strength           // ajuste manual: inmediato y fluido
                onChange?()
            } else {
                fadeTarget = strength                // si está en transición, apunta al nuevo objetivo
            }
        }
    }

    // MARK: - Horario

    func setScheduleEnabled(_ on: Bool) {
        scheduleEnabled = on
        UserDefaults.standard.set(on, forKey: K.schedule)
        lastScheduleShould = nil
        syncToScheduleNow()
    }

    func setOnMinutes(_ m: Int) {
        onMinutes = m
        UserDefaults.standard.set(m, forKey: K.onMin)
        lastScheduleShould = nil
    }

    func setOffMinutes(_ m: Int) {
        offMinutes = m
        UserDefaults.standard.set(m, forKey: K.offMin)
        lastScheduleShould = nil
    }

    // MARK: - Salida usada por DisplayManager

    /// Ganancias multiplicativas (gamma): blanco cálido, negros intactos.
    func warmGains() -> (r: Double, g: Double, b: Double) {
        (1.0, 1.0 - 0.07 * currentStrength, 1.0 - 0.32 * currentStrength)
    }

    /// Intensidad para la capa ámbar (monitores que no responden a gamma).
    var overlayStrength: Double { currentStrength }

    // MARK: - Privado: transición

    private func startFade() {
        fadeTimer?.invalidate()
        fadeStart = currentStrength
        fadeTarget = isEnabled ? strength : 0
        fadeTick = 0
        fadeSteps = max(1, Int(fadeDuration))
        if abs(fadeTarget - fadeStart) < 0.0001 { onChange?(); return }
        fadeTimer = Timer.scheduledTimer(withTimeInterval: fadeDuration / Double(fadeSteps), repeats: true) { [weak self] _ in
            Task { @MainActor in self?.fadeStep() }
        }
    }

    private func fadeStep() {
        fadeTick += 1
        let t = min(1.0, Double(fadeTick) / Double(fadeSteps))
        currentStrength = fadeStart + (fadeTarget - fadeStart) * t
        if fadeTick >= fadeSteps {
            currentStrength = fadeTarget
            fadeTimer?.invalidate()
            fadeTimer = nil
        }
        onChange?()
    }

    // MARK: - Privado: horario

    private func startScheduleTimer() {
        scheduleTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.evaluateSchedule() }
        }
    }

    private func scheduleShouldBeOn(_ nowMinutes: Int? = nil) -> Bool {
        let now = nowMinutes ?? currentMinuteOfDay()
        if onMinutes == offMinutes { return false }
        if onMinutes < offMinutes { return now >= onMinutes && now < offMinutes }
        return now >= onMinutes || now < offMinutes     // ventana que cruza medianoche
    }

    private func currentMinuteOfDay() -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: Date())
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    private func evaluateSchedule() {
        guard scheduleEnabled else { return }
        let should = scheduleShouldBeOn()
        defer { lastScheduleShould = should }
        guard let last = lastScheduleShould else { return }   // primer tick solo sincroniza
        if should != last, should != isEnabled {
            setEnabled(should)                                // cruza la hora → transición progresiva
        }
    }

    /// Al activar el horario o cambiar la hora: alinear de inmediato (con transición).
    private func syncToScheduleNow() {
        guard scheduleEnabled else { return }
        let should = scheduleShouldBeOn()
        lastScheduleShould = should
        if should != isEnabled { setEnabled(should) }
    }
}
