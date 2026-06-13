import Foundation
import ServiceManagement

/// Controla si Luna se abre automáticamente al iniciar sesión (macOS 13+).
@MainActor
final class LoginItem: ObservableObject {
    static let shared = LoginItem()

    @Published var isEnabled: Bool = false

    init() { refresh() }

    func refresh() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    func set(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Luna: no se pudo cambiar 'abrir al iniciar sesión': \(error)")
        }
        refresh()
    }
}
