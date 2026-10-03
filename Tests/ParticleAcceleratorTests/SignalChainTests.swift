import Foundation
import Testing

@testable import ParticleAccelerator

private func near(_ one: Float, _ other: Float, within tolerance: Float = 0.001) -> Bool {
    abs(one - other) <= tolerance
}

@Test func rangeStretchesItsLowAndHighPointsToZeroAndOne() {
    let shape = SignalShape(low: 0.2, high: 0.6)
    #expect(shape.stretchAndBend(0.1) == 0)
    #expect(shape.stretchAndBend(0.2) == 0)
    #expect(near(shape.stretchAndBend(0.4), 0.5))
    #expect(shape.stretchAndBend(0.6) == 1)
    #expect(shape.stretchAndBend(0.9) == 1)
}

@Test func aRangeWithNoWidthIsASwitch() {
    let shape = SignalShape(low: 0.5, high: 0.5)
    #expect(shape.stretchAndBend(0.49) == 0)
    #expect(shape.stretchAndBend(0.5) == 1)
}

@Test func aSteeperCurveKeepsOnlyTheStrongHits() {
    let straight = SignalShape(steepness: 1)
    let steeper = SignalShape(steepness: 2)
    #expect(near(straight.stretchAndBend(0.5), 0.5))
    #expect(near(steeper.stretchAndBend(0.5), 0.25))
    #expect(steeper.stretchAndBend(0) == 0)
    #expect(steeper.stretchAndBend(1) == 1)
}

@Test func fadeRisesAtOnceAndFallsSlowly() {
    let shape = SignalShape(riseSeconds: 0, fallSeconds: 0.5)
    #expect(shape.fade(0, towards: 1, seconds: 1.0 / 60) == 1)
    // After one fall time it has dropped to 1/e, about 0.37.
    #expect(near(shape.fade(1, towards: 0, seconds: 0.5), 0.368))
}

@Test func fadeIsTheSameAtAnyFrameRate() {
    let shape = SignalShape(riseSeconds: 0.1, fallSeconds: 0.3)
    var at60: Float = 1
    for _ in 0..<60 { at60 = shape.fade(at60, towards: 0, seconds: 1.0 / 60) }
    var at24: Float = 1
    for _ in 0..<24 { at24 = shape.fade(at24, towards: 0, seconds: 1.0 / 24) }
    #expect(near(at60, at24))
    #expect(near(at60, Float(exp(-1 / 0.3))))
}

@Test func aLiveSignalFollowsItsSourceThroughAllFourSteps() {
    var reading = SoundReading.silence
    reading.bands.kick = 0.8
    reading.bands.air = 0.1
    let chain = SignalChain(
        source: .kick, shape: SignalShape(low: 0.6, high: 1, steepness: 2, riseSeconds: 0, fallSeconds: 0.2))
    var signal = LiveSignal(chain)
    // 0.8 is halfway up the range, and the curve squares it.
    #expect(near(signal.update(reading, seconds: 1.0 / 60), 0.25))

    reading.bands.kick = 0
    let fading = signal.update(reading, seconds: 0.2)
    #expect(near(fading, 0.25 * Float(exp(-1.0)), within: 0.002))
}

@Test func everySourceReadsItsOwnPartOfTheSound() {
    var reading = SoundReading.silence
    reading.bands = BandValues(sub: 0.1, kick: 0.2, lowMids: 0.3, mids: 0.4, vocals: 0.5, air: 0.6)
    reading.loudness = 0.7
    reading.beat = 0.8
    let levels = SoundSource.allCases.map { reading.level(of: $0) }
    #expect(levels == [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8])
}

@Test func theSpectrumGoesThroughTheSameShapeBarByBar() {
    var reading = SoundReading.silence
    reading.bars[0] = 1
    reading.bars[63] = 0.5
    var spectrum = LiveSpectrum(SignalShape(steepness: 2, riseSeconds: 0, fallSeconds: 0.2))
    let bars = spectrum.update(reading, seconds: 1.0 / 60)
    #expect(bars[0] == 1)
    #expect(bars[1] == 0)
    #expect(near(bars[63], 0.25))
}

@Test func aChainCanBeSavedAndReadBack() throws {
    let chain = SignalChain(
        source: .vocals, shape: SignalShape(low: 0.1, high: 0.9, steepness: 3, riseSeconds: 0.01, fallSeconds: 0.4))
    let saved = try JSONEncoder().encode(chain)
    #expect(try JSONDecoder().decode(SignalChain.self, from: saved) == chain)
}
