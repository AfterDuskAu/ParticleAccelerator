import Foundation

/// Keeps count of how long frames take, so every visual's cost is known on every Mac
/// (CLAUDE.md rule 5).
///
/// The graphics card reports its own time from another thread, so the numbers are kept
/// behind a lock. That's fine here: neither side is the audio thread.
final class FrameTimer: @unchecked Sendable {
    struct Summary: Equatable {
        /// Frames shown each second.
        var framesPerSecond: Double = 0
        /// The longest wait between one frame and the next, lately. At 60 frames a
        /// second a frame comes every 16.7 ms, so anything much over that is a frame
        /// that was missed, which the average alone can hide.
        var longestGapMilliseconds: Double = 0
        /// The graphics card's time for a frame: the average, and the slowest lately.
        var graphicsCardMilliseconds: Double = 0
        var slowestGraphicsCardMilliseconds: Double = 0
        /// The processor's time getting a frame ready.
        var preparingMilliseconds: Double = 0

        /// "60 fps (longest gap 17 ms) · graphics card 6.1 ms (slowest 7.4) · preparing 0.30 ms"
        var text: String {
            String(
                format: "%.0f fps (longest gap %.0f ms) · graphics card %.1f ms (slowest %.1f) · preparing %.2f ms",
                framesPerSecond, longestGapMilliseconds, graphicsCardMilliseconds,
                slowestGraphicsCardMilliseconds, preparingMilliseconds)
        }
    }

    /// How many frames the averages look back over: two seconds at 60 fps.
    static let framesRemembered = 120

    private let lock = NSLock()
    private var frameTimes: [Double] = []
    private var preparing: [Double] = []
    private var graphicsCard: [Double] = []

    /// A frame was started at this moment, and getting it ready took this long.
    func frameBegan(at time: Double, preparingSeconds: Double) {
        lock.lock()
        defer { lock.unlock() }
        Self.remember(time, in: &frameTimes)
        Self.remember(preparingSeconds, in: &preparing)
    }

    /// The graphics card finished a frame, having spent this long on it.
    func graphicsCardFinished(seconds: Double) {
        lock.lock()
        defer { lock.unlock() }
        Self.remember(seconds, in: &graphicsCard)
    }

    var summary: Summary {
        lock.lock()
        defer { lock.unlock() }
        var summary = Summary()
        if let first = frameTimes.first, let last = frameTimes.last, last > first {
            summary.framesPerSecond = Double(frameTimes.count - 1) / (last - first)
            let longestGap = zip(frameTimes.dropFirst(), frameTimes).map { $0 - $1 }.max() ?? 0
            summary.longestGapMilliseconds = longestGap * 1_000
        }
        if !graphicsCard.isEmpty {
            summary.graphicsCardMilliseconds = graphicsCard.reduce(0, +) / Double(graphicsCard.count) * 1_000
            summary.slowestGraphicsCardMilliseconds = (graphicsCard.max() ?? 0) * 1_000
        }
        if !preparing.isEmpty {
            summary.preparingMilliseconds = preparing.reduce(0, +) / Double(preparing.count) * 1_000
        }
        return summary
    }

    private static func remember(_ value: Double, in values: inout [Double]) {
        values.append(value)
        if values.count > framesRemembered { values.removeFirst(values.count - framesRemembered) }
    }
}
