import Cocoa
import SwiftUI

/// Patrones de prueba que se muestran a pantalla completa para comparar al ojo.
enum CalibrationPattern: String, CaseIterable, Identifiable {
    case stairs, gray50, white, black, colorBars, gradient
    var id: String { rawValue }
    var label: String {
        switch self {
        case .stairs:    return "Escalera"
        case .gray50:    return "Gris 50%"
        case .white:     return "Blanco"
        case .black:     return "Negro"
        case .colorBars: return "Barras"
        case .gradient:  return "Degradado"
        }
    }
}

/// Orquesta el "modo calibración": ventanas de patrón en cada monitor + panel flotante.
@MainActor
final class CalibrationController: NSObject, ObservableObject, NSWindowDelegate {
    @Published var pattern: CalibrationPattern = .stairs
    @Published var selectedDisplayID: CGDirectDisplayID?
    @Published var referenceDisplayID: CGDirectDisplayID?
    @Published private(set) var isActive = false

    private var patternWindows: [NSWindow] = []
    private var panel: NSPanel?
    private var keyMonitor: Any?

    func toggle(displayManager: DisplayManager) {
        isActive ? exit() : enter(displayManager: displayManager)
    }

    func enter(displayManager: DisplayManager) {
        guard !isActive else { return }
        displayManager.refresh()
        if selectedDisplayID == nil || !displayManager.displays.contains(where: { $0.id == selectedDisplayID }) {
            selectedDisplayID = displayManager.displays.first?.id
        }
        if referenceDisplayID == nil || !displayManager.displays.contains(where: { $0.id == referenceDisplayID }) {
            referenceDisplayID = displayManager.displays.first(where: { CGDisplayIsMain($0.id) != 0 })?.id
                ?? displayManager.displays.first?.id
        }
        showPatternWindows()
        showPanel(displayManager: displayManager)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.exit(); return nil }   // Esc
            return event
        }
        NSApp.activate(ignoringOtherApps: true)
        isActive = true
    }

    func exit() {
        guard isActive else { return }
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
        for w in patternWindows { w.orderOut(nil) }
        patternWindows.removeAll()
        panel?.delegate = nil
        panel?.orderOut(nil)
        panel = nil
        isActive = false
    }

    // MARK: - Ventanas

    private func globalFrame() -> CGRect {
        NSScreen.screens.reduce(CGRect.null) { $0.union($1.frame) }
    }

    private func showPatternWindows() {
        let global = globalFrame()
        for screen in NSScreen.screens {
            let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.isOpaque = true
            window.backgroundColor = .black
            window.hasShadow = false
            // Debajo de las capas de brillo/tinte (.screenSaver) para ver el resultado calibrado.
            window.level = NSWindow.Level(rawValue: Int(NSWindow.Level.screenSaver.rawValue) - 2)
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
            let view = PatternView(controller: self, screenFrame: screen.frame, globalFrame: global)
            window.contentViewController = NSHostingController(rootView: view)
            window.setFrame(screen.frame, display: true)
            window.orderFrontRegardless()
            patternWindows.append(window)
        }
    }

    private func showPanel(displayManager: DisplayManager) {
        let view = CalibrationView(controller: self, displayManager: displayManager)
        let host = NSHostingController(rootView: view)
        let panel = NSPanel(contentViewController: host)
        panel.styleMask = [.titled, .closable, .utilityWindow]
        panel.title = "Calibración"
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = NSWindow.Level(rawValue: Int(NSWindow.Level.screenSaver.rawValue) + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
    }

    nonisolated func windowWillClose(_ notification: Notification) {
        MainActor.assumeIsolated { self.exit() }
    }
}

// MARK: - Patrones (SwiftUI)

struct PatternView: View {
    @ObservedObject var controller: CalibrationController
    let screenFrame: CGRect
    let globalFrame: CGRect

    var body: some View {
        GeometryReader { geo in
            switch controller.pattern {
            case .gray50: Color(white: 0.5)
            case .white:  Color.white
            case .black:  Color.black
            case .stairs: stairs
            case .colorBars: colorBars
            case .gradient: gradient
            }
        }
        .ignoresSafeArea()
    }

    private var stairs: some View {
        HStack(spacing: 0) {
            ForEach(0..<12, id: \.self) { i in
                Color(white: Double(i) / 11.0)
            }
        }
    }

    private var colorBars: some View {
        HStack(spacing: 0) {
            ForEach(Array(barColors.enumerated()), id: \.offset) { _, c in c }
        }
    }

    private var barColors: [Color] {
        [.red, .green, .blue, .cyan, Color(red: 1, green: 0, blue: 1), .yellow, .white,
         Color(white: 0.5), Color(red: 0.95, green: 0.80, blue: 0.69), .black]
    }

    /// Degradado negro→blanco mapeado por la X global: los monitores en fila forman
    /// una sola rampa continua si están bien igualados.
    private var gradient: some View {
        ZStack(alignment: .leading) {
            Color.black
            Rectangle()
                .fill(LinearGradient(colors: [.black, .white], startPoint: .leading, endPoint: .trailing))
                .frame(width: globalFrame.width)
                .offset(x: globalFrame.minX - screenFrame.minX)
        }
    }
}
