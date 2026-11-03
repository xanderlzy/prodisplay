import CoreGraphics
import Foundation

/// System brightness of the built-in panel via the private DisplayServices framework.
enum BrightnessService {
    private typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private static let handle = dlopen(
        "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY
    )
    private static let getFn: GetFn? = symbol("DisplayServicesGetBrightness")
    private static let setFn: SetFn? = symbol("DisplayServicesSetBrightness")

    private static func symbol<T>(_ name: String) -> T? {
        guard let handle, let sym = dlsym(handle, name) else { return nil }
        return unsafeBitCast(sym, to: T.self)
    }

    static func brightness(of display: CGDirectDisplayID) -> Double? {
        var value: Float = 0
        guard let getFn, getFn(display, &value) == 0 else { return nil }
        return Double(value)
    }

    static func setBrightness(_ value: Double, of display: CGDirectDisplayID) {
        _ = setFn?(display, Float(min(max(value, 0), 1)))
    }
}
