import Foundation
import CoreGraphics

/// Cómo se aplica la calibración de color a un monitor.
enum CalibrationMethod: String, Codable {
    case gamma      // CGSetDisplayTransferByFormula — calibración real (C49RG9x, Wokyis…)
    case overlay    // capa de color — aproximado (LC49G95T y monitores que ignoran gamma)
}

/// Parámetros de calibración de un monitor.
struct DisplayCalibration: Codable, Equatable {
    var rGain: Double = 1.0     // 0.5–1.0  (punto blanco)
    var gGain: Double = 1.0
    var bGain: Double = 1.0
    var gamma: Double = 1.0     // 0.5–2.0  (claridad de los grises)
    var black: Double = 0.0     // 0.0–0.2  (nivel de negro / "lift")
    var method: CalibrationMethod = .gamma

    static let neutral = DisplayCalibration()

    var isNeutral: Bool {
        rGain == 1.0 && gGain == 1.0 && bGain == 1.0 && gamma == 1.0 && black == 0.0
    }

    // MARK: - Aplicar

    /// Calibración real vía la curva de la GPU (solo monitores que responden a gamma).
    func applyGamma(to cgID: CGDirectDisplayID) {
        let lo = CGGammaValue(black)
        let g = CGGammaValue(gamma)
        _ = CGSetDisplayTransferByFormula(
            cgID,
            lo, CGGammaValue(rGain), g,
            lo, CGGammaValue(gGain), g,
            lo, CGGammaValue(bGain), g
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
    private static let key = "luna.calibrations.v1"

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
