import Foundation

/// The loudest a part of the sound has been in the last ten seconds or so. Auto-gain
/// measures everything against this, so quiet songs and loud ones both move.
///
/// It keeps the loudest moment of each of the last ten seconds, which is exact enough
/// and costs almost nothing. A louder moment raises it at once; when the loud part
/// leaves the ten seconds, it eases down over a couple of seconds instead of dropping.
struct RecentPeak {
    static let secondsRemembered = 10

    /// The quietest value it ever reports, so silence and hiss aren't blown up to full.
    let floor: Float
    private(set) var value: Float

    private var loudestOfEachSecond: [Float]
    private var currentSecond = 0
    private var stepsIntoSecond = 0
    private let stepsPerSecond: Int
    private let easeDownPerStep: Float

    /// - Parameters:
    ///   - stepSeconds: how much time each `add` stands for.
    ///   - floor: in decibels.
    init(stepSeconds: Double, floor: Float) {
        self.floor = floor
        value = floor
        loudestOfEachSecond = Array(repeating: floor, count: Self.secondsRemembered)
        stepsPerSecond = max(1, Int((1 / stepSeconds).rounded()))
        easeDownPerStep = Float(1 - exp(-stepSeconds / 2))
    }

    /// Takes the newest measurement, in decibels, and returns the recent peak.
    mutating func add(_ decibels: Float) -> Float {
        loudestOfEachSecond[currentSecond] = max(loudestOfEachSecond[currentSecond], decibels)
        stepsIntoSecond += 1
        if stepsIntoSecond == stepsPerSecond {
            stepsIntoSecond = 0
            currentSecond = (currentSecond + 1) % Self.secondsRemembered
            loudestOfEachSecond[currentSecond] = floor
        }

        var loudest = floor
        for second in loudestOfEachSecond { loudest = max(loudest, second) }
        if loudest >= value {
            value = loudest
        } else {
            value += (loudest - value) * easeDownPerStep
        }
        return value
    }
}
