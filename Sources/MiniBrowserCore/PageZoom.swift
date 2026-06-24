import Foundation

/// Page zoom levels for the web view, stepped in fixed increments and clamped
/// to a sane range. Pure so the stepping/clamping is unit-tested.
public enum PageZoom {
    public static let lower = 0.5
    public static let upper = 3.0
    public static let step = 0.1
    public static let standard = 1.0

    public static func stepped(_ level: Double, by steps: Int) -> Double {
        let raw = level + Double(steps) * step
        let clamped = Swift.min(upper, Swift.max(lower, raw))
        return (clamped * 100).rounded() / 100   // avoid binary-float drift (1.3, not 1.30000…3)
    }
}
