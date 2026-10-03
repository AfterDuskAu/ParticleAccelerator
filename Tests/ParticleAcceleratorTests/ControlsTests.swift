import Foundation
import Testing
import simd

@testable import ParticleAccelerator

// MARK: A person's own changes (no graphics card needed)

private let height = ParticleWave.Control.peakHeight
private let fall = ParticleWave.Control.fall

@Test func aControlKeepsTheVisualsOwnSettingUntilItIsChanged() {
    var values = ControlValues()
    #expect(values.isEmpty)
    #expect(values.value(of: height) == height.usual)
    #expect(!values.isChanged(height))

    values.set(0.5, for: height)
    #expect(values.value(of: height) == 0.5)
    #expect(values.isChanged(height) && !values.isChanged(fall))
    #expect(values.hasChanges(among: ParticleWave.controls))

    values.reset(height)
    #expect(values.value(of: height) == height.usual)
    #expect(values.isEmpty)
}

@Test func aControlNeverLeavesItsRange() {
    var values = ControlValues()
    values.set(50, for: height)
    #expect(values.value(of: height) == height.range.upperBound)
    values.set(-3, for: height)
    #expect(values.value(of: height) == height.range.lowerBound)
}

@Test func aBandsColourCanBeChangedAndPutBack() {
    var values = ControlValues()
    #expect(values.colour(of: .kick) == Band.kick.colour)
    values.setColour(SIMD3(0.1, 0.9, 0.2), for: .kick)
    #expect(values.colour(of: .kick) == SIMD3(0.1, 0.9, 0.2))
    #expect(values.isColourChanged(.kick) && !values.isColourChanged(.sub))
    #expect(values.colour(of: .sub) == Band.sub.colour)
    values.resetColour(of: .kick)
    #expect(values.colour(of: .kick) == Band.kick.colour)
    #expect(values.isEmpty)
}

@Test func resetAllPutsEverythingBack() {
    var values = ControlValues()
    values.set(0.4, for: height)
    values.set(0.5, for: fall)
    values.setColour(SIMD3(1, 1, 1), for: .air)
    values.reset(ParticleWave.controls)
    #expect(values.isEmpty)

    // And the same for a host, which doesn't know one visual's controls from another's.
    values.set(0.4, for: height)
    values.setColour(SIMD3(1, 1, 1), for: .air)
    values.resetAll()
    #expect(values.isEmpty)
}

@Test func changesAreSavedWithTheSettingsAndComeBack() throws {
    var settings = AcceleratorSettings()
    settings.quality = .medium
    settings.controls.set(0.4, for: height)
    settings.controls.setColour(SIMD3(0.2, 0.4, 0.6), for: .mids)

    let saved = try JSONEncoder().encode(settings)
    let back = try JSONDecoder().decode(AcceleratorSettings.self, from: saved)
    #expect(back == settings)
    #expect(back.controls.value(of: height) == 0.4)
    #expect(back.controls.colour(of: .mids) == SIMD3(0.2, 0.4, 0.6))
}

@Test func settingsSavedBeforeTheControlsExistedStillOpen() throws {
    // What the app saved before the controls were added. Everything in it is kept, and
    // the controls start unchanged.
    let old = #"{"visual":3,"quality":"ultra","limitsFlashing":false,"showsFrameTime":true}"#
    let settings = try JSONDecoder().decode(AcceleratorSettings.self, from: Data(old.utf8))
    #expect(settings.quality == .ultra)
    #expect(!settings.limitsFlashing && settings.showsFrameTime)
    #expect(settings.controls.isEmpty)
    // And settings with nothing in them at all are simply new settings.
    #expect(try JSONDecoder().decode(AcceleratorSettings.self, from: Data("{}".utf8)) == AcceleratorSettings())
}

@Test func aSavedValueThatMakesNoSenseIsIgnored() throws {
    // A colour with two numbers, and a control from a visual that doesn't exist.
    let odd = #"{"controls":{"numbers":{"99.nothing":4},"colours":{"kick":[0.5,0.5]}}}"#
    let settings = try JSONDecoder().decode(AcceleratorSettings.self, from: Data(odd.utf8))
    #expect(settings.controls.colour(of: .kick) == Band.kick.colour)
    #expect(settings.controls.value(of: height) == height.usual)
}

// MARK: Every visual's list of controls

@Test func everyControlIsWellFormed() {
    for visual in StageRenderer.visuals {
        let controls = visual.controls
        #expect(!controls.isEmpty, "Visualizer \(visual.number) has no controls")
        #expect(Set(controls.map(\.id)).count == controls.count, "two controls share a name in saved settings")
        #expect(StageRenderer.controls(ofVisual: visual.number) == controls)
        for control in controls {
            #expect(control.visual == visual.number)
            #expect(control.range.contains(control.usual), "\(control.id)")
            #expect(control.range.lowerBound < control.range.upperBound, "\(control.id)")
            #expect(!control.name.isEmpty && !control.group.isEmpty && control.help.hasSuffix("."), "\(control.id)")
            // A slider that gives equal room to equal ratios can't start at nothing.
            #expect(!control.spreadsEvenlyByRatio || control.range.lowerBound > 0, "\(control.id)")
            // Two controls under one heading never share a name.
            #expect(controls.filter { $0.group == control.group && $0.name == control.name }.count == 1, "\(control.id)")
        }
    }
    #expect(StageRenderer.controls(ofVisual: 2).isEmpty)
}

@Test func aSliderGoesToAValueAndBack() {
    for control in ParticleWave.controls {
        #expect(control.sliderPlace(of: control.range.lowerBound) == 0, "\(control.id)")
        #expect(abs(control.sliderPlace(of: control.range.upperBound) - 1) < 1e-6, "\(control.id)")
        let place = control.sliderPlace(of: control.usual)
        #expect(place >= 0 && place <= 1)
        #expect(abs(control.value(atSliderPlace: place) - control.usual) < 1e-4 * max(1, control.usual), "\(control.id)")
    }
    // Times get as much room from 0.03 to 0.3 as from 0.15 to 1.5.
    #expect(abs((fall.sliderPlace(of: 0.3) - fall.sliderPlace(of: 0.03)) - (fall.sliderPlace(of: 1.5) - fall.sliderPlace(of: 0.15))) < 1e-5)
}

@Test func valuesAreShownInPlainWords() {
    #expect(height.text(for: 0.88) == "88%")
    #expect(fall.text(for: 0.11) == "0.11 s")
    #expect(ParticleWave.Control.rise.text(for: 0.035) == "0.035 s")
    #expect(ParticleWave.Control.peakWidth.text(for: 2.5) == "2.5 bars")
    #expect(ParticleWave.Control.quietPitches.text(for: 5) == "5.0 dB")
    #expect(ParticleWave.Control.sparkSize.text(for: 1) == "1.00×")
}

@Test func fewerBarsJoinNeighboursIntoBlocks() {
    // One loud pitch, in bar 30. With all 64 bars it's a peak of its own; with 8, the
    // whole block of eight bars it's in (24 to 31) stands as tall as it does.
    func settled(barsShown: Int) -> SIMD64<Float> {
        var mountains = ParticleWave.Mountains()
        mountains.barsShown = barsShown
        var sound = SIMD64<Float>(repeating: 0)
        sound[30] = 1
        var range = SIMD64<Float>(repeating: 0)
        for _ in 0..<120 { range = mountains.update(bars: sound, seconds: 1.0 / 60) }
        return range
    }
    let all = settled(barsShown: 64)
    #expect(all[30] > 0.5 && all[25] == 0)
    let eight = settled(barsShown: 8)
    #expect(eight[24] == eight[30] && eight[31] == eight[30] && eight[30] == all[30])
    // And it still slopes away at the block's edges.
    #expect(eight[23] < eight[24] && eight[23] > 0 && eight[20] == 0)
    #expect(ParticleWave.Control.bars.text(for: 64) == "64")
}

@Test func theControlsAreGroupedUnderTheirHeadingsInOrder() {
    let groups = AcceleratorControls.groups(of: ParticleWave.controls)
    #expect(groups.map(\.name) == ["Peaks", "Movement", "Sparks", "Line", "Picture"])
    #expect(groups.flatMap(\.controls) == ParticleWave.controls)
}

// MARK: The controls change the mountains

@Test func theMountainsFollowTheirControls() {
    func settled(_ change: (inout ParticleWave.Mountains) -> Void) -> SIMD64<Float> {
        var mountains = ParticleWave.Mountains()
        change(&mountains)
        var sound = SIMD64<Float>(repeating: 0)
        sound[30] = 1
        sound[33] = 0.875
        var range = SIMD64<Float>(repeating: 0)
        for _ in 0..<120 { range = mountains.update(bars: sound, seconds: 1.0 / 60) }
        return range
    }
    let usual = settled { _ in }
    // A sound that holds steady stands as tall as it's told to.
    #expect(abs(settled { $0.heldShare = 1 }[30] - 1) < 0.01)
    // Wider peaks reach further to each side.
    #expect(usual[27] == 0 && settled { $0.footprint = 6 }[27] > 0.2)
    // Showing more of the quieter pitches lifts the quieter one of the two.
    #expect(settled { $0.decibelsToHalve = 12 }[33] > usual[33] * 1.3)
}

@Test func aLongerFallLetsAPeakHang() {
    func leftAfterATenthOfASecond(fall: Double) -> Float {
        var mountains = ParticleWave.Mountains()
        mountains.fallSeconds = fall
        var sound = SIMD64<Float>(repeating: 0)
        sound[30] = 1
        for _ in 0..<3 { _ = mountains.update(bars: sound, seconds: 1.0 / 60) }
        var range = SIMD64<Float>(repeating: 0)
        for _ in 0..<6 { range = mountains.update(bars: SIMD64<Float>(repeating: 0), seconds: 1.0 / 60) }
        return range[30]
    }
    #expect(leftAfterATenthOfASecond(fall: 0.03) < 0.1)
    #expect(leftAfterATenthOfASecond(fall: 1) > 0.8)
}

// MARK: The controls change the picture (needs a graphics card)

/// Music right across the spectrum, drawn with these changes.
private func picture(_ change: (inout ControlValues) -> Void = { _ in }) throws -> Frame {
    let stage = try TestStage()
    var values = ControlValues()
    change(&values)
    stage.renderer.values = values
    var reading = SoundReading.silence
    reading.bars = SIMD64<Float>(repeating: 1)
    reading.loudness = 0.8
    reading.seconds = 10
    stage.draw(frames: 240, reading: reading)
    return stage.lastFrame()
}

@Test(.enabled(if: hasGraphicsCard, noGraphicsCard))
func aLowerPeakHeightKeepsTheSparksLow() throws {
    func lightHighUp(_ frame: Frame) -> Double {
        frame.brightness(left: 0.1, top: 0.24, right: 0.9, bottom: 0.36)
    }
    let usual = lightHighUp(try picture())
    let low = lightHighUp(try picture { $0.set(0.2, for: ParticleWave.Control.peakHeight) })
    #expect(low < usual * 0.7, "usual \(usual), low \(low)")
}

@Test(.enabled(if: hasGraphicsCard, noGraphicsCard))
func brighterSparksAreBrighter() throws {
    func light(_ frame: Frame) -> Double {
        frame.brightness(left: 0.1, top: 0.25, right: 0.9, bottom: 0.45)
    }
    let dim = light(try picture { $0.set(0.3, for: ParticleWave.Control.sparkBrightness) })
    let bright = light(try picture { $0.set(3, for: ParticleWave.Control.sparkBrightness) })
    #expect(bright > dim * 1.5, "dim \(dim), bright \(bright)")
}

@Test(.enabled(if: hasGraphicsCard, noGraphicsCard))
func aPickedColourShowsInItsBandsSection() throws {
    // The kick's section is pink until the person picks green for it.
    let usual = try picture().colour(left: 0.15, top: 0.30, right: 0.21, bottom: 0.46)
    #expect(usual.red > usual.green * 1.3, "\(usual)")
    let picked = try picture { $0.setColour(SIMD3(0.1, 1, 0.2), for: .kick) }
    let kick = picked.colour(left: 0.15, top: 0.30, right: 0.21, bottom: 0.46)
    #expect(kick.green > kick.red * 1.3, "\(kick)")
    // The section two along is left as it was.
    let mids = picked.colour(left: 0.53, top: 0.30, right: 0.59, bottom: 0.46)
    #expect(mids.blue > mids.green, "\(mids)")
}
