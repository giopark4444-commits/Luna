import Cocoa
import SwiftUI

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let displayManager = DisplayManager()
    private let calibration = CalibrationController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupPopover()
        // Night Shift comparte el LUT de gamma con la calibración: al cambiar,
        // reaplicamos la calibración (cede mientras Night Shift está activo).
        NightShiftManager.shared.onChange = { [weak self] in
            self?.displayManager.reapplyCalibrations()
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(displaysChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
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
