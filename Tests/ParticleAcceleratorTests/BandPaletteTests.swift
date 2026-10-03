import Foundation
import Testing
import simd

@testable import ParticleAccelerator

// MARK: Colours that stay as they are

@Test func theColoursAreTheBandsOwnUntilAPersonPicksOthers() {
    var values = ControlValues()
    #expect(BandPalette(values).colours(at: 12) == Band.allCases.map(\.colour))
    values.setColour(SIMD3(0.2, 0.4, 0.6), for: .mids)
    let colours = BandPalette(values).colours(at: 12)
    #expect(colours[Band.mids.rawValue] == SIMD3(0.2, 0.4, 0.6))
    #expect(colours[Band.sub.rawValue] == Band.sub.colour)
    // And they don't move.
    #expect(BandPalette(values).colours(at: 500) == colours)
}

// MARK: Colours that change by themselves

/// The palette with "change by themselves" switched on.
private func changing(every seconds: Float = 20) -> BandPalette {
    var values = ControlValues()
    values.set(1, for: BandPalette.changesControl)
    values.set(seconds, for: BandPalette.secondsControl)
    return BandPalette(values)
}

@Test func switchedOnTheColoursDriftAndNeverSettle() {
    let palette = changing()
    #expect(palette.changesByItself && palette.secondsForAChange == 20)
    let start = palette.colours(at: 1_000)
    // The same moment always gives the same colours: the stage and the sound check ask
    // separately and must agree.
    #expect(palette.colours(at: 1_000) == start)
    // A minute on they're different, and a minute after that different again.
    let later = palette.colours(at: 1_060)
    let laterStill = palette.colours(at: 1_120)
    #expect(later != start && laterStill != later && laterStill != start)
}

@Test func theDriftIsSlowAndSmooth() {
    // From one frame to the next no colour moves by more than a hair, even at the
    // quickest setting.
    for seconds: Float in [4, 20, 120] {
        let palette = changing(every: seconds)
        var biggestStep: Float = 0
        var before = palette.colours(at: 2_000)
        for frame in 1...(60 * 30) {
            let now = palette.colours(at: 2_000 + Double(frame) / 60)
            for band in 0..<6 { biggestStep = max(biggestStep, simd_abs(now[band] - before[band]).max()) }
            before = now
        }
        #expect(biggestStep < 0.2 / seconds, "every \(seconds) s: \(biggestStep)")
    }
}

@Test func neighbouringBandsAlwaysStayApart() {
    // The owner asked for the visual to be separated into colours. However the colours
    // drift, each band stays clearly different from the next.
    let palette = changing(every: 4)
    for moment in stride(from: 0.0, to: 400, by: 0.37) {
        let colours = palette.colours(at: moment)
        for band in 0..<5 {
            let difference = simd_abs(colours[band] - colours[band + 1]).max()
            #expect(difference > 0.2, "bands \(band) and \(band + 1) at \(moment) s: \(colours[band]) and \(colours[band + 1])")
        }
        for colour in colours {
            // Bright, full colours: never grey, never dark.
            #expect(colour.max() == 1 && colour.min() >= 0 && colour.min() < 0.3)
        }
    }
}

@Test func aPersonsOwnColoursWaitWhileTheColoursChange() {
    var values = ControlValues()
    values.setColour(SIMD3(0.2, 0.4, 0.6), for: .mids)
    values.set(1, for: BandPalette.changesControl)
    #expect(BandPalette(values).colours(at: 77)[Band.mids.rawValue] != SIMD3(0.2, 0.4, 0.6))
    // Switched off again, they're back.
    values.reset(BandPalette.changesControl)
    #expect(BandPalette(values).colours(at: 77)[Band.mids.rawValue] == SIMD3(0.2, 0.4, 0.6))
}

@Test func theShadersAreGivenTheColoursOfTheMoment() {
    var values = ControlValues()
    values.set(1, for: BandPalette.changesControl)
    var early = StageUniforms()
    early.setBandLight(from: values, at: 100)
    var late = StageUniforms()
    late.setBandLight(from: values, at: 160)
    #expect(early.bandLight != late.bandLight)
    // As light, the brightest part of each is still full.
    for band in 0..<6 {
        #expect(max(early.bandLight[band * 4], early.bandLight[band * 4 + 1], early.bandLight[band * 4 + 2]) == 1)
    }
}

@Test func resetAllSwitchesTheChangingOffToo() {
    var values = ControlValues()
    values.set(1, for: BandPalette.changesControl)
    values.set(8, for: BandPalette.secondsControl)
    #expect(values.hasChanges(among: ParticleWave.controls))
    values.reset(ParticleWave.controls)
    #expect(values.isEmpty)
    #expect(!BandPalette(values).changesByItself)
}

@Test func aColourFromItsPlaceOnTheWheel() {
    #expect(BandPalette.colour(hue: 0, saturation: 1) == SIMD3(1, 0, 0))
    #expect(BandPalette.colour(hue: 1.0 / 3, saturation: 1) == SIMD3(0, 1, 0))
    #expect(BandPalette.colour(hue: 2.0 / 3, saturation: 1) == SIMD3(0, 0, 1))
    // Past once round is the same as the start, and so is going backwards.
    #expect(BandPalette.colour(hue: 1.25, saturation: 1) == BandPalette.colour(hue: 0.25, saturation: 1))
    #expect(BandPalette.colour(hue: -0.75, saturation: 1) == BandPalette.colour(hue: 0.25, saturation: 1))
    // Less saturated is paler.
    #expect(BandPalette.colour(hue: 0, saturation: 0.5) == SIMD3(1, 0.5, 0.5))
}
