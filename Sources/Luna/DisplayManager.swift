import Foundation
import Cocoa

struct DisplayInfo: Identifiable {
    let id: CGDirectDisplayID       // puede cambiar al reconectar
    let key: String                 // clave ESTABLE por monitor físico (persistencia)
    let name: String                // etiqueta para mostrar
    var brightness: Double          // 0.05 – 1.0
}

@MainActor
class DisplayManager: ObservableObject {
    @Published var displays: [DisplayInfo] = []
    @Published var masterBrightness: Double = 1.0
    @Published private(set) var calibrations: [String: DisplayCalibration] = [:]
    @Published private(set) var calibrationEnabled: Bool = true
    @Published private(set) var presetNames: [String] = []

    private let calibEnabledKey = "luna.calibrationEnabled"

    init() {
        calibrations = CalibrationStore.loadAll()
        calibrationEnabled = UserDefaults.standard.object(forKey: calibEnabledKey) as? Bool ?? true
        presetNames = CalibrationPresetStore.loadAll().keys.sorted()
        refresh()
    }

    // MARK: - Memoria de configuraciones (presets)

    func savePreset(_ name: String) {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        var all = CalibrationPresetStore.loadAll()
        all[n] = calibrations
        CalibrationPresetStore.saveAll(all)
        presetNames = all.keys.sorted()
    }

    func loadPreset(_ name: String) {
        guard var preset = CalibrationPresetStore.loadAll()[name] else { return }
        // Remapear claves por nombre (presets antiguos) a la clave estable actual.
        for screen in NSScreen.screens {
            let key = screen.stableKey
            let nm = screen.localizedName
            if key != nm, preset[key] == nil, let old = preset[nm] {
                preset[key] = old
                preset[nm] = nil
            }
        }
        calibrations = preset
        CalibrationStore.saveAll(calibrations)
        reapplyColor()
    }

    func deletePreset(_ name: String) {
        var all = CalibrationPresetStore.loadAll()
        all[name] = nil
        CalibrationPresetStore.saveAll(all)
        presetNames = all.keys.sorted()
    }

    /// Enumera los monitores conectados (vía NSScreen) y los controla todos por
    /// overlay: uniforme entre monitores e instantáneo (sin DDC ni subprocesos).
    func refresh() {
        migrateLegacyKeysIfNeeded()
        let previous = Dictionary(uniqueKeysWithValues: displays.map { ($0.id, $0.brightness) })

        var result: [DisplayInfo] = []
        for screen in NSScreen.screens {
            guard let cgID = screen.cgDisplayID else { continue }
            let key = screen.stableKey
            // Prioridad: valor en memoria → guardado en disco → sin atenuar.
            let brightness = previous[cgID] ?? savedBrightness(for: key) ?? 1.0
            result.append(DisplayInfo(id: cgID, key: key, name: screen.displayName, brightness: brightness))
        }
        // El monitor principal primero.
        result.sort { CGDisplayIsMain($0.id) != 0 && CGDisplayIsMain($1.id) == 0 }
        displays = result
        updateMaster()

        // Reaplicar por si cambió la geometría de algún monitor.
        for d in displays {
            OverlayDimmer.shared.setBrightness(d.brightness, for: d.id)
            applyColor(to: d)
        }
    }

    /// Migra datos guardados con clave por nombre (versión vieja) a la clave
    /// estable por monitor físico, para los monitores conectados ahora.
    private func migrateLegacyKeysIfNeeded() {
        var calChanged = false
        for screen in NSScreen.screens {
            guard screen.cgDisplayID != nil else { continue }
            let key = screen.stableKey
            let name = screen.localizedName
            guard key != name, !name.isEmpty else { continue }

            if calibrations[key] == nil, let old = calibrations[name] {
                calibrations[key] = old
                calibrations[name] = nil
                calChanged = true
            }
            let oldB = "luna.brightness.\(name)"
            let newB = "luna.brightness.\(key)"
            if UserDefaults.standard.object(forKey: newB) == nil,
               let v = UserDefaults.standard.object(forKey: oldB) as? Double {
                UserDefaults.standard.set(v, forKey: newB)
            }
        }
        if calChanged { CalibrationStore.saveAll(calibrations) }
    }

    // MARK: - Calibración de color

    func calibration(for key: String) -> DisplayCalibration {
        calibrations[key] ?? .neutral
    }

    func setCalibration(_ cal: DisplayCalibration, for key: String) {
        calibrations[key] = cal
        CalibrationStore.saveAll(calibrations)
        for d in displays where d.key == key { applyColor(to: d) }
    }

    /// Restablece a neutro pero conserva el método (gamma/overlay/manual) elegido.
    func resetCalibration(for key: String) {
        var cal = DisplayCalibration.neutral
        cal.method = calibration(for: key).method
        setCalibration(cal, for: key)
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
            var cal = calibration(for: d.key)
            if d.id == refID {
                cal.rGain = 1; cal.gGain = 1; cal.bGain = 1
            } else if let g = AutoCalibrate.gains(for: d.id, targetWhite: refProfile.white) {
                cal.rGain = g.0; cal.gGain = g.1; cal.bGain = g.2
            } else {
                continue
            }
            calibrations[d.key] = cal
        }
        calibrationEnabled = true
        UserDefaults.standard.set(true, forKey: calibEnabledKey)
        CalibrationStore.saveAll(calibrations)
        for d in displays { applyColor(to: d) }
        return true
    }

    /// Activa/desactiva toda la calibración (conserva los valores guardados).
    func setCalibrationEnabled(_ on: Bool) {
        calibrationEnabled = on
        UserDefaults.standard.set(on, forKey: calibEnabledKey)
        reapplyColor()
    }

    /// Reaplica color (calibración + Night Shift) a todos los monitores.
    func reapplyColor() {
        for d in displays { applyColor(to: d) }
    }

    /// Aplica calibración Y Night Shift juntos por monitor.
    /// - Monitores con gamma: Night Shift se integra multiplicando las ganancias
    ///   (look natural tipo Apple, negros intactos), combinado con la calibración.
    /// - Monitores overlay/manual: Night Shift va por capa ámbar (aproximado).
    private func applyColor(to display: DisplayInfo) {
        let cal = calibration(for: display.key)
        let calActive = calibrationEnabled && cal.method != .manual
        let ns = NightShiftManager.shared
        // Respaldo: capa cálida en monitores que no calientan por gamma (lo activa el usuario).
        let useNSOverlay = ns.isEnabled && cal.nightShiftFallback

        // Tinte de calibración (solo método overlay).
        if calActive, cal.method == .overlay, let t = cal.overlayTint() {
            OverlayDimmer.shared.setTint(r: t.r, g: t.g, b: t.b, alpha: t.alpha, for: display.id)
        } else {
            OverlayDimmer.shared.clearTint(for: display.id)
        }

        // Night Shift: por gamma (limpio, negros intactos) por defecto en TODOS los
        // monitores; o por capa cálida si el usuario marcó el respaldo (su monitor
        // ignora gamma). Así cualquiera puede corregir su propio caso.
        OverlayDimmer.shared.setWarm(strength: useNSOverlay ? ns.overlayStrength : 0, for: display.id)
        let warm = useNSOverlay ? (r: 1.0, g: 1.0, b: 1.0) : ns.warmGains()
        let cg = (calActive && cal.method == .gamma) ? cal : .neutral
        let lo = CGGammaValue(cg.black)
        _ = CGSetDisplayTransferByFormula(
            display.id,
            lo, CGGammaValue(cg.rGain * warm.r), CGGammaValue(cg.rGamma),
            lo, CGGammaValue(cg.gGain * warm.g), CGGammaValue(cg.gGamma),
            lo, CGGammaValue(cg.bGain * warm.b), CGGammaValue(cg.bGamma)
        )
    }

    func setBrightness(_ value: Double, for id: CGDirectDisplayID) {
        let v = clamp(value)
        guard let idx = displays.firstIndex(where: { $0.id == id }) else { return }
        displays[idx].brightness = v
        updateMaster()
        OverlayDimmer.shared.setBrightness(v, for: id)
        save(v, for: displays[idx].key)
    }

    func setAllBrightness(_ value: Double) {
        let v = clamp(value)
        masterBrightness = v
        for i in displays.indices {
            displays[i].brightness = v
            OverlayDimmer.shared.setBrightness(v, for: displays[i].id)
            save(v, for: displays[i].key)
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

    private func defaultsKey(_ key: String) -> String { "luna.brightness.\(key)" }

    private func savedBrightness(for key: String) -> Double? {
        let k = defaultsKey(key)
        guard UserDefaults.standard.object(forKey: k) != nil else { return nil }
        return UserDefaults.standard.double(forKey: k)
    }

    private func save(_ value: Double, for key: String) {
        UserDefaults.standard.set(value, forKey: defaultsKey(key))
    }
}

extension NSScreen {
    var cgDisplayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    /// Etiqueta para mostrar (con respaldo si el monitor no reporta nombre).
    var displayName: String {
        let n = localizedName
        if !n.isEmpty { return n }
        if let id = cgDisplayID { return "Pantalla \(id)" }
        return "Pantalla"
    }

    /// Clave ESTABLE por monitor físico, persistente entre reinicios y única
    /// incluso entre monitores idénticos (UUID que incorpora el puerto/ubicación).
    /// Respaldo: fabricante/modelo/serie si el UUID no está disponible.
    var stableKey: String {
        guard let id = cgDisplayID else { return "screen:\(localizedName)" }
        if let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() {
            return CFUUIDCreateString(nil, uuid) as String
        }
        return "vms:\(CGDisplayVendorNumber(id))-\(CGDisplayModelNumber(id))-\(CGDisplaySerialNumber(id))"
    }
}
