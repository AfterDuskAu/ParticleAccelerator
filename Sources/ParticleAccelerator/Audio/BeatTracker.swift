import Accelerate
import Foundation

/// Hears the beat: each kick as it lands, the song's tempo, and a steady count of beats.
///
/// The analyser calls `add` once for every step of sound (about 86 times a second) with
/// how much the sound just jumped. "Flux" is that jump: how much louder the pitches got
/// since the step before. A kick drum is a big jump in the kick band.
final class BeatTracker {
    /// A jump smaller than this is never a beat. 1 would be a full-strength tone
    /// appearing from nothing, measured against how loud the song has been lately.
    static let smallestBeat: Float = 0.15
    /// A beat has to be at least this share of the strongest jump of the last few
    /// seconds. It's what tells a kick drum from the bass notes between the kicks.
    static let shareOfStrongest: Float = 0.5
    static let strongestFadeSeconds = 4.0
    /// Kicks closer together than this count as one.
    static let shortestGapSeconds = 0.1
    /// How quickly the `beat` pulse fades.
    static let pulseFadeSeconds = 0.06
    /// The tempos it looks for. Outside these, it hears half or double the real tempo.
    static let slowestTempo = 60.0
    static let fastestTempo = 180.0
    /// A rhythm that repeats every beat also repeats every two beats, so two tempos
    /// always fit (say 75 and 150). The one nearer this wins, unless the other fits
    /// much better. Most music is between 85 and 170 beats a minute.
    static let likeliestTempo = 125.0
    /// How far from the likeliest tempo still counts as likely, in doublings.
    static let likelyTempoSpread = 0.7
    /// How strongly the rhythm has to repeat before a tempo is believed, from 0 to 1.
    /// Measured on 2026-10-03: hiss with no rhythm at all reaches 0.16, and a real
    /// song's verses 0.35 to 0.65.
    static let leastTempoConfidence: Float = 0.2
    /// A settled tempo is only replaced by one that repeats this strongly. In the same
    /// song's first chorus, double the real tempo measured 0.22 for two seconds.
    static let leastConfidenceToReplace: Float = 0.3
    /// Once a tempo is settled, it counts for this much more than any other. A busy
    /// chorus with strumming on the half-beats fits double the tempo almost as well, and
    /// without this the tempo would jump there and back (measured on a real song).
    static let settledTempoBonus: Float = 1.3
    /// The tempo is forgotten after this long with no sound at all.
    static let forgetAfterSilentSeconds = 10.0

    private(set) var beat: Float = 0
    private(set) var beatsHeard = 0
    private(set) var beatsPerMinute: Double?
    private(set) var beatPhase: Double = 0
    private(set) var steadyBeats = 0
    /// How strongly the rhythm repeated at the last tempo measured, from 0 to 1.
    private(set) var tempoConfidence: Float = 0

    private let stepSeconds: Double

    // Hearing each kick.
    private var recentKickFlux: [Float]
    private var recentKickIndex = 0
    private var stepsSinceBeat: Int
    private let shortestGapSteps: Int
    private var strongestLately: Float = 0
    private let strongestFadePerStep: Float

    // Finding the tempo.
    private var onsetHistory: [Float]
    private var onsetIndex = 0
    private var onsetsKept = 0
    private var onsetsInOrder: [Float]
    private var repeatStrength: [Float]
    private let shortestLag: Int
    private let longestLag: Int
    private var stepsSinceTempoCheck = 0
    private let stepsBetweenTempoChecks: Int
    private let fewestOnsetsForTempo: Int
    private var candidateTempo: Double?
    private var candidateAgreements = 0
    private var silentSteps = 0
    private let forgetAfterSilentSteps: Int

    init(stepSeconds: Double) {
        self.stepSeconds = stepSeconds
        let stepsPerSecond = 1 / stepSeconds

        recentKickFlux = Array(repeating: 0, count: max(8, Int(0.5 * stepsPerSecond)))
        shortestGapSteps = max(1, Int((Self.shortestGapSeconds * stepsPerSecond).rounded()))
        stepsSinceBeat = shortestGapSteps
        strongestFadePerStep = Float(exp(-stepSeconds / Self.strongestFadeSeconds))

        let historyCount = Int(8 * stepsPerSecond)
        onsetHistory = Array(repeating: 0, count: historyCount)
        onsetsInOrder = Array(repeating: 0, count: historyCount)
        // A "lag" is the gap between two beats, in steps: fast tempos have short lags.
        shortestLag = max(2, Int((60 / Self.fastestTempo) * stepsPerSecond))
        longestLag = Int(((60 / Self.slowestTempo) * stepsPerSecond).rounded(.up))
        // One spare lag at each end, for measuring between whole steps.
        repeatStrength = Array(repeating: 0, count: longestLag - shortestLag + 3)
        stepsBetweenTempoChecks = max(1, Int(0.5 * stepsPerSecond))
        fewestOnsetsForTempo = Int(4 * stepsPerSecond)
        forgetAfterSilentSteps = Int(Self.forgetAfterSilentSeconds * stepsPerSecond)
    }

    /// Takes one step of sound.
    /// - Parameters:
    ///   - kickFlux: how much the kick band just jumped.
    ///   - onsetStrength: how much the whole sound just jumped.
    ///   - isSilent: whether there's no sound at all right now.
    func add(kickFlux: Float, onsetStrength: Float, isSilent: Bool) {
        let heardBeat = hearKick(kickFlux)

        silentSteps = isSilent ? silentSteps + 1 : 0
        if silentSteps >= forgetAfterSilentSteps {
            beatsPerMinute = nil
            candidateTempo = nil
        }

        onsetHistory[onsetIndex] = onsetStrength
        onsetIndex = (onsetIndex + 1) % onsetHistory.count
        onsetsKept = min(onsetsKept + 1, onsetHistory.count)
        stepsSinceTempoCheck += 1
        if stepsSinceTempoCheck >= stepsBetweenTempoChecks, onsetsKept >= fewestOnsetsForTempo {
            stepsSinceTempoCheck = 0
            settleTempo(measureTempo())
        }

        countSteadily(heardBeat: heardBeat)
    }

    // MARK: Each kick

    /// A beat is a jump in the kick band that stands well above how much the band has
    /// been moving for the last half second, and isn't small beside the strongest jumps
    /// of the last few seconds.
    private func hearKick(_ kickFlux: Float) -> Bool {
        var mean: Float = 0
        var meanOfSquares: Float = 0
        vDSP_meanv(recentKickFlux, 1, &mean, vDSP_Length(recentKickFlux.count))
        vDSP_measqv(recentKickFlux, 1, &meanOfSquares, vDSP_Length(recentKickFlux.count))
        let spread = max(0, meanOfSquares - mean * mean).squareRoot()
        let threshold = max(
            mean + 2 * spread + Self.smallestBeat, Self.shareOfStrongest * strongestLately)
        strongestLately = max(kickFlux, strongestLately * strongestFadePerStep)

        recentKickFlux[recentKickIndex] = kickFlux
        recentKickIndex = (recentKickIndex + 1) % recentKickFlux.count

        stepsSinceBeat += 1
        let heardBeat = kickFlux > threshold && stepsSinceBeat >= shortestGapSteps
        if heardBeat {
            stepsSinceBeat = 0
            beatsHeard += 1
        }
        beat = Float(exp(-Double(stepsSinceBeat) * stepSeconds / Self.pulseFadeSeconds))
        return heardBeat
    }

    // MARK: The tempo

    /// Finds the gap at which the last eight seconds of jumps best line up with
    /// themselves (their "autocorrelation"): that gap is one beat. Returns nil when
    /// nothing repeats clearly.
    private func measureTempo() -> Double? {
        // The history is a ring: lay it out oldest first, and centre it on zero.
        let count = onsetsKept
        let oldest = (onsetIndex - count + onsetHistory.count) % onsetHistory.count
        for index in 0..<count {
            onsetsInOrder[index] = onsetHistory[(oldest + index) % onsetHistory.count]
        }
        var mean: Float = 0
        vDSP_meanv(onsetsInOrder, 1, &mean, vDSP_Length(count))
        var minusMean = -mean
        var energy: Float = 0
        let firstLag = shortestLag - 1
        onsetsInOrder.withUnsafeMutableBufferPointer { onsets in
            guard let base = onsets.baseAddress else { return }
            vDSP_vsadd(base, 1, &minusMean, base, 1, vDSP_Length(count))
            vDSP_svesq(base, 1, &energy, vDSP_Length(count))
            guard energy > 1e-6 else { return }
            // How well the jumps line up with themselves, shifted by each lag. A longer
            // lag leaves fewer jumps overlapping, so each is scaled up to compare fairly.
            for lag in firstLag...(longestLag + 1) where lag < count {
                var sum: Float = 0
                vDSP_dotpr(base, 1, base + lag, 1, &sum, vDSP_Length(count - lag))
                repeatStrength[lag - firstLag] = sum / energy * Float(count) / Float(count - lag)
            }
        }
        guard energy > 1e-6 else { return nil }

        var bestLag = 0
        var bestScore: Float = 0
        let settledLag = beatsPerMinute.map { 60 / ($0 * stepSeconds) }
        for lag in shortestLag...longestLag where lag + 1 < count {
            var score = repeatStrength[lag - firstLag] * preference(forLag: lag)
            if let settledLag, abs(Double(lag) - settledLag) <= 1 {
                score *= Self.settledTempoBonus
            }
            if score > bestScore {
                bestScore = score
                bestLag = lag
            }
        }
        guard bestLag > 0 else { return nil }

        let before = repeatStrength[bestLag - 1 - firstLag]
        let at = repeatStrength[bestLag - firstLag]
        let after = repeatStrength[bestLag + 1 - firstLag]
        tempoConfidence = at
        guard at >= Self.leastTempoConfidence, at >= before, at >= after else { return nil }

        // The real gap is rarely a whole number of steps: fit a curve through the best
        // lag and its neighbours and take the top of the curve.
        let curve = before - 2 * at + after
        let nudge = curve < 0 ? Double(0.5 * (before - after) / curve) : 0
        let lagSeconds = (Double(bestLag) + nudge) * stepSeconds
        return 60 / lagSeconds
    }

    /// How likely a tempo is before listening.
    private func preference(forLag lag: Int) -> Float {
        let tempo = 60 / (Double(lag) * stepSeconds)
        let doublingsAway = log2(tempo / Self.likeliestTempo) / Self.likelyTempoSpread
        return Float(exp(-0.5 * doublingsAway * doublingsAway))
    }

    /// Believes a new tempo only once it's been measured a few times running, so one odd
    /// bar doesn't change it.
    private func settleTempo(_ measured: Double?) {
        // With no clear rhythm (a breakdown, a held note, a wall of guitars), keep the
        // tempo already settled. Only silence makes it forget.
        guard let measured else { return }

        if let current = beatsPerMinute, Self.agree(measured, current) {
            beatsPerMinute = current * 0.7 + measured * 0.3
            candidateTempo = nil
            return
        }
        // A different tempo from the settled one has to be heard clearly.
        if beatsPerMinute != nil, tempoConfidence < Self.leastConfidenceToReplace { return }
        if let candidate = candidateTempo, Self.agree(measured, candidate) {
            candidateAgreements += 1
        } else {
            candidateAgreements = 1
        }
        candidateTempo = measured

        let agreementsNeeded = beatsPerMinute == nil ? 2 : 4
        if candidateAgreements >= agreementsNeeded {
            if beatsPerMinute == nil {
                // Start the steady count from the last kick heard.
                let beatsSinceKick = Double(stepsSinceBeat) * stepSeconds * measured / 60
                beatPhase = beatsHeard > 0 ? beatsSinceKick.truncatingRemainder(dividingBy: 1) : 0
            }
            beatsPerMinute = measured
            candidateTempo = nil
        }
    }

    private static func agree(_ one: Double, _ other: Double) -> Bool {
        abs(one / other - 1) < 0.04
    }

    // MARK: The steady count

    /// Counts beats at the tempo, and leans towards each kick that lands near where a
    /// beat was expected, so the count stays in step with the drums.
    private func countSteadily(heardBeat: Bool) {
        guard let beatsPerMinute else { return }
        beatPhase += stepSeconds * beatsPerMinute / 60
        if heardBeat {
            // Positive: the count is ahead of the kick. Negative: behind it.
            let ahead = beatPhase < 0.5 ? beatPhase : beatPhase - 1
            if abs(ahead) < 0.25 {
                beatPhase -= ahead * 0.3
            }
        }
        if beatPhase >= 1 {
            beatPhase -= 1
            steadyBeats += 1
        }
    }
}
