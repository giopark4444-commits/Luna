import Foundation
import Darwin
import ObjectiveC

@MainActor
class NightShiftManager: ObservableObject {
    static let shared = NightShiftManager()

    @Published var isEnabled: Bool = false
    @Published var strength: Double = 0.5   // 0.0 – 1.0
    @Published var isAvailable: Bool = false

    /// Aviso cuando Night Shift cambia (para que la calibración reaplique el gamma).
    var onChange: (() -> Void)?

    private var client: AnyObject?

    private init() {
        dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY)
        guard let cls = NSClassFromString("CBBlueLightClient") as? NSObject.Type else { return }
        client = cls.init()
        isAvailable = true
        readStatus()
    }

    func readStatus() {
        guard let c = client, isAvailable else { return }

        // CBBlueLightStatus layout: [active: Bool (1 byte), enabled: Bool, sunSchedulePermitted: Bool, ...]
        // Verified on Apple Silicon macOS 13+; byte 0 is the `active` flag.
        typealias GetStatusFn = @convention(c) (AnyObject, Selector, UnsafeMutableRawPointer) -> ObjCBool
        if let imp = class_getMethodImplementation(object_getClass(c), NSSelectorFromString("getBlueLightStatus:")) {
            let fn = unsafeBitCast(imp, to: GetStatusFn.self)
            var buffer = [UInt8](repeating: 0, count: 128)
            _ = buffer.withUnsafeMutableBytes { ptr in
                fn(c, NSSelectorFromString("getBlueLightStatus:"), ptr.baseAddress!)
            }
            isEnabled = buffer[0] != 0
        }

        // getStrength: → Float pointer
        typealias GetStrengthFn = @convention(c) (AnyObject, Selector, UnsafeMutablePointer<Float>) -> ObjCBool
        if let imp = class_getMethodImplementation(object_getClass(c), NSSelectorFromString("getStrength:")) {
            let fn = unsafeBitCast(imp, to: GetStrengthFn.self)
            var value: Float = 0.5
            _ = fn(c, NSSelectorFromString("getStrength:"), &value)
            strength = Double(value)
        }
    }

    func setEnabled(_ on: Bool) {
        guard let c = client, isAvailable else { return }
        isEnabled = on
        typealias SetActiveFn = @convention(c) (AnyObject, Selector, ObjCBool) -> Void
        if let imp = class_getMethodImplementation(object_getClass(c), NSSelectorFromString("setActive:")) {
            let fn = unsafeBitCast(imp, to: SetActiveFn.self)
            fn(c, NSSelectorFromString("setActive:"), ObjCBool(on))
        }
        onChange?()
    }

    func setStrength(_ value: Double) {
        guard let c = client, isAvailable else { return }
        strength = max(0.0, min(1.0, value))
        typealias SetStrengthFn = @convention(c) (AnyObject, Selector, Float, ObjCBool) -> ObjCBool
        if let imp = class_getMethodImplementation(object_getClass(c), NSSelectorFromString("setStrength:commit:")) {
            let fn = unsafeBitCast(imp, to: SetStrengthFn.self)
            _ = fn(c, NSSelectorFromString("setStrength:commit:"), Float(strength), ObjCBool(true))
        }
        onChange?()
    }
}
