import Foundation
import Metal
import Testing

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

@Test func oneStrongPitchMakesATriangularMountain() {
    let range = settled(bars([30: 1]))
    // Full height at the pitch, sloping evenly down to nothing three and a half bars
    // away on each side.
    #expect(abs(range[30] - 1) < 0.01)
    #expect(abs(range[29] - range[31]) < 0.001)
    #expect(abs(range[31] - (1 - 1 / 3.5)) < 0.01)
    #expect(abs(range[33] - (1 - 3 / 3.5)) < 0.01)
    #expect(range[34] == 0 && range[26] == 0)
    #expect(range[31] > range[32] && range[32] > range[33])
}

@Test func theHighsMakeMountainsOfTheirOwnBesideTheBass() {
    // A strong bass note, and a cymbal 16 decibels quieter (0.4 of the 40-decibel
    // range lower). Drawn as the spectrum stands, the cymbal would hardly show.
    let range = settled(bars([8: 1, 52: 0.6]))
    #expect(abs(range[8] - 1) < 0.01)
    #expect(range[52] > 0.95)
    // And there's a valley between them.
    #expect(range[30] == 0)
}

@Test func withinOnePartOfTheSpectrumTheStrongerPitchStandsTaller() {
    // Two pitches three bars apart, one 6 decibels quieter: half as tall.
    let range = settled(bars([30: 1, 33: 0.85]))
    #expect(abs(range[30] - 1) < 0.01)
    #expect(abs(range[33] - 0.5) < 0.03)
}

@Test func faintHissDoesNotMakeMountains() {
    // 36 decibels below the song's peak: turned up only a little.
    let range = settled(bars([8: 1, 52: 0.1]))
    #expect(range[52] < 0.3)
}

@Test func aMountainClimbsAtOnceAndSinksSlowly() {
    var mountains = ParticleWave.Mountains()
    var range = SIMD64<Float>(repeating: 0)
    for _ in 0..<6 { range = mountains.update(bars: bars([30: 1]), seconds: 1.0 / 60) }
    // A tenth of a second in, it's nearly all the way up.
    #expect(range[30] > 0.9)
    for _ in 0..<6 { range = mountains.update(bars: SIMD64<Float>(repeating: 0), seconds: 1.0 / 60) }
    // A tenth of a second after the sound stops, it has only sunk part of the way.
    #expect(range[30] > 0.5 && range[30] < 0.8)
}

@Test func thePartsOfTheSpectrumForgetOldPeaks() {
    // A loud passage, then a quieter one 12 decibels down in the same place. After a
    // few seconds the quieter one stands at full height again.
    var mountains = ParticleWave.Mountains()
    for _ in 0..<120 { _ = mountains.update(bars: bars([30: 1]), seconds: 1.0 / 60) }
    var range = SIMD64<Float>(repeating: 0)
    for _ in 0..<30 { range = mountains.update(bars: bars([30: 0.7]), seconds: 1.0 / 60) }
    #expect(range[30] < 0.45)
    for _ in 0..<300 { range = mountains.update(bars: bars([30: 0.7]), seconds: 1.0 / 60) }
    #expect(range[30] > 0.95)
}

// MARK: The sparks

@Test func theSparksStartTheSameEveryTimeAndSpreadAlongTheLine() {
    let sparks = ParticleWave.startingSparks(count: 10_000)
    #expect(sparks.count == 10_000)
    #expect(MemoryLayout<ParticleWave.Spark>.stride == 32)
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
func theLineIsBrighterWhenTheMusicIsLouder() throws {
    // The line itself is already near the brightest a screen can show, so the light
    // is measured in its glow: just above and below it, on the side of the spectrum
    // where there are no peaks.
    func glowBesideTheLine(loudness: Float) throws -> Double {
        let stage = try TestStage()
        stage.draw(frames: 180, reading: readingWithAPeak(loudness: loudness))
        let frame = stage.lastFrame()
        return frame.brightness(left: 0.65, top: 0.41, right: 0.9, bottom: 0.47)
            + frame.brightness(left: 0.65, top: 0.53, right: 0.9, bottom: 0.59)
    }
    let quiet = try glowBesideTheLine(loudness: 0)
    let loud = try glowBesideTheLine(loudness: 1)
    #expect(loud > quiet * 1.25, "quiet \(quiet), loud \(loud)")
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
