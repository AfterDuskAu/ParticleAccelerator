import Foundation
import Metal
import Testing
import simd

@testable import ParticleAccelerator

// Tests for the two visuals laid out in band sections (2026-10-04): Corona (7), the
// copy of Tendrils, and Jets (8), the copy of Fountain. The owner asked for copies "a
// lot more responsive to their specific bars".

/// A reading with only one band's bars playing, all of them at full.
private func only(_ band: Band) -> SoundReading {
    var reading = SoundReading.silence
    for bar in 0..<SoundAnalyser.barCount where Band.of(bar: bar) == band { reading.bars[bar] = 1 }
    reading.loudness = 0.7
    reading.bands[band] = 1
    reading.seconds = 10
    return reading
}

/// A reading with every bar playing.
private func everything() -> SoundReading {
    var reading = SoundReading.silence
    reading.bars = SIMD64<Float>(repeating: 1)
    reading.loudness = 0.8
    reading.bands = BandValues(sub: 0.8, kick: 0.8, lowMids: 0.8, mids: 0.8, vocals: 0.8, air: 0.8)
    reading.seconds = 10
    return reading
}

/// A visual at its base, with the camera standing still so that places in the picture
/// can be told apart.
private func stillStage(visual: Int, _ change: (inout ControlValues) -> Void = { _ in }) throws -> TestStage {
    let stage = try TestStage(visual: visual)
    var values = baseValues(ofVisual: visual)
    let camera = visual == 7 ? Corona.Control.common : Jets.Control.common
    values.set(0, for: camera.cameraMovement)
    values.set(0, for: camera.beatPunch)
    change(&values)
    stage.renderer.values = values
    return stage
}

// MARK: The sections

@Test func theSixSectionsCoverTheWholeSpectrumInOrder() {
    let edges = BandSections.barEdges
    #expect(edges.count == 7 && edges.first == 0 && edges.last == 64)
    #expect(zip(edges, edges.dropFirst()).allSatisfy { $0 < $1 })
    // Cut into parts, the sections cover every bar, and each part's bars are in its
    // own band. While a part is at least a bar wide, no bar counts for two parts.
    for parts in [1, 3, 8] {
        var covered: [Int] = []
        for band in Band.allCases {
            for part in 0..<parts {
                let bars = BandSections.bars(ofPart: part, of: parts, in: band)
                #expect(bars.allSatisfy { Band.of(bar: $0) == band }, "\(band) part \(part) of \(parts): \(bars)")
                covered += bars
            }
        }
        #expect(Set(covered) == Set(0..<64), "cut into \(parts)")
        if parts <= 3 { #expect(covered.count == 64, "cut into \(parts): a bar counts twice") }
    }
}

// MARK: Visualizer 8, Jets

@Test func eachJetFollowsItsOwnBarsAndNoOthers() {
    // One bar playing, in the mids.
    var peaks = SIMD64<Float>(repeating: 0)
    peaks[35] = 0.9
    #expect(Band.of(bar: 35) == .mids)
    for jetsForEachBand in [1, 3, 8] {
        let levels = Jets.jetLevels(peaks: peaks, jetsForEachBand: jetsForEachBand)
        #expect(levels.count == 6 * jetsForEachBand)
        // One jet is up, it's one of the mids', and every other jet is down.
        let up = levels.indices.filter { levels[$0] > 0 }
        #expect(up.count == 1 && levels[up[0]] == 0.9, "\(jetsForEachBand) for each band: \(levels)")
        #expect(up[0] / jetsForEachBand == Band.mids.rawValue)
    }
}

@Test(.enabled(if: hasGraphicsCard, noGraphicsCard))
func theJetsStandInTheSoundChecksOrderAndOnlyTheirOwnBandsRise() throws {
    // Sub on the left, air on the right. With only one band playing, the light well
    // above the floor is over that band's jets.
    func lightAbove(_ band: Band) throws -> (left: Double, middle: Double, right: Double) {
        let stage = try stillStage(visual: 8)
        stage.draw(frames: 40, reading: only(band))
        let frame = stage.lastFrame()
        // The row runs from about a fifth of the way across the picture to four
        // fifths. The mids' jets are just right of its middle.
        return (
            frame.brightness(left: 0.16, top: 0.3, right: 0.32, bottom: 0.7),
            frame.brightness(left: 0.48, top: 0.3, right: 0.62, bottom: 0.7),
            frame.brightness(left: 0.70, top: 0.3, right: 0.86, bottom: 0.7)
        )
    }
    let sub = try lightAbove(.sub)
    #expect(sub.left > sub.middle * 4 && sub.left > sub.right * 4 && sub.left > 0.01, "sub \(sub)")
    let air = try lightAbove(.air)
    #expect(air.right > air.middle * 4 && air.right > air.left * 4 && air.right > 0.01, "air \(air)")
    let mids = try lightAbove(.mids)
    #expect(mids.middle > mids.left * 4 && mids.middle > mids.right * 4 && mids.middle > 0.01, "mids \(mids)")
}

@Test(.enabled(if: hasGraphicsCard, noGraphicsCard))
func aJetIsUpWithinABeatAndDownBeforeTheNext() throws {
    let stage = try stillStage(visual: 8)
    func lightHighUp() -> Double {
        stage.lastFrame().brightness(left: 0.1, top: 0.2, right: 0.9, bottom: 0.55)
    }
    stage.draw(frames: 120, reading: .silence)
    let silent = lightHighUp()
    // A quarter of a second after the music starts, the sparks are well up.
    stage.draw(frames: 15, reading: everything())
    let up = lightHighUp()
    #expect(up > silent * 5 && up > 0.01, "silent \(silent), up \(up)")
    // Three quarters of a second after it stops, they're down again.
    stage.draw(frames: 45, reading: .silence)
    let down = lightHighUp()
    #expect(down < up * 0.15, "up \(up), down \(down)")
}

@Test(.enabled(if: hasGraphicsCard, noGraphicsCard))
func withOneJetForEachBandSixStandApart() throws {
    // Six jets with dark gaps between them, counted just above the floor.
    func gapsAlongTheRow(jetsForEachBand: Float) throws -> Int {
        let stage = try stillStage(visual: 8) {
            $0.set(jetsForEachBand, for: Jets.Control.jetsForEachBand)
            $0.set(0, for: Jets.Control.fan)
            $0.set(0, for: Jets.Control.floorGlow)
        }
        stage.draw(frames: 90, reading: everything())
        let frame = stage.lastFrame()
        let strip = (0..<160).map { step -> Double in
            let left = 0.1 + 0.8 * Double(step) / 160
            return frame.brightness(left: left, top: 0.70, right: left + 0.005, bottom: 0.84)
        }
        let brightest = strip.max() ?? 0
        // A gap is a run of dark after light. (The jets' glow keeps the gaps from
        // being black, so "dark" is less than half as bright as the brightest jet.)
        var gaps = 0
        var wasLit = false
        for light in strip {
            let isLit = light > brightest * 0.5
            if wasLit && !isLit { gaps += 1 }
            wasLit = isLit
        }
        return gaps
    }
    let six = try gapsAlongTheRow(jetsForEachBand: 1)
    #expect(six >= 5 && six <= 7, "one jet for each band: \(six) gaps")
}

@Test func theJetsSparksAllStartWaiting() {
    let sparks = Jets.startingSparks(count: 1_000)
    #expect(MemoryLayout<Jets.Spark>.stride == 64)
    #expect(sparks.allSatisfy { $0.position.w >= 1 && $0.nature.w >= 0 && $0.nature.w < 1 })
}

// MARK: Visualizer 7, Corona

/// The light round the hole: below it, above it, and far out to one side.
private func lightRoundTheHole(_ frame: Frame) -> (below: Double, above: Double) {
    (
        frame.brightness(left: 0.42, top: 0.74, right: 0.58, bottom: 0.94),
        frame.brightness(left: 0.42, top: 0.06, right: 0.58, bottom: 0.26)
    )
}

@Test(.enabled(if: hasGraphicsCard, noGraphicsCard))
func theBassReachesOutBelowTheHoleAndTheHighsAboveIt() throws {
    let low = try stillStage(visual: 7)
    low.draw(frames: 240, reading: only(.sub))
    let bass = lightRoundTheHole(low.lastFrame())
    #expect(bass.below > bass.above * 5 && bass.below > 0.01, "bass \(bass)")

    let high = try stillStage(visual: 7)
    high.draw(frames: 240, reading: only(.air))
    let highs = lightRoundTheHole(high.lastFrame())
    #expect(highs.above > highs.below * 5 && highs.above > 0.01, "highs \(highs)")
}

@Test(.enabled(if: hasGraphicsCard, noGraphicsCard))
func aStrandReachesOutAtOnceAndLetsGoAtOnce() throws {
    // In Visualizer 4 a strand's sparks have to travel out along it, which takes
    // seconds. Here they're already flowing along its whole length, unlit, so the
    // strand reaches out as fast as the music does.
    let stage = try stillStage(visual: 7)
    func farOut() -> Double {
        let frame = stage.lastFrame()
        return frame.brightness(left: 0.42, top: 0.04, right: 0.58, bottom: 0.2)
            + frame.brightness(left: 0.42, top: 0.8, right: 0.58, bottom: 0.96)
    }
    stage.draw(frames: 120, reading: .silence)
    let silent = farOut()
    // A tenth of a second of music, and the tips are far out.
    stage.draw(frames: 6, reading: everything())
    let reached = farOut()
    #expect(reached > silent * 8 && reached > 0.01, "silent \(silent), reached \(reached)")
    // Half a second of silence, and they've let go.
    stage.draw(frames: 30, reading: .silence)
    let letGo = farOut()
    #expect(letGo < reached * 0.2, "reached \(reached), let go \(letGo)")
}

@Test(.enabled(if: hasGraphicsCard, noGraphicsCard))
func theCoronasHoleStaysDarkAndItsTwoSidesMatch() throws {
    let stage = try stillStage(visual: 7)
    stage.draw(frames: 300, reading: everything())
    let frame = stage.lastFrame()
    let hole = frame.brightness(left: 0.485, top: 0.47, right: 0.515, bottom: 0.53)
    let strands = frame.brightness(left: 0.42, top: 0.60, right: 0.58, bottom: 0.68)
    let left = frame.brightness(left: 0.2, top: 0.2, right: 0.45, bottom: 0.8)
    let right = frame.brightness(left: 0.55, top: 0.2, right: 0.8, bottom: 0.8)
    // Only a little of the strands' glow reaches into the hole.
    #expect(hole < 0.2 && hole < strands * 0.5, "hole \(hole), the strands just below it \(strands)")
    #expect(left > 0.03 && right > 0.03, "left \(left), right \(right)")
    // The bands climb both sides alike, so one side is about as bright as the other.
    #expect(left < right * 1.5 && right < left * 1.5, "left \(left), right \(right)")
}

@Test func theCoronasSparksStartBeforeAnyHasSetOut() {
    let sparks = Corona.startingSparks(count: 1_000)
    #expect(MemoryLayout<Corona.Spark>.stride == 64)
    #expect(sparks.allSatisfy { $0.nature.y < 0 && $0.nature.w >= 0 && $0.nature.w < 1 })
    #expect(Set(sparks.map(\.nature.w)).count > 990)
}

@Test(.enabled(if: hasGraphicsCard, noGraphicsCard))
func aStrandIsFullOfSparksFromTheFirstMoment() throws {
    // Each spark starts somewhere along its strand, so the very first hit, a few
    // frames after the visual starts, already reaches far out.
    let stage = try stillStage(visual: 7)
    stage.draw(frames: 8, reading: everything())
    let frame = stage.lastFrame()
    let farOut = frame.brightness(left: 0.42, top: 0.04, right: 0.58, bottom: 0.2)
        + frame.brightness(left: 0.42, top: 0.8, right: 0.58, bottom: 0.96)
    #expect(farOut > 0.01, "far out \(farOut)")
}
