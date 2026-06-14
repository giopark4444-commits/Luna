import Foundation
import Cocoa

struct DisplayInfo: Identifiable {
    let id: CGDirectDisplayID
    let name: String
    var brightness: Double          // 0.05 – 1.0
}

@MainActor
class DisplayManager: ObservableObject {
    @Published var displays: [DisplayInfo] = []
    @Published var masterBrightness: Double = 1.0
    @Published private(set) var calibrations: [String: DisplayCalibration] = [:]
    @Published private(set) var calibrationEnabled: Bool = true

    private let calibEnabledKey = "luna.calibrationEnabled"

    init() {
        calibrations = CalibrationStore.loadAll()
        calibrationEnabled = UserDefaults.standard.object(forKey: calibEnabledKey) as? Bool ?? true
        refresh()
    }

    /// Enumera los monitores conectados (vía NSScreen) y los controla todos por
    /// overlay: uniforme entre monitores e instantáneo (sin DDC ni subprocesos).
    func refresh() {
        let previous = Dictionary(uniqueKeysWithValues: displays.map { ($0.id, $0.brightness) })

        var result: [DisplayInfo] = []
        for screen in NSScreen.screens {
            guard let cgID = screen.cgDisplayID else { continue }
            // Prioridad: valor en memoria → guardado en disco → sin atenuar.
            let brightness = previous[cgID] ?? savedBrightness(for: screen.localizedName) ?? 1.0
            result.append(DisplayInfo(id: cgID, name: screen.localizedName, brightness: brightness))
        }
        // El monitor principal primero.
        result.sort { CGDisplayIsMain($0.id) != 0 && CGDisplayIsMain($1.id) == 0 }
        displays = result
        updateMaster()

        // Reaplicar por si cambió la geometría de algún monitor.
        for d in displays {
            OverlayDimmer.shared.setBrightness(d.brightness, for: d.id)
            applyCalibration(calibration(for: d.name), to: d)
        }
    }

    // MARK: - Calibración de color

    func calibration(for name: String) -> DisplayCalibration {
        calibrations[name] ?? .neutral
    }

    func setCalibration(_ cal: DisplayCalibration, for name: String) {
        calibrations[name] = cal
        CalibrationStore.saveAll(calibrations)
        for d in displays where d.name == name { applyCalibration(cal, to: d) }
    }

    /// Restablece a neutro pero conserva el método (gamma/overlay/manual) elegido.
    func resetCalibration(for name: String) {
        var cal = DisplayCalibration.neutral
        cal.method = calibration(for: name).method
        setCalibration(cal, for: name)
    }

    /// Primer pase automático: alinea el punto blanco de cada monitor al de la
    /// referencia usando su perfil de color (ICC). Conserva gamma/negros/método.
    @discardableResult
    func autoCalibrate(referenceID: CGDirectDisplayID?) -> Bool {
        let refID = referenceID
            ?? displays.first(where: { CGDisplayIsMain($0.id) != 0 })?.id
            ?? displays.first?.id
        guard let refID, let refProfile = AutoCalibrate.profile(for: refID) else { return false }

        for d in displays {
            var cal = calibration(for: d.name)
            if d.id == refID {
                cal.rGain = 1; cal.gGain = 1; cal.bGain = 1
            } else if let g = AutoCalibrate.gains(for: d.id, targetWhite: refProfile.white) {
                cal.rGain = g.0; cal.gGain = g.1; cal.bGain = g.2
            } else {
                continue
            }
            calibrations[d.name] = cal
        }
        calibrationEnabled = true
        UserDefaults.standard.set(true, forKey: calibEnabledKey)
        CalibrationStore.saveAll(calibrations)
        for d in displays { applyCalibration(calibration(for: d.name), to: d) }
        return true
    }

    /// Activa/desactiva toda la calibración (conserva los valores guardados).
    func setCalibrationEnabled(_ on: Bool) {
        calibrationEnabled = on
        UserDefaults.standard.set(on, forKey: calibEnabledKey)
        for d in displays { applyCalibration(calibration(for: d.name), to: d) }
    }

    private func applyCalibration(_ cal: DisplayCalibration, to display: DisplayInfo) {
        // Desactivada globalmente o "manual" (menú del monitor): Luna no toca el color.
        guard calibrationEnabled, cal.method != .manual else {
            OverlayDimmer.shared.clearTint(for: display.id)
            DisplayCalibration.resetGamma(display.id)
            return
        }
        switch cal.method {
        case .gamma:
            OverlayDimmer.shared.clearTint(for: display.id)
            cal.applyGamma(to: display.id)
        case .overlay:
            DisplayCalibration.resetGamma(display.id)
            if let t = cal.overlayTint() {
                OverlayDimmer.shared.setTint(r: t.r, g: t.g, b: t.b, alpha: t.alpha, for: display.id)
            } else {
                OverlayDimmer.shared.clearTint(for: display.id)
            }
        case .manual:
            break   // ya manejado en el guard
        }
    }

    func setBrightness(_ value: Double, for id: CGDirectDisplayID) {
        let v = clamp(value)
        guard let idx = displays.firstIndex(where: { $0.id == id }) else { return }
        displays[idx].brightness = v
        updateMaster()
        OverlayDimmer.shared.setBrightness(v, for: id)
        save(v, for: displays[idx].name)
    }

    func setAllBrightness(_ value: Double) {
        let v = clamp(value)
        masterBrightness = v
        for i in displays.indices {
            displays[i].brightness = v
            OverlayDimmer.shared.setBrightness(v, for: displays[i].id)
            save(v, for: displays[i].name)
        }
    }

    /// Limpieza al salir: quita capas de atenuado y restaura la curva de color.
    func restoreDisplays() {
        OverlayDimmer.shared.removeAll()
        CGDisplayRestoreColorSyncSettings()
    }

    // MARK: - Private

    private func updateMaster() {
        guard !displays.isEmpty else { masterBrightness = 1.0; return }
        masterBrightness = displays.map(\.brightness).reduce(0, +) / Double(displays.count)
    }

    private func clamp(_ v: Double) -> Double { max(0.05, min(1.0, v)) }

    // MARK: - Persistencia (recuerda el brillo por monitor entre arranques)

    private func defaultsKey(_ name: String) -> String { "luna.brightness.\(name)" }

    private func savedBrightness(for name: String) -> Double? {
        let key = defaultsKey(name)
        guard UserDefaults.standard.object(forKey: key) != nil else { return nil }
        return UserDefaults.standard.double(forKey: key)
    }

    private func save(_ value: Double, for name: String) {
        UserDefaults.standard.set(value, forKey: defaultsKey(name))
    }
}

private extension NSScreen {
    var cgDisplayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
