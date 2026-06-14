import Foundation
import CoreGraphics

/// Cómo se aplica la calibración de color a un monitor.
enum CalibrationMethod: String, Codable {
    case gamma      // CGSetDisplayTransferByFormula — calibración real (C49RG9x, Wokyis…)
    case overlay    // capa de color — aproximado (LC49G95T y monitores que ignoran gamma)
    case manual     // configuración del propio monitor (Luna no toca el color; usas su menú)
}

/// Parámetros de calibración de un monitor.
///
/// Control por canal en tres zonas tonales (modelo Ganancia/Gamma/Negros):
/// - `?Gain`  → blancos/altas (punto blanco)
/// - `?Gamma` → medios (balance de color de los tonos medios, no solo grises)
/// - `black`  → negros/sombras (lift común)
struct DisplayCalibration: Codable, Equatable {
    var rGain: Double = 1.0     // 0.5–1.0
    var gGain: Double = 1.0
    var bGain: Double = 1.0
    var rGamma: Double = 1.0    // 0.5–2.0
    var gGamma: Double = 1.0
    var bGamma: Double = 1.0
    var black: Double = 0.0     // 0.0–0.2
    var method: CalibrationMethod = .gamma
    /// Respaldo: si este monitor no calienta con Night Shift por gamma, usar la
    /// capa cálida (overlay). Lo activa el usuario para su monitor problemático.
    var nightShiftFallback: Bool = false

    static let neutral = DisplayCalibration()

    init() {}

    // Decodificación tolerante: campos ausentes (versiones previas) toman su valor
    // por defecto, así agregar campos nuevos nunca borra lo ya guardado.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rGain = try c.decodeIfPresent(Double.self, forKey: .rGain) ?? 1.0
        gGain = try c.decodeIfPresent(Double.self, forKey: .gGain) ?? 1.0
        bGain = try c.decodeIfPresent(Double.self, forKey: .bGain) ?? 1.0
        rGamma = try c.decodeIfPresent(Double.self, forKey: .rGamma) ?? 1.0
        gGamma = try c.decodeIfPresent(Double.self, forKey: .gGamma) ?? 1.0
        bGamma = try c.decodeIfPresent(Double.self, forKey: .bGamma) ?? 1.0
        black = try c.decodeIfPresent(Double.self, forKey: .black) ?? 0.0
        method = try c.decodeIfPresent(CalibrationMethod.self, forKey: .method) ?? .gamma
        nightShiftFallback = try c.decodeIfPresent(Bool.self, forKey: .nightShiftFallback) ?? false
    }

    var isNeutral: Bool {
        rGain == 1 && gGain == 1 && bGain == 1 &&
        rGamma == 1 && gGamma == 1 && bGamma == 1 && black == 0
    }

    // MARK: - Aplicar

    /// Calibración real vía la curva por canal de la GPU (monitores que responden a gamma).
    func applyGamma(to cgID: CGDirectDisplayID) {
        let lo = CGGammaValue(black)
        _ = CGSetDisplayTransferByFormula(
            cgID,
            lo, CGGammaValue(rGain), CGGammaValue(rGamma),
            lo, CGGammaValue(gGain), CGGammaValue(gGamma),
            lo, CGGammaValue(bGain), CGGammaValue(bGamma)
        )
    }

    /// Restaura la curva de la GPU a identidad para ese monitor.
    static func resetGamma(_ cgID: CGDirectDisplayID) {
        _ = CGSetDisplayTransferByFormula(cgID, 0, 1, 1, 0, 1, 1, 0, 1, 1)
    }

    /// Para el método overlay: convierte las ganancias R/G/B en (color, alfa) de una
    /// capa que aproxima el "multiply" sobre blanco: (1-A) + A·C_canal ≈ ganancia_canal.
    /// Solo aproxima el punto blanco; gamma y negros no son representables así.
    func overlayTint() -> (r: Double, g: Double, b: Double, alpha: Double)? {
        let minGain = min(rGain, min(gGain, bGain))
        let alpha = 1.0 - minGain
        guard alpha > 0.001 else { return nil }
        func channel(_ gain: Double) -> Double { max(0, min(1, 1 - (1 - gain) / alpha)) }
        return (channel(rGain), channel(gGain), channel(bGain), alpha)
    }
}

/// Persistencia de las calibraciones por nombre de monitor.
enum CalibrationStore {
    private static let key = "luna.calibrations.v2"

    static func loadAll() -> [String: DisplayCalibration] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: DisplayCalibration].self, from: data)
        else { return [:] }
        return decoded
    }

    static func saveAll(_ all: [String: DisplayCalibration]) {
        guard let data = try? JSONEncoder().encode(all) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

/// Configuración exportable/importable de Luna (para respaldo o compartir con
/// otro usuario). Se empareja por NOMBRE de monitor al importar, porque la clave
/// estable (UUID) es distinta en cada máquina.
struct LunaConfig: Codable {
    var version: Int = 1
    var calibrationEnabled: Bool = true
    var nightShiftEnabled: Bool = false
    var nightShiftStrength: Double = 0.5
    var monitors: [MonitorConfig] = []

    struct MonitorConfig: Codable {
        var name: String
        var brightness: Double
        var calibration: DisplayCalibration
    }
}

/// Memoria de configuraciones guardadas: cada preset es la calibración de todos
/// los monitores (clave = nombre del monitor) bajo un nombre.
enum CalibrationPresetStore {
    private static let key = "luna.calibration.presets.v1"

    static func loadAll() -> [String: [String: DisplayCalibration]] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: [String: DisplayCalibration]].self, from: data)
        else { return [:] }
        return decoded
    }

    static func saveAll(_ all: [String: [String: DisplayCalibration]]) {
        guard let data = try? JSONEncoder().encode(all) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
