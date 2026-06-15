import Cocoa
import SwiftUI

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let displayManager = DisplayManager()
    private let calibration = CalibrationController()
    private var scrollMonitor: Any?
    private var globalScrollMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupPopover()
        NightShiftManager.shared.onChange = { [weak self] in
            self?.displayManager.reapplyColor()
        }
        setupScrollControl()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(displaysChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    /// Scroll sobre el ícono ☽ para subir/bajar el brillo (sin permisos).
    private func setupScrollControl() {
        // Local: cuando la app está activa (p. ej. con el popover abierto).
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self else { return event }
            return MainActor.assumeIsolated {
                if self.handleScroll(event) { return nil }
                return event
            }
        }
        // Global: cuando Luna está en segundo plano (lo normal en barra de menú).
        globalScrollMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self else { return }
            MainActor.assumeIsolated { _ = self.handleScroll(event) }
        }
    }

    /// Aplica el scroll al brillo si el cursor está sobre el ícono. Devuelve true si lo manejó.
    private func handleScroll(_ event: NSEvent) -> Bool {
        guard let window = statusItem.button?.window else { return false }
        guard window.frame.contains(NSEvent.mouseLocation) else { return false }
        let dy = event.scrollingDeltaY
        guard dy != 0 else { return false }
        let step = event.hasPreciseScrollingDeltas ? dy * 0.0025 : (dy > 0 ? 0.06 : -0.06)
        displayManager.nudgeAllBrightness(by: step)
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Quita las capas de atenuado y restaura la gamma al salir
        displayManager.restoreDisplays()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        let image = NSImage(systemSymbolName: "moon.fill", accessibilityDescription: "Luna")
        image?.isTemplate = true
        button.image = image
        button.action = #selector(togglePopover)
        button.target = self
    }

    private func setupPopover() {
        let view = LunaView(displayManager: displayManager, onCalibrate: { [weak self] in
            self?.startCalibration()
        })
        let hostingVC = NSHostingController(rootView: view)
        // Que el popover se ajuste al alto real del contenido (evita que se
        // recorte cuando aparece/desaparece una fila, p. ej. Night Shift).
        hostingVC.sizingOptions = [.preferredContentSize]
        popover = NSPopover()
        popover.contentViewController = hostingVC
        popover.behavior = .transient
        popover.animates = true
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            displayManager.refresh()
            NightShiftManager.shared.readStatus()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            if #available(macOS 14.0, *) { NSApp.activate() } else { NSApp.activate(ignoringOtherApps: true) }
        }
    }

    @objc private func displaysChanged() {
        displayManager.refresh()
    }

    private func startCalibration() {
        if popover.isShown { popover.performClose(nil) }
        calibration.enter(displayManager: displayManager)
    }
}
