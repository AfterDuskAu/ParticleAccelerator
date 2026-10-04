import Foundation
import Metal
import Testing
import simd

@testable import ParticleAccelerator

// Tests for every visual at once, and for the base designs added on 2026-10-04:
// Tendrils (4), Fountain (5) and Starburst (6). Corona (7) and Jets (8) have a file of
// their own (`BandVisualsTests`).

/// A reading with music right across the spectrum.
private func music(loudness: Float = 0.8, beatsHeard: Int = 0, beat: Float = 0) -> SoundReading {
    var reading = SoundReading.silence
    reading.bars = SIMD64<Float>(repeating: 0.8)
    reading.loudness = loudness
    reading.bands = BandValues(sub: 0.7, kick: 0.7, lowMids: 0.7, mids: 0.7, vocals: 0.7, air: 0.7)
    reading.beat = beat
    reading.beatsHeard = beatsHeard
    reading.seconds = 10
    return reading
}

private let visualsWithSomethingToShow = [3, 4, 5, 6, 7, 8]

// MARK: Every visual

@Test func theParticleVisualsCanBeShownAndTheOthersAreStillToCome() {
    #expect(Visuals.all.filter(\.canBeShown).map(\.number) == visualsWithSomethingToShow)
    #expect(Set(StageRenderer.visuals.map { $0.number }) == Set(visualsWithSomethingToShow))
    for number in visualsWithSomethingToShow {
        #expect(!StageRenderer.controls(ofVisual: number).isEmpty)
    }
}

@Test(.enabled(if: hasGraphicsCard, noGraphicsCard), arguments: visualsWithSomethingToShow)
func everyVisualDrawsInSilenceAndIsBrighterWithMusic(visual: Int) throws {
    // At its base, and at its standard, which is what a person first sees.
    for atItsStandard in [false, true] {
        let quiet = try TestStage(visual: visual)
        if atItsStandard { quiet.renderer.values = ControlValues() }
        quiet.draw(frames: 200, reading: .silence)
        let silence = quiet.lastFrame().brightness(left: 0, top: 0, right: 1, bottom: 1)

        let loud = try TestStage(visual: visual)
        if atItsStandard { loud.renderer.values = ControlValues() }
        for frame in 0..<300 {
            // A kick every half second.
            loud.draw(frames: 1, reading: music(beatsHeard: frame / 30, beat: frame % 30 < 6 ? 1 : 0))
        }
        let playing = loud.lastFrame().brightness(left: 0, top: 0, right: 1, bottom: 1)

        // Neither is black, and neither has gone wrong in its sums (which leaves a
        // picture black or solid white).
        let which = "Visualizer \(visual) at its \(atItsStandard ? "standard" : "base")"
        #expect(silence > 0.0003 && silence < 0.5, "\(which) in silence: \(silence)")
        #expect(playing > silence * 1.3 && playing < 0.9, "\(which): silence \(silence), music \(playing)")
    }
}

@Test(.enabled(if: hasGraphicsCard, noGraphicsCard), arguments: visualsWithSomethingToShow)
func everyVisualStillDrawsWithEveryControlAtEitherEnd(visual: Int) throws {
    for atTheTop in [false, true] {
        let stage = try TestStage(visual: visual)
        var values = baseValues(ofVisual: visual)
        for control in StageRenderer.controls(ofVisual: visual) {
            values.set(atTheTop ? control.range.upperBound : control.range.lowerBound, for: control)
        }
        stage.renderer.values = values
        for frame in 0..<240 {
            stage.draw(frames: 1, reading: music(beatsHeard: frame / 30, beat: frame % 30 < 6 ? 1 : 0))
        }
        // Something is drawn, and the sums haven't gone wrong (which leaves a picture
        // black or solid white). With every control at the bottom a visual may be
        // small and dim, so it's the brightest pixel that's looked for.
        let frame = stage.lastFrame()
        let light = frame.brightness(left: 0, top: 0, right: 1, bottom: 1)
        let which = "Visualizer \(visual) at the \(atTheTop ? "top" : "bottom")"
        #expect(frame.brightestPixel > 0.04, "\(which): brightest pixel \(frame.brightestPixel)")
        #expect(light < 0.995, "\(which): \(light)")
    }
}

@Test(.enabled(if: hasGraphicsCard, noGraphicsCard), arguments: visualsWithSomethingToShow)
func everyVisualCanChangeItsSparkCountAndPictureSizeWhileItRuns(visual: Int) throws {
    let stage = try TestStage(width: 320, height: 180, particleCount: 5_000, visual: visual)
    stage.draw(frames: 20, reading: music())
    try stage.renderer.setTier(QualityTier(particleCount: 9_000, drawingWidth: 320, drawingHeight: 180))
    #expect(stage.renderer.tier.particleCount == 9_000)
    let size = try stage.renderer.resize(forViewPixels: CGSize(width: 200, height: 100))
    #expect(size.width == 200 && size.height == 100)
    stage.draw(frames: 20, reading: music())
    #expect(stage.renderer.timer.summary.framesPerSecond > 0)
}

@Test(.enabled(if: hasGraphicsCard, noGraphicsCard), arguments: visualsWithSomethingToShow)
func aPickedColourShowsInEveryVisual(visual: Int) throws {
    // Every band given the same colour: the whole picture leans that way.
    func leaning(_ colour: SIMD3<Float>) throws -> (red: Double, green: Double, blue: Double) {
        let stage = try TestStage(visual: visual)
        var values = baseValues(ofVisual: visual)
        for band in Band.allCases { values.setColour(colour, for: band, in: visual) }
        stage.renderer.values = values
        for frame in 0..<300 {
            stage.draw(frames: 1, reading: music(beatsHeard: frame / 30, beat: frame % 30 < 6 ? 1 : 0))
        }
        return stage.lastFrame().colour(left: 0, top: 0, right: 1, bottom: 1)
    }
    let red = try leaning(SIMD3(1, 0.05, 0.05))
    let green = try leaning(SIMD3(0.05, 1, 0.05))
    #expect(red.red > red.green * 1.15, "Visualizer \(visual) in red: \(red)")
    #expect(green.green > green.red * 1.15, "Visualizer \(visual) in green: \(green)")
}

// MARK: Visualizer 5, Fountain

@Test(.enabled(if: hasGraphicsCard, noGraphicsCard))
func theFountainRisesFromTheBottomMiddle() throws {
    let stage = try TestStage(visual: 5)
    stage.draw(frames: 300, reading: music())
    let frame = stage.lastFrame()
    // The mouth is near the bottom, in the middle: by far the brightest place.
    let mouth = frame.brightness(left: 0.46, top: 0.82, right: 0.54, bottom: 0.94)
    let farCorner = frame.brightness(left: 0, top: 0, right: 0.12, bottom: 0.2)
    #expect(mouth > 0.4, "mouth \(mouth)")
    #expect(mouth > farCorner * 10, "mouth \(mouth), corner \(farCorner)")
    // The spray is above it, and there's more of it in the middle than at the sides.
    let above = frame.brightness(left: 0.4, top: 0.25, right: 0.6, bottom: 0.6)
    let beside = frame.brightness(left: 0.02, top: 0.25, right: 0.22, bottom: 0.6)
    #expect(above > beside * 2.5, "above \(above), beside \(beside)")
}

@Test(.enabled(if: hasGraphicsCard, noGraphicsCard))
func theLouderTheSongTheHigherTheFountain() throws {
    func lightHighUp(loudness: Float) throws -> Double {
        let stage = try TestStage(visual: 5)
        stage.draw(frames: 300, reading: music(loudness: loudness))
        return stage.lastFrame().brightness(left: 0.3, top: 0.05, right: 0.7, bottom: 0.3)
    }
    let quiet = try lightHighUp(loudness: 0.2)
    let loud = try lightHighUp(loudness: 1)
    #expect(loud > quiet * 3, "quiet \(quiet), loud \(loud)")
}

@Test(.enabled(if: hasGraphicsCard, noGraphicsCard))
func theFountainsColoursFollowTheBands() throws {
    // Only the air band playing: most of the sparks are its colour, green. Only the
    // sub: orange.
    func spray(_ bands: BandValues) throws -> (red: Double, green: Double, blue: Double) {
        let stage = try TestStage(visual: 5)
        var reading = music()
        reading.bands = bands
        stage.draw(frames: 300, reading: reading)
        // Beside the white-hot jet, where the sparks have taken their colours.
        return stage.lastFrame().colour(left: 0.25, top: 0.2, right: 0.44, bottom: 0.65)
    }
    let highs = try spray(BandValues(air: 1))
    let bass = try spray(BandValues(sub: 1))
    #expect(highs.green > highs.red * 1.1, "highs \(highs)")
    #expect(bass.red > bass.green * 1.2 && bass.red > bass.blue * 1.2, "bass \(bass)")
}

@Test func theFountainsSparksAllStartWaitingAtTheMouth() {
    let sparks = Fountain.startingSparks(count: 1_000)
    #expect(MemoryLayout<Fountain.Spark>.stride == 64)
    #expect(sparks.allSatisfy { $0.position.w >= 1 && $0.nature.w >= 0 && $0.nature.w < 1 })
    #expect(Set(sparks.map(\.nature.w)).count > 990)
}

// MARK: Visualizer 6, Starburst

/// How far out the sparks are, on average: each pixel's distance from the middle of
/// the picture (as a share of its height), weighted by how bright it is. The glow at
/// the very centre is left out.
private func averageDistanceOfTheLight(in frame: Frame) -> Double {
    var total = 0.0
    var light = 0.0
    for y in stride(from: 0, to: frame.height, by: 2) {
        for x in stride(from: 0, to: frame.width, by: 2) {
            let across = Double(x - frame.width / 2) / Double(frame.height)
            let down = Double(y - frame.height / 2) / Double(frame.height)
            let distance = (across * across + down * down).squareRoot()
            guard distance > 0.12 else { continue }
            let bright = frame.brightness(x: x, y: y)
            total += bright * distance
            light += bright
        }
    }
    return total / max(light, 1e-9)
}

@Test(.enabled(if: hasGraphicsCard, noGraphicsCard))
func theStarburstFiresAllTheTimeAndMoreOnAKick() throws {
    // The light in a ring round the centre, a third of a second after a kick lands or
    // doesn't.
    func ring(kick: Bool) throws -> Double {
        let stage = try TestStage(visual: 6)
        stage.draw(frames: 180, reading: music())
        stage.draw(frames: 6, reading: kick ? music(beatsHeard: 1, beat: 1) : music())
        stage.draw(frames: 14, reading: kick ? music(beatsHeard: 1) : music())
        let frame = stage.lastFrame()
        return frame.brightness(left: 0.3, top: 0.15, right: 0.7, bottom: 0.38)
            + frame.brightness(left: 0.3, top: 0.62, right: 0.7, bottom: 0.85)
    }
    // With music and no kick at all, sparks are already flying out all round the
    // centre: it doesn't wait for a kick.
    let without = try ring(kick: false)
    #expect(without > 0.02, "with no kick \(without)")
    // A kick throws a shell of them on top.
    let with = try ring(kick: true)
    #expect(with > without * 1.08, "with no kick \(without), with one \(with)")
}

@Test(.enabled(if: hasGraphicsCard, noGraphicsCard))
func theStarburstsSparksKeepFlyingOutwardAsTheyFade() throws {
    // The owner, 2026-10-04: "once the moment has passed for it, it fades but still
    // moved outward". The music stops, so nothing new fires, and the sparks already
    // in the air are followed.
    let stage = try TestStage(visual: 6)
    var values = baseValues(ofVisual: 6)
    values.set(0, for: Starburst.Control.centreGlow)
    stage.renderer.values = values
    stage.draw(frames: 150, reading: music())
    stage.draw(frames: 20, reading: .silence)
    let early = stage.lastFrame()
    stage.draw(frames: 50, reading: .silence)
    let later = stage.lastFrame()
    let whole = { (frame: Frame) in frame.brightness(left: 0, top: 0, right: 1, bottom: 1) }
    // Further out, and fainter.
    #expect(
        averageDistanceOfTheLight(in: later) > averageDistanceOfTheLight(in: early) * 1.04,
        "early \(averageDistanceOfTheLight(in: early)), later \(averageDistanceOfTheLight(in: later))")
    #expect(whole(later) < whole(early) * 0.8, "early \(whole(early)), later \(whole(later))")
}

@Test(.enabled(if: hasGraphicsCard, noGraphicsCard))
func theStarburstHasNoLinesStraightOutFromTheCentre() throws {
    // The first design fired streams: lines of sparks, all on one heading. Now every
    // spark has a heading of its own, so no thin slice of the picture stands out from
    // the slices beside it. (This also catches the line of sparks that the sine-made
    // random numbers drew straight up from the centre on the iMac's graphics card.)
    let stage = try TestStage(visual: 6)
    var values = baseValues(ofVisual: 6)
    values.set(0, for: Starburst.Control.droop)
    values.set(0, for: Starburst.Control.common.cameraMovement)
    stage.renderer.values = values
    stage.draw(frames: 300, reading: music())
    let frame = stage.lastFrame()
    // Thin upright slices above the centre, each a hundredth of the picture wide.
    let slices = (-6...6).map { step -> Double in
        let middle = 0.5 + Double(step) * 0.01
        return frame.brightness(left: middle - 0.005, top: 0.02, right: middle + 0.005, bottom: 0.3)
    }
    let centre = slices[6]
    let beside = (slices[..<5].reduce(0, +) + slices[8...].reduce(0, +)) / 10
    #expect(centre < beside * 1.35, "the slice straight above the centre \(centre), those beside it \(beside)")
}

@Test(.enabled(if: hasGraphicsCard, noGraphicsCard))
func theStarburstCanBeAllWhiteOrFullColour() throws {
    // How far apart the picture's red, green and blue are.
    func colourfulness(whiteness: Float) throws -> Double {
        let stage = try TestStage(visual: 6)
        var values = baseValues(ofVisual: 6)
        values.set(whiteness, for: Starburst.Control.whiteness)
        // Every band orange, so there's one colour to look for.
        for band in Band.allCases { values.setColour(SIMD3(1, 0.4, 0.05), for: band, in: 6) }
        stage.renderer.values = values
        stage.draw(frames: 120, reading: music())
        let seen = stage.lastFrame().colour(left: 0.2, top: 0.1, right: 0.8, bottom: 0.9)
        return seen.red / max(seen.blue, 0.0001)
    }
    let coloured = try colourfulness(whiteness: 0)
    let white = try colourfulness(whiteness: 1)
    #expect(coloured > white * 1.5, "coloured \(coloured), white \(white)")
}

@Test func theStarburstsSparksAllStartWaitingAtTheCentre() {
    let sparks = Starburst.startingSparks(count: 1_000)
    #expect(MemoryLayout<Starburst.Spark>.stride == 64)
    #expect(sparks.allSatisfy { $0.position.w >= 1 && $0.nature.w >= 0 && $0.nature.w < 1 })
}

// MARK: Visualizer 4, Tendrils

@Test(.enabled(if: hasGraphicsCard, noGraphicsCard))
func theTendrilsPourOutFromADarkHole() throws {
    let stage = try TestStage(visual: 4)
    stage.draw(frames: 420, reading: music())
    let frame = stage.lastFrame()
    let hole = frame.brightness(left: 0.485, top: 0.47, right: 0.515, bottom: 0.53)
    let rim = frame.brightness(left: 0.35, top: 0.3, right: 0.65, bottom: 0.7)
    let farOut = frame.brightness(left: 0.05, top: 0.2, right: 0.25, bottom: 0.8)
    // Dark in the very middle (only a little of the strands' glow reaches in), bright
    // around it, and strands all the way out.
    #expect(hole < 0.12, "hole \(hole)")
    #expect(rim > hole * 3 && rim > 0.05, "hole \(hole), rim \(rim)")
    #expect(farOut > 0.02, "far out \(farOut)")
}

@Test(.enabled(if: hasGraphicsCard, noGraphicsCard))
func aLongerTrailIsSmootherNotBrighter() throws {
    func light(trail: Float) throws -> Double {
        let stage = try TestStage(visual: 4)
        var values = baseValues(ofVisual: 4)
        values.set(trail, for: Tendrils.Control.trail)
        stage.renderer.values = values
        stage.draw(frames: 420, reading: music())
        return stage.lastFrame().brightness(left: 0, top: 0, right: 1, bottom: 1)
    }
    let short = try light(trail: 0.12)
    let long = try light(trail: 1.5)
    #expect(long < short * 2.2 && long > short * 0.45, "short \(short), long \(long)")
}

@Test(.enabled(if: hasGraphicsCard, noGraphicsCard))
func theTendrilsStartAfreshWhenThePictureChangesSize() throws {
    // The trails are kept in the picture itself. A picture of a new size has none,
    // and mustn't show whatever happened to be in the graphics card's memory.
    let stage = try TestStage(width: 320, height: 180, particleCount: 20_000, visual: 4)
    stage.draw(frames: 120, reading: music())
    try stage.renderer.resize(forViewPixels: CGSize(width: 200, height: 120))
    stage.draw(frames: 1, reading: .silence)
    #expect(stage.renderer.timer.summary.framesPerSecond > 0)
}

@Test func theTendrilsSparksStartAtDifferentAges() {
    let sparks = Tendrils.startingSparks(count: 1_000)
    #expect(MemoryLayout<Tendrils.Spark>.stride == 64)
    // None has set out yet, and their ages are spread, so they don't all leave the rim
    // in the same frame.
    #expect(sparks.allSatisfy { $0.nature.y < 0 && $0.position.w >= 0 && $0.position.w < 1 })
    #expect(sparks.filter { $0.position.w < 0.5 }.count > 400)
}
