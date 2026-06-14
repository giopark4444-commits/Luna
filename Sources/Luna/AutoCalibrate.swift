import CoreGraphics
import Foundation

/// Primer pase automático de calibración basado en el perfil de color (ICC) de
/// cada monitor: alinea el punto blanco de cada uno al del monitor de referencia.
///
/// No usa colorímetro (la Mac no mide la pantalla), así que es una estimación a
/// partir de los datos del perfil del monitor — un buen punto de partida que luego
/// se afina a mano.
enum AutoCalibrate {

    struct Profile {
        var white: (x: Double, y: Double)   // cromaticidad del blanco
        var matrix: [[Double]]              // RGB → XYZ (3x3)
    }

    static func profile(for cgID: CGDirectDisplayID) -> Profile? {
        let cs = CGDisplayCopyColorSpace(cgID)
        guard let cf = cs.copyICCData() else { return nil }
        let bytes = [UInt8](cf as Data)
        guard let r = xyz(bytes, "rXYZ"), let g = xyz(bytes, "gXYZ"),
              let b = xyz(bytes, "bXYZ") else { return nil }

        // Colorantes (adaptados a D50 en el ICC).
        var m = [[r.0, g.0, b.0], [r.1, g.1, b.1], [r.2, g.2, b.2]]
        // Deshacer la adaptación cromática (tag 'chad') para recuperar el blanco real.
        if let chad = chad(bytes), let invChad = invert3x3(chad) {
            m = matMul(invChad, m)
        }
        // Blanco nativo = M · (1,1,1).
        let wx = m[0][0] + m[0][1] + m[0][2]
        let wy = m[1][0] + m[1][1] + m[1][2]
        let wz = m[2][0] + m[2][1] + m[2][2]
        let sum = wx + wy + wz
        guard sum > 0 else { return nil }
        return Profile(white: (x: wx / sum, y: wy / sum), matrix: m)
    }

    /// Matriz de adaptación cromática (tag 'chad', sf32 con 9 valores 3x3).
    private static func chad(_ b: [UInt8]) -> [[Double]]? {
        guard let off = tagOffset(b, "chad"), off + 8 + 36 <= b.count else { return nil }
        var v = [Double](repeating: 0, count: 9)
        for i in 0..<9 { v[i] = s15(b, off + 8 + i * 4) }
        return [[v[0], v[1], v[2]], [v[3], v[4], v[5]], [v[6], v[7], v[8]]]
    }

    private static func matMul(_ a: [[Double]], _ b: [[Double]]) -> [[Double]] {
        var r = [[Double]](repeating: [0, 0, 0], count: 3)
        for i in 0..<3 { for j in 0..<3 { r[i][j] = a[i][0]*b[0][j] + a[i][1]*b[1][j] + a[i][2]*b[2][j] } }
        return r
    }

    /// Ganancias R/G/B (0.5–1.0) para que `cgID` reproduzca el blanco `target`.
    static func gains(for cgID: CGDirectDisplayID, targetWhite target: (x: Double, y: Double)) -> (Double, Double, Double)? {
        guard let p = profile(for: cgID), let inv = invert3x3(p.matrix) else { return nil }
        let Yw = p.matrix[1][0] + p.matrix[1][1] + p.matrix[1][2]   // luminancia del blanco propio
        let y = max(0.0001, target.y)
        let t = [target.x / y * Yw, Yw, (1 - target.x - target.y) / y * Yw]
        var gain = [
            inv[0][0]*t[0] + inv[0][1]*t[1] + inv[0][2]*t[2],
            inv[1][0]*t[0] + inv[1][1]*t[1] + inv[1][2]*t[2],
            inv[2][0]*t[0] + inv[2][1]*t[1] + inv[2][2]*t[2]
        ]
        let mx = max(gain[0], max(gain[1], gain[2]))
        guard mx > 0 else { return nil }
        gain = gain.map { max(0.5, min(1.0, $0 / mx)) }   // normalizar a ≤1 y limitar al rango
        return (gain[0], gain[1], gain[2])
    }

    // MARK: - Lectura del ICC

    private static func xyz(_ b: [UInt8], _ sig: String) -> (Double, Double, Double)? {
        guard let off = tagOffset(b, sig), off + 20 <= b.count else { return nil }
        return (s15(b, off + 8), s15(b, off + 12), s15(b, off + 16))
    }

    private static func tagOffset(_ b: [UInt8], _ sig: String) -> Int? {
        guard b.count > 132 else { return nil }
        let s = Array(sig.utf8)
        let count = Int(u32(b, 128))
        var p = 132
        for _ in 0..<count {
            guard p + 12 <= b.count else { return nil }
            if b[p] == s[0] && b[p+1] == s[1] && b[p+2] == s[2] && b[p+3] == s[3] {
                return Int(u32(b, p + 4))
            }
            p += 12
        }
        return nil
    }

    private static func u32(_ b: [UInt8], _ o: Int) -> UInt32 {
        (UInt32(b[o]) << 24) | (UInt32(b[o+1]) << 16) | (UInt32(b[o+2]) << 8) | UInt32(b[o+3])
    }

    private static func s15(_ b: [UInt8], _ o: Int) -> Double {
        Double(Int32(bitPattern: u32(b, o))) / 65536.0
    }

    private static func invert3x3(_ m: [[Double]]) -> [[Double]]? {
        let a = m[0][0], b = m[0][1], c = m[0][2]
        let d = m[1][0], e = m[1][1], f = m[1][2]
        let g = m[2][0], h = m[2][1], i = m[2][2]
        let A = e*i - f*h, B = -(d*i - f*g), C = d*h - e*g
        let det = a*A + b*B + c*C
        guard abs(det) > 1e-9 else { return nil }
        let id = 1 / det
        return [
            [A*id, (c*h - b*i)*id, (b*f - c*e)*id],
            [B*id, (a*i - c*g)*id, (c*d - a*f)*id],
            [C*id, (b*g - a*h)*id, (a*e - b*d)*id]
        ]
    }
}
