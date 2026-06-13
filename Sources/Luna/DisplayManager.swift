import Foundation
import Cocoa

enum BrightnessMethod {
    case ddc(m1ddcIndex: Int)
    case gamma(cgDisplayID: CGDirectDisplayID)
}

struct DisplayInfo: Identifiable {
    let id: Int                     // m1ddc index (1-based) or cgDisplayID for gamma-only
    let name: String
    let method: BrightnessMethod
    var brightness: Double          // 0.0 – 1.0
    var isGammaOnly: Bool { if case .gamma = method { return true }; return false }
}

@MainActor
class DisplayManager: ObservableObject {
    @Published var displays: [DisplayInfo] = []
    @Published var masterBrightness: Double = 1.0
    @Published var isRefreshing: Bool = false

    private let m1ddcPath: String = {
        // Prefer the binary bundled inside Luna.app/Contents/Resources/
        if let bundled = Bundle.main.path(forResource: "m1ddc", ofType: nil) {
            return bundled
        }
        // Fall back to a Homebrew installation
        return "/opt/homebrew/bin/m1ddc"
    }()

    init() { refresh() }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        let path = m1ddcPath
        Task {
            let fetched = await Task.detached(priority: .userInitiated) {
                DisplayManager.fetchAll(m1ddcPath: path)
            }.value
            let currentBrightness = Dictionary(uniqueKeysWithValues: self.displays.map { ($0.id, $0.brightness) })
            self.displays = fetched.map { var d = $0; d.brightness = currentBrightness[d.id] ?? d.brightness; return d }
            self.updateMaster()
            self.isRefreshing = false
        }
    }

    func setBrightness(_ value: Double, for displayID: Int) {
        let v = clamp(value)
        guard let idx = displays.firstIndex(where: { $0.id == displayID }) else { return }
        displays[idx].brightness = v
        updateMaster()
        let method = displays[idx].method
        let path = m1ddcPath
        Task.detached(priority: .userInitiated) {
            DisplayManager.applyBrightness(v, method: method, m1ddcPath: path)
        }
    }

    func setAllBrightness(_ value: Double) {
        let v = clamp(value)
        masterBrightness = v
        let methods = displays.map { (id: $0.id, method: $0.method) }
        for i in displays.indices { displays[i].brightness = v }
        let path = m1ddcPath
        Task.detached(priority: .userInitiated) {
            await withTaskGroup(of: Void.self) { group in
                for item in methods {
                    group.addTask { DisplayManager.applyBrightness(v, method: item.method, m1ddcPath: path) }
                }
            }
        }
    }

    func restoreGamma() {
        CGDisplayRestoreColorSyncSettings()
    }

    // MARK: - Private

    private func updateMaster() {
        guard !displays.isEmpty else { masterBrightness = 1.0; return }
        masterBrightness = displays.map(\.brightness).reduce(0, +) / Double(displays.count)
    }

    private func clamp(_ v: Double) -> Double { max(0.05, min(1.0, v)) }

    // MARK: - Static background work

    nonisolated private static func fetchAll(m1ddcPath: String) -> [DisplayInfo] {
        let detailed = run(m1ddcPath, args: ["display", "list", "detailed"])
        // Map m1ddc index → CGDirectDisplayID from "Display ID:" lines
        let cgIDMap = parseDisplayIDMap(from: detailed)

        // Build the basic list
        var result: [DisplayInfo] = []
        for line in detailed.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("["),
                  let bracketEnd = trimmed.firstIndex(of: "]"),
                  let index = Int(trimmed[trimmed.index(after: trimmed.startIndex)..<bracketEnd])
            else { continue }

            let afterBracket = trimmed[trimmed.index(after: bracketEnd)...]
                .trimmingCharacters(in: .whitespaces)
            let name: String = {
                if let p = afterBracket.firstIndex(of: "(") {
                    return String(afterBracket[..<p]).trimmingCharacters(in: .whitespaces)
                }
                return afterBracket
            }()

            let displayName = name.isEmpty ? "Display \(index)" : name

            // Try DDC first
            let (brightness, ddcOK) = readDDCBrightness(index: index, m1ddcPath: m1ddcPath)

            if ddcOK {
                result.append(DisplayInfo(
                    id: index,
                    name: displayName,
                    method: .ddc(m1ddcIndex: index),
                    brightness: brightness
                ))
            } else if let cgID = cgIDMap[index] {
                // Fall back to gamma; read current gamma to estimate brightness
                let gammaBrightness = readGammaBrightness(cgID: cgID)
                result.append(DisplayInfo(
                    id: index,
                    name: displayName,
                    method: .gamma(cgDisplayID: cgID),
                    brightness: gammaBrightness
                ))
            }
        }
        return result
    }

    nonisolated private static func parseDisplayIDMap(from output: String) -> [Int: CGDirectDisplayID] {
        var map: [Int: CGDirectDisplayID] = [:]
        var currentIndex: Int? = nil
        for line in output.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("["), let end = t.firstIndex(of: "]"),
               let idx = Int(t[t.index(after: t.startIndex)..<end]) {
                currentIndex = idx
            } else if let idx = currentIndex, t.contains("Display ID:") {
                let parts = t.components(separatedBy: ":")
                if parts.count >= 2,
                   let val = UInt32(parts.last!.trimmingCharacters(in: .whitespaces)) {
                    map[idx] = CGDirectDisplayID(val)
                }
            }
        }
        return map
    }

    nonisolated private static func readDDCBrightness(index: Int, m1ddcPath: String) -> (Double, Bool) {
        let out = run(m1ddcPath, args: ["display", String(index), "get", "luminance"])
        let first = out.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: "\n").first ?? ""
        if let pct = Int(first.trimmingCharacters(in: .whitespaces)), pct >= 0, pct <= 100 {
            return (Double(pct) / 100.0, true)
        }
        return (1.0, false)
    }

    nonisolated private static func readGammaBrightness(cgID: CGDirectDisplayID) -> Double {
        var red = [CGGammaValue](repeating: 0, count: 256)
        var green = [CGGammaValue](repeating: 0, count: 256)
        var blue = [CGGammaValue](repeating: 0, count: 256)
        var count: UInt32 = 0
        CGGetDisplayTransferByTable(cgID, 256, &red, &green, &blue, &count)
        guard count > 0 else { return 1.0 }
        let last = Int(count) - 1
        let avg = (Double(red[last]) + Double(green[last]) + Double(blue[last])) / 3.0
        // If avg ≈ 1.0 it means full brightness (no gamma applied yet)
        return avg < 0.02 ? 1.0 : avg
    }

    nonisolated private static func applyBrightness(_ value: Double, method: BrightnessMethod, m1ddcPath: String) {
        switch method {
        case .ddc(let idx):
            let pct = Int(value * 100)
            _ = run(m1ddcPath, args: ["display", String(idx), "set", "luminance", String(pct)])
        case .gamma(let cgID):
            let v = CGGammaValue(value)
            CGSetDisplayTransferByFormula(cgID, 0, v, 1.0, 0, v, 1.0, 0, v, 1.0)
        }
    }

    @discardableResult
    nonisolated private static func run(_ path: String, args: [String]) -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = args
        let outPipe = Pipe(); let errPipe = Pipe()
        proc.standardOutput = outPipe; proc.standardError = errPipe
        guard (try? proc.run()) != nil else { return "" }
        let group = DispatchGroup()
        group.enter()
        proc.terminationHandler = { _ in group.leave() }
        if group.wait(timeout: .now() + .seconds(5)) == .timedOut {
            proc.terminate()
            proc.waitUntilExit()
        }
        let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return out.isEmpty ? err : out + (err.isEmpty ? "" : "\n" + err)
    }
}
