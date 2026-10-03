import Accelerate
import Foundation

/// Measures the sound in a `SampleRing` and gives a `SoundReading`: the spectrum, the
/// named bands, the loudness and the beat.
///
/// It works through the sound in fixed steps (512 samples, about 86 a second), however
/// often `update` is called, so the same song gives the same readings at any frame
/// rate. Each step it looks at the last 2,048 samples through a Hann window and splits
/// them into pitches with a fast Fourier transform (FFT).
///
/// Call `update` from one thread only (whichever draws).
final class SoundAnalyser {
    static let barCount = 64
    static let lowestBarHz: Float = 30
    static let highestBarHz: Float = 16_000
    /// Bars are lifted by this many decibels for each doubling of pitch. Music has far
    /// more energy in the bass, and without the lift the right half would hardly move.
    static let barLiftPerOctave: Float = 3
    /// A bar this many decibels below the recent peak reads 0 (40 is a hundredth as
    /// strong).
    static let barRange: Float = 40
    /// A band, or the loudness, this many decibels below its recent peak reads 0 (20 is
    /// a tenth as strong). Songs are mastered so evenly that a wider range hardly moves.
    static let levelRange: Float = 20
    /// Auto-gain never turns up further than this many decibels below full volume, so
    /// silence and hiss stay at 0.
    static let quietestPeak: Float = -60
    /// A band is never turned up to more than this far below the whole sound's peak, so
    /// a band with nothing in it stays low instead of showing its hiss.
    static let mostBandBoost: Float = 30

    let ring: SampleRing
    /// The size of the stretch of sound each step looks at: 2,048 samples at ordinary
    /// rates, more at 96 kHz and above so it's the same length of time.
    let windowSize: Int
    let stepSize: Int
    let stepSeconds: Double

    private(set) var reading = SoundReading.silence
    /// The ring's sample number that the analyser has measured up to.
    private var measuredUpTo: Int64 = 0

    // Working memory, made once.
    private let halfSize: Int
    private let log2Size: vDSP_Length
    private let fft: FFTSetup
    private let hannWindow: UnsafeMutablePointer<Float>
    private let samples: UnsafeMutablePointer<Float>
    private let real: UnsafeMutablePointer<Float>
    private let imaginary: UnsafeMutablePointer<Float>
    /// How strong each pitch is: 1 is a full-volume sine wave.
    private let power: UnsafeMutablePointer<Float>
    /// The strength in each bar, kept from drawing the bars to measuring the beat.
    private var barPower = [Float](repeating: 0, count: SoundAnalyser.barCount)
    /// Last step's values, to see how much the sound has jumped since.
    private var barSqueezedBefore = [Float](repeating: 0, count: SoundAnalyser.barCount)
    private var kickStrengthBefore: [Float]

    /// Where one bar sits among the FFT's pitches ("bins").
    private struct Bar {
        /// The bins inside the bar, or an empty range for a bass bar narrower than a bin.
        var bins: Range<Int>
        /// The bar's middle, as a bin number with a fraction.
        var centre: Float
        var lift: Float
        /// False for a bar above the highest pitch the sound can hold (half its sample
        /// rate), which only happens with low-quality files. It always reads 0.
        var isInReach: Bool
    }
    private let bars: [Bar]
    private let bandBins: [Range<Int>]

    private var barsPeak: RecentPeak
    private var loudnessPeak: RecentPeak
    private var bandPeaks: [RecentPeak]
    private let beats: BeatTracker

    init(ring: SampleRing) {
        self.ring = ring
        let rate = ring.sampleRate
        windowSize = rate > 100_000 ? 8_192 : rate > 50_000 ? 4_096 : 2_048
        stepSize = windowSize / 4
        stepSeconds = Double(stepSize) / rate
        halfSize = windowSize / 2
        log2Size = vDSP_Length(windowSize.trailingZeroBitCount)

        guard let setup = vDSP_create_fftsetup(log2Size, FFTRadix(kFFTRadix2)) else {
            fatalError("Accelerate couldn't set up a \(windowSize)-sample FFT.")
        }
        fft = setup
        hannWindow = Self.memory(windowSize)
        vDSP_hann_window(hannWindow, vDSP_Length(windowSize), Int32(vDSP_HANN_DENORM))
        samples = Self.memory(windowSize)
        real = Self.memory(halfSize)
        imaginary = Self.memory(halfSize)
        power = Self.memory(halfSize)

        let hzPerBin = Float(rate) / Float(windowSize)
        let topBin = halfSize - 1
        func firstBin(atOrAbove hz: Float) -> Int {
            min(topBin, max(1, Int((hz / hzPerBin).rounded(.up))))
        }

        let barRatio = Self.highestBarHz / Self.lowestBarHz
        bars = (0..<Self.barCount).map { index in
            let low = Self.lowestBarHz * pow(barRatio, Float(index) / Float(Self.barCount))
            let high = Self.lowestBarHz * pow(barRatio, Float(index + 1) / Float(Self.barCount))
            let middle = (low * high).squareRoot()
            return Bar(
                bins: firstBin(atOrAbove: low)..<max(firstBin(atOrAbove: low), firstBin(atOrAbove: high)),
                centre: min(Float(topBin), middle / hzPerBin),
                lift: Self.barLiftPerOctave * log2(middle / 1_000),
                isInReach: low < Float(rate) / 2)
        }
        bandBins = Band.allCases.map { band in
            let first = firstBin(atOrAbove: band.frequencies.lowerBound)
            return first..<max(first + 1, firstBin(atOrAbove: band.frequencies.upperBound))
        }
        kickStrengthBefore = Array(repeating: 0, count: bandBins[Band.kick.rawValue].count)

        let peak = RecentPeak(stepSeconds: stepSeconds, floor: Self.quietestPeak)
        barsPeak = peak
        loudnessPeak = peak
        bandPeaks = Array(repeating: peak, count: Band.allCases.count)
        beats = BeatTracker(stepSeconds: stepSeconds)
    }

    deinit {
        vDSP_destroy_fftsetup(fft)
        for buffer in [hannWindow, samples, real, imaginary, power] {
            buffer.deallocate()
        }
    }

    private static func memory(_ count: Int) -> UnsafeMutablePointer<Float> {
        let buffer = UnsafeMutablePointer<Float>.allocate(capacity: count)
        buffer.initialize(repeating: 0, count: count)
        return buffer
    }

    // MARK: Each frame

    /// Measures any sound that has arrived since the last call, and returns the newest
    /// reading.
    ///
    /// - Parameter limit: the number of the last sample to measure, for a source that
    ///   hands sound over before it's heard. Left out, everything in the ring is
    ///   measured.
    func update(upTo limit: Int64 = .max) -> SoundReading {
        let written = min(limit, ring.totalWritten)
        // A long way behind (the window was hidden, say): skip to the newest sound
        // rather than work through sound nobody saw.
        if written - measuredUpTo > Self.furthestBehind(ring.sampleRate) {
            measuredUpTo = written - Int64(stepSize)
        }
        while measuredUpTo + Int64(stepSize) <= written {
            measuredUpTo += Int64(stepSize)
            if ring.read(endingAt: measuredUpTo, count: windowSize, into: samples) {
                measureStep()
            }
        }
        return reading
    }

    /// Two seconds of sound: further behind than this, it skips ahead.
    private static func furthestBehind(_ sampleRate: Double) -> Int64 {
        min(Int64(2 * sampleRate), Int64(SampleRing.capacity / 2))
    }

    // MARK: Each step

    private func measureStep() {
        // Loudness is the "root mean square" of the samples: their average strength.
        var strength: Float = 0
        vDSP_rmsqv(samples, 1, &strength, vDSP_Length(windowSize))
        let loudnessDecibels = Self.decibels(power: strength * strength)

        findPower()

        reading.seconds = Double(measuredUpTo) / ring.sampleRate
        reading.loudnessDecibels = loudnessDecibels
        let loudnessPeakNow = loudnessPeak.add(loudnessDecibels)
        reading.loudness = Self.level(loudnessDecibels, peak: loudnessPeakNow, range: Self.levelRange)

        for band in Band.allCases {
            let bins = bandBins[band.rawValue]
            var sum: Float = 0
            vDSP_sve(power + bins.lowerBound, 1, &sum, vDSP_Length(bins.count))
            // A single pitch spreads over about 1.5 bins through a Hann window; dividing
            // by that makes a lone sine wave read its true loudness.
            let decibels = Self.decibels(power: sum / 1.5)
            let ownPeak = bandPeaks[band.rawValue].add(decibels)
            let peak = max(ownPeak, loudnessPeakNow - Self.mostBandBoost)
            reading.bandDecibels[band] = decibels
            reading.bands[band] = Self.level(decibels, peak: peak, range: Self.levelRange)
        }

        measureBars()
        measureBeat(
            loudnessPeak: loudnessPeakNow, isSilent: loudnessDecibels < Self.quietestPeak)
    }

    /// Fills `power` with how strong each pitch is in the latest window of sound.
    private func findPower() {
        vDSP_vmul(samples, 1, hannWindow, 1, samples, 1, vDSP_Length(windowSize))
        var split = DSPSplitComplex(realp: real, imagp: imaginary)
        samples.withMemoryRebound(to: DSPComplex.self, capacity: halfSize) { pairs in
            vDSP_ctoz(pairs, 2, &split, 1, vDSP_Length(halfSize))
        }
        vDSP_fft_zrip(fft, &split, 1, log2Size, FFTDirection(FFT_FORWARD))
        // vDSP keeps the very highest pitch in this slot; it isn't part of bin 0.
        imaginary[0] = 0
        vDSP_zvmags(&split, 1, power, 1, vDSP_Length(halfSize))
        // vDSP's answer for a full-volume sine wave is windowSize / 2. Scale it to 1.
        var scale = 4 / (Float(windowSize) * Float(windowSize))
        vDSP_vsmul(power, 1, &scale, power, 1, vDSP_Length(halfSize))
        // Bin 0 is any steady offset in the signal, not a sound.
        power[0] = 0
    }

    private func measureBars() {
        var decibels = SIMD64<Float>(repeating: SoundReading.silenceDecibels)
        var loudestBar = SoundReading.silenceDecibels
        for (index, bar) in bars.enumerated() {
            var barPower: Float = 0
            if !bar.isInReach {
                barPower = 0
            } else if bar.bins.isEmpty {
                // Narrower than one bin: read between the two bins either side, so the
                // bass bars rise and fall smoothly instead of in blocks.
                let below = min(halfSize - 2, Int(bar.centre))
                let fraction = bar.centre - Float(below)
                barPower = power[below] + (power[below + 1] - power[below]) * fraction
            } else {
                vDSP_maxv(power + bar.bins.lowerBound, 1, &barPower, vDSP_Length(bar.bins.count))
            }
            self.barPower[index] = barPower
            decibels[index] = Self.decibels(power: barPower) + bar.lift
            loudestBar = max(loudestBar, decibels[index])
        }
        let peak = barsPeak.add(loudestBar)
        for index in 0..<Self.barCount {
            reading.bars[index] = Self.level(decibels[index], peak: peak, range: Self.barRange)
        }
    }

    /// Measures how much the sound just jumped, for the beat tracker.
    private func measureBeat(loudnessPeak: Float, isSilent: Bool) {
        // Everything is measured against how loud the song has been lately, so a kick
        // stands out as much in a quiet song as in a loud one.
        let gain = 1 / pow(10, loudnessPeak / 20)

        // For hearing each kick: how much stronger the kick band's pitches just got.
        // Plain strength, so a kick drum stands well clear of a softer bass note.
        var kickJump: Float = 0
        let kickBins = bandBins[Band.kick.rawValue]
        for (index, bin) in kickBins.enumerated() {
            let strength = power[bin].squareRoot() * gain
            kickJump += max(0, strength - kickStrengthBefore[index])
            kickStrengthBefore[index] = strength
        }

        // For the tempo: how much every bar just rose. The bars are spread evenly from
        // bass to highs, so a kick counts as much as a snare, and each is squeezed with
        // a logarithm so quiet instruments count too.
        var wholeJump: Float = 0
        for index in 0..<Self.barCount {
            let squeezed = log1p(100 * barPower[index].squareRoot() * gain)
            wholeJump += max(0, squeezed - barSqueezedBefore[index])
            barSqueezedBefore[index] = squeezed
        }

        beats.add(
            kickFlux: kickJump, onsetStrength: wholeJump, isSilent: isSilent,
            isTooFaint: loudnessPeak <= Self.quietestPeak)
        reading.beat = beats.beat
        reading.beatsHeard = beats.beatsHeard
        reading.beatsPerMinute = beats.beatsPerMinute
        reading.beatPhase = beats.beatPhase
        reading.steadyBeats = beats.steadyBeats
    }

    // MARK: Decibels and levels

    private static func decibels(power: Float) -> Float {
        max(SoundReading.silenceDecibels, 10 * log10(max(power, 1e-20)))
    }

    /// Where `decibels` sits between `range` below the peak (0) and the peak itself (1).
    private static func level(_ decibels: Float, peak: Float, range: Float) -> Float {
        min(1, max(0, (decibels - peak) / range + 1))
    }
}
