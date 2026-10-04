import Foundation
import Metal
import Testing
import simd

@testable import ParticleAccelerator

// MARK: The mountains (no graphics card needed)

/// Bars from 0 to 1, as the analyser gives them.
private func bars(_ levels: [Int: Float]) -> SIMD64<Float> {
    var bars = SIMD64<Float>(repeating: 0)
    for (bar, level) in levels { bars[bar] = level }
    return bars
}

/// The mountains once they've settled on a steady sound.
private func settled(_ sound: SIMD64<Float>) -> SIMD64<Float> {
    var mountains = ParticleWave.Mountains()
    var range = SIMD64<Float>(repeating: 0)
    for _ in 0..<120 { range = mountains.update(bars: sound, seconds: 1.0 / 60) }
    return range
}

@Test func silenceIsFlat() {
    #expect(settled(SIMD64<Float>(repeating: 0)) == SIMD64<Float>(repeating: 0))
}

/// A sound that holds steady stands at this share of its height.
private let held = ParticleWave.Control.heldSound.base

@Test func oneSteadyPitchMakesATriangularMountain() {
    let range = settled(bars([30: 1]))
    // As tall as a held sound stands at the pitch, sloping evenly down to nothing two
    // and a half bars away on each side.
    #expect(abs(range[30] - held) < 0.01)
    #expect(abs(range[29] - range[31]) < 0.001)
    #expect(abs(range[31] - held * (1 - 1 / 2.5)) < 0.01)
    #expect(abs(range[32] - held * (1 - 2 / 2.5)) < 0.01)
    #expect(range[33] == 0 && range[27] == 0)
}

@Test func theHighsMakeMountainsOfTheirOwnBesideTheBass() {
    // A strong bass note, and a cymbal 16 decibels quieter (0.4 of the 40-decibel
    // range lower). Drawn as the spectrum stands, the cymbal would hardly show.
    let range = settled(bars([8: 1, 52: 0.6]))
    #expect(abs(range[8] - held) < 0.01)
    #expect(range[52] > 0.95 * held)
    // And there's a valley between them.
    #expect(range[30] == 0)
}

@Test func withinOnePartOfTheSpectrumTheStrongerPitchStandsTaller() {
    // Two pitches three bars apart, one 5 decibels quieter: half as tall.
    let range = settled(bars([30: 1, 33: 0.875]))
    #expect(abs(range[30] - held) < 0.01)
    #expect(abs(range[33] - held / 2) < 0.02)
}

@Test func faintHissDoesNotMakeMountains() {
    // 36 decibels below the song's peak: turned up only a little.
    let range = settled(bars([8: 1, 52: 0.1]))
    #expect(range[52] < 0.15)
}

@Test func aHitLeapsUpAndDropsStraightBack() {
    var mountains = ParticleWave.Mountains()
    var range = SIMD64<Float>(repeating: 0)
    for _ in 0..<3 { range = mountains.update(bars: bars([30: 1]), seconds: 1.0 / 60) }
    // A twentieth of a second in, it's nearly all the way up.
    #expect(range[30] > 0.9)
    for _ in 0..<6 { range = mountains.update(bars: SIMD64<Float>(repeating: 0), seconds: 1.0 / 60) }
    // A tenth of a second after the sound stops it's well on its way down, and two
    // tenths later it's all but gone: ready for the next beat.
    #expect(range[30] < 0.45)
    for _ in 0..<12 { range = mountains.update(bars: SIMD64<Float>(repeating: 0), seconds: 1.0 / 60) }
    #expect(range[30] < 0.08)
}

@Test func aHitStandsAboveASoundThatHasBeenHolding() {
    // A busy passage: a pitch that has been sounding for two seconds, and then a drum
    // hit 10 decibels louder in the same place.
    var mountains = ParticleWave.Mountains()
    var range = SIMD64<Float>(repeating: 0)
    for _ in 0..<120 { range = mountains.update(bars: bars([30: 0.75]), seconds: 1.0 / 60) }
    #expect(abs(range[30] - held) < 0.02)
    for _ in 0..<3 { range = mountains.update(bars: bars([30: 1]), seconds: 1.0 / 60) }
    #expect(range[30] > 0.9)
    // If the louder sound holds too, it settles back to where a held sound stands.
    for _ in 0..<120 { range = mountains.update(bars: bars([30: 1]), seconds: 1.0 / 60) }
    #expect(abs(range[30] - held) < 0.02)
}

@Test func aRepeatedHitLeapsEveryTime() {
    // A kick every half second (120 beats a minute), each a twentieth of a second long.
    var mountains = ParticleWave.Mountains()
    var tallest: [Float] = []
    var lowest: [Float] = []
    for _ in 0..<6 {
        var top: Float = 0
        for frame in 0..<30 {
            let range = mountains.update(bars: frame < 3 ? bars([10: 1]) : SIMD64<Float>(repeating: 0), seconds: 1.0 / 60)
            top = max(top, range[10])
            if frame == 29 { lowest.append(range[10]) }
        }
        tallest.append(top)
    }
    // Every kick reaches nearly full height, and the mountain is flat again before the
    // next one.
    #expect(tallest.allSatisfy { $0 > 0.9 }, "\(tallest)")
    #expect(lowest.allSatisfy { $0 < 0.03 }, "\(lowest)")
}

@Test func thePartsOfTheSpectrumForgetOldPeaks() {
    // A loud passage, then a quieter one 12 decibels down in the same place. After a
    // few seconds the quieter one stands as tall as the loud one did.
    var mountains = ParticleWave.Mountains()
    for _ in 0..<120 { _ = mountains.update(bars: bars([30: 1]), seconds: 1.0 / 60) }
    var range = SIMD64<Float>(repeating: 0)
    for _ in 0..<30 { range = mountains.update(bars: bars([30: 0.7]), seconds: 1.0 / 60) }
    #expect(range[30] < 0.2)
    for _ in 0..<300 { range = mountains.update(bars: bars([30: 0.7]), seconds: 1.0 / 60) }
    #expect(range[30] > 0.95 * held)
}

// MARK: The bands' sections and colours

@Test func everyBarOfTheSpectrumBelongsToABand() {
    // The band changes where the band's pitches begin: 60, 150, 500, 2,000 and 6,000 Hz.
    #expect(Band.of(bar: 0) == .sub && Band.of(bar: 6) == .sub)
    #expect(Band.of(bar: 7) == .kick && Band.of(bar: 15) == .kick)
    #expect(Band.of(bar: 16) == .lowMids && Band.of(bar: 28) == .lowMids)
    #expect(Band.of(bar: 29) == .mids && Band.of(bar: 42) == .mids)
    #expect(Band.of(bar: 43) == .vocals && Band.of(bar: 53) == .vocals)
    #expect(Band.of(bar: 54) == .air && Band.of(bar: 63) == .air)
}

@Test func everyBandHasAColourOfItsOwn() {
    // No two are close: each differs from every other by a good step in at least one
    // of red, green and blue.
    for band in Band.allCases {
        for other in Band.allCases where other != band {
            let difference = simd_abs(band.colour - other.colour)
            #expect(difference.max() > 0.25, "\(band) and \(other)")
        }
        // Light is the same colour, darker in number.
        #expect(band.light.max() <= band.colour.max())
    }
    // The shaders are given the five places where one band ends and the next begins.
    #expect(ParticleWave.bandsSource.contains("waveBandEnds[5]"))
    // And all six colours, as light, each frame.
    var uniforms = StageUniforms()
    uniforms.setBandLight(from: ControlValues(), visual: 3, at: 0)
    for band in Band.allCases {
        #expect(uniforms.bandLight[band.rawValue * 4] == band.light.x)
        #expect(uniforms.bandLight[band.rawValue * 4 + 2] == band.light.z)
    }
}

// MARK: The sparks

@Test func theSparksStartTheSameEveryTimeAndSpreadAlongTheLine() {
    let sparks = ParticleWave.startingSparks(count: 10_000)
    #expect(sparks.count == 10_000)
    #expect(MemoryLayout<ParticleWave.Spark>.stride == 48)
    // On the line, spread right across it, with ages and natures all through 0…1.
    #expect(sparks.allSatisfy { $0.position.y == 0 && $0.position.w >= 0 && $0.position.w < 1 })
    #expect(sparks.allSatisfy { $0.nature.w >= 0 && $0.nature.w < 1 })
    let left = sparks.filter { $0.position.x < 0 }.count
    #expect(abs(left - 5_000) < 100)
    #expect(Set(sparks.map { $0.nature.w }).count > 9_990)
    #expect(ParticleWave.startingSparks(count: 100).map(\.position) == sparks.prefix(100).map(\.position))
}

// MARK: The picture (needs a graphics card)

@Test(.enabled(if: hasGraphicsCard, noGraphicsCard))
func inSilenceThereIsALineAcrossTheMiddleAndLittleElse() throws {
    let stage = try TestStage()
    stage.draw(frames: 180, reading: .silence)
    let frame = stage.lastFrame()
    let rows = frame.rows

    // The brightest row is the line, in the middle of the picture.
    let brightest = try #require(rows.indices.max { rows[$0] < rows[$1] })
    #expect(abs(Double(brightest) / Double(frame.height) - 0.5) < 0.06)
    #expect(rows[brightest] > 0.2)
    // Well above and below it there's only the background, a very dark blue.
    #expect(frame.brightness(left: 0, top: 0, right: 1, bottom: 0.25) < 0.05)
    #expect(frame.brightness(left: 0, top: 0.75, right: 1, bottom: 1) < 0.05)
    #expect(rows[brightest] > 5 * frame.brightness(left: 0, top: 0, right: 1, bottom: 0.25))
}

@Test(.enabled(if: hasGraphicsCard, noGraphicsCard))
func thePeaksRiseWhereTheMusicIs() throws {
    let stage = try TestStage()
    // Bars 12 to 20 are loud: about a quarter of the way along, on the bass side.
    stage.draw(frames: 240, reading: readingWithAPeak())
    let frame = stage.lastFrame()
    // What the bare background reads, to measure the light against.
    let background = frame.brightness(left: 0, top: 0, right: 1, bottom: 0.08)
    func light(left: Double, top: Double, right: Double, bottom: Double) -> Double {
        frame.brightness(left: left, top: top, right: right, bottom: bottom) - background
    }

    // Above the line: far more light over the loud bars than over the quiet highs.
    let overThePeak = light(left: 0.17, top: 0.18, right: 0.33, bottom: 0.42)
    let overTheQuiet = light(left: 0.70, top: 0.18, right: 0.86, bottom: 0.42)
    #expect(overThePeak > 0.08)
    #expect(overThePeak > overTheQuiet * 3, "peak \(overThePeak), quiet \(overTheQuiet)")

    // The reflection below is there, and dimmer than the peak above.
    let underThePeak = light(left: 0.17, top: 0.58, right: 0.33, bottom: 0.82)
    let underTheQuiet = light(left: 0.70, top: 0.58, right: 0.86, bottom: 0.82)
    #expect(underThePeak > underTheQuiet * 2, "peak \(underThePeak), quiet \(underTheQuiet)")
    #expect(underThePeak < overThePeak * 0.8)
}

@Test(.enabled(if: hasGraphicsCard, noGraphicsCard))
func eachSectionOfTheLineIsBrighterWhenItsOwnBandIsLouder() throws {
    // The line itself is already near the brightest a screen can show, so the light
    // is measured in its glow: just above and below it, in sections of the spectrum
    // where there are no peaks.
    func glowBesideTheLine(vocals: Float) throws -> (vocals: Double, air: Double) {
        let stage = try TestStage()
        var reading = readingWithAPeak()
        reading.bands.vocals = vocals
        stage.draw(frames: 180, reading: reading)
        let frame = stage.lastFrame()
        func glow(left: Double, right: Double) -> Double {
            frame.brightness(left: left, top: 0.465, right: right, bottom: 0.49)
                + frame.brightness(left: left, top: 0.51, right: right, bottom: 0.535)
        }
        return (glow(left: 0.70, right: 0.82), glow(left: 0.90, right: 0.98))
    }
    let quiet = try glowBesideTheLine(vocals: 0)
    let loud = try glowBesideTheLine(vocals: 1)
    #expect(loud.vocals > quiet.vocals * 1.15, "quiet \(quiet), loud \(loud)")
    // The section next to it, whose band hasn't changed, stays as it was.
    #expect(loud.air < quiet.air * 1.1, "quiet \(quiet), loud \(loud)")
}

@Test(.enabled(if: hasGraphicsCard, noGraphicsCard))
func eachSectionIsItsBandsColour() throws {
    // Music right across the spectrum.
    let stage = try TestStage()
    var reading = SoundReading.silence
    reading.bars = SIMD64<Float>(repeating: 1)
    reading.loudness = 0.8
    reading.seconds = 10
    stage.draw(frames: 240, reading: reading)
    let frame = stage.lastFrame()

    // The middle of each band's section, above the line: of the six bands' colours,
    // the one it's nearest to is its own.
    let middles: [(Band, Double)] = [
        (.sub, 0.05), (.kick, 0.18), (.lowMids, 0.35), (.mids, 0.56), (.vocals, 0.76), (.air, 0.93),
    ]
    for (band, middle) in middles {
        let seen = frame.colour(left: middle - 0.03, top: 0.30, right: middle + 0.03, bottom: 0.46)
        let hue = simd_normalize(SIMD3(Float(seen.red), Float(seen.green), Float(seen.blue)))
        let nearest = Band.allCases.max {
            simd_dot(hue, simd_normalize($0.colour)) < simd_dot(hue, simd_normalize($1.colour))
        }
        #expect(nearest == band, "\(band): saw \(seen)")
    }
    // And the bass end is red where the top end is green.
    let bass = frame.colour(left: 0.02, top: 0.30, right: 0.08, bottom: 0.46)
    let top = frame.colour(left: 0.90, top: 0.30, right: 0.96, bottom: 0.46)
    #expect(bass.red > bass.green * 1.5 && top.green > top.red * 1.5, "bass \(bass), top \(top)")
}

@Test(.enabled(if: hasGraphicsCard, noGraphicsCard))
func moreSparksMakeAFinerPictureNotABrighterOne() throws {
    // Low quality and High quality should be about as bright as each other.
    func light(sparks: Int) throws -> Double {
        let stage = try TestStage(particleCount: sparks)
        stage.draw(frames: 240, reading: readingWithAPeak())
        return stage.lastFrame().brightness(left: 0.1, top: 0.15, right: 0.4, bottom: 0.45)
    }
    let few = try light(sparks: 20_000)
    let many = try light(sparks: 80_000)
    #expect(abs(many / few - 1) < 0.25, "few \(few), many \(many)")
}

@Test(.enabled(if: hasGraphicsCard, noGraphicsCard))
func theSparkCountAndPictureSizeCanChangeWhileItRuns() throws {
    let stage = try TestStage(width: 320, height: 180, particleCount: 5_000)
    stage.draw(frames: 5, reading: readingWithAPeak())
    try stage.renderer.setTier(QualityTier(particleCount: 9_000, drawingWidth: 320, drawingHeight: 180))
    #expect(stage.renderer.tier.particleCount == 9_000)
    let size = try stage.renderer.resize(forViewPixels: CGSize(width: 200, height: 100))
    #expect(size.width == 200 && size.height == 100)
    stage.draw(frames: 5, reading: readingWithAPeak())
    #expect(stage.renderer.timer.summary.framesPerSecond > 0)
}

@Test(.enabled(if: hasGraphicsCard, noGraphicsCard))
func aVisualThatIsntBuiltIsRefusedPlainly() throws {
    let device = try #require(graphicsCard)
    let error = #expect(throws: StageProblem.self) {
        try StageRenderer(device: device, visualNumber: 2, tier: .low, screenFormat: .bgra8Unorm)
    }
    #expect(error?.message == "Visualizer 2 isn't built yet.")
}
