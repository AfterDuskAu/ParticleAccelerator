import CoreGraphics
import Metal

/// What a quality setting comes to: how many particles a visual may use, and how big a
/// picture it's drawn at before being scaled to the screen. Kept in step with
/// docs/OUTPUT.md, where the numbers were measured.
struct QualityTier: Equatable {
    var particleCount: Int
    var drawingWidth: Int
    var drawingHeight: Int

    static let low = QualityTier(particleCount: 75_000, drawingWidth: 1_280, drawingHeight: 720)
    static let medium = QualityTier(particleCount: 150_000, drawingWidth: 1_920, drawingHeight: 1_080)
    static let high = QualityTier(particleCount: 300_000, drawingWidth: 2_560, drawingHeight: 1_440)
    static let ultra = QualityTier(particleCount: 1_000_000, drawingWidth: 3_840, drawingHeight: 2_160)

    /// The tier for a quality setting on this Mac's graphics card.
    static func tier(for quality: Quality, isLowPowerCard: Bool) -> QualityTier {
        switch quality {
        case .low: return .low
        case .medium: return .medium
        case .high: return .high
        case .ultra: return .ultra
        case .auto:
            // A laptop's built-in low-power graphics starts at Medium; anything stronger
            // at High, which the 2019 iMac holds at 60 fps (measured).
            return isLowPowerCard ? .medium : .high
        }
    }

    /// The size to draw the picture at for a view of this many pixels: the view's own
    /// shape, with no more pixels than the tier allows and no more than the view has.
    func pictureSize(forViewPixels view: CGSize) -> (width: Int, height: Int) {
        let viewWidth = max(1, Double(view.width))
        let viewHeight = max(1, Double(view.height))
        let allowed = Double(drawingWidth * drawingHeight)
        let scale = min(1, (allowed / (viewWidth * viewHeight)).squareRoot())
        // Even numbers, so the half-size glow pictures line up.
        func even(_ value: Double) -> Int { max(2, Int((value / 2).rounded()) * 2) }
        return (even(viewWidth * scale), even(viewHeight * scale))
    }
}
