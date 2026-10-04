import Foundation
import Testing
import simd

@testable import ParticleAccelerator

// Each visual's standard and its lock (the owner, 2026-10-04): "Set Standard", "Reset
// to Standard", "Reset All" (which goes back to the base), and a lock so that nothing
// is moved by accident. None of these needs a graphics card.

private let height = ParticleWave.Control.peakHeight
private let fountainHeight = Fountain.Control.height

// MARK: The visuals' own standards

@Test func aVisualShowsItsStandardUntilItIsChanged() {
    let values = ControlValues()
    // Visualizer 5's standard is the owner's, which isn't its base.
    #expect(fountainHeight.base == 1 && fountainHeight.standard == 1.37)
    #expect(values.value(of: fountainHeight) == 1.37)
    #expect(values.value(of: Fountain.Control.common.cameraMovement) == 4)
    #expect(BandPalette(values, visual: 5).changesByItself)
    #expect(!values.differsFromStandard(visual: 5) && values.differsFromBase(visual: 5))
    // Visualizer 3 has no standard of its own yet, so it's at its base.
    #expect(values.value(of: height) == height.base)
    #expect(!values.differsFromStandard(visual: 3) && !values.differsFromBase(visual: 3))
    #expect(!BandPalette(values, visual: 3).changesByItself)
}

@Test func everyStandardNamesRealControlsAndKeepsInsideTheirRanges() {
    for visual in StageRenderer.visuals {
        let controls = visual.controls + BandPalette.controls(ofVisual: visual.number)
        for (key, value) in visual.standard {
            let control = controls.first { $0.key == key }
            #expect(control != nil, "Visualizer \(visual.number)'s standard names “\(key)”, which isn't one of its controls")
            if let control {
                #expect(control.range.contains(value), "\(control.id)")
                #expect(control.standard == value, "\(control.id)")
            }
        }
        // Anything a standard doesn't name is at its base.
        for control in controls where visual.standard[control.key] == nil {
            #expect(control.standard == control.base, "\(control.id)")
        }
    }
}

@Test func theOwnersTwoStandardsAreAsTheySetThem() {
    // From the owner's two screenshots, 2026-10-04.
    func shown(_ visual: Visual.Type, _ key: String) -> String? {
        let controls = visual.controls + BandPalette.controls(ofVisual: visual.number)
        return controls.first { $0.key == key }.map { $0.text(for: ControlValues().value(of: $0)) }
    }
    let fountain: [String: String] = [
        "height": "1.37×", "spread": "3.50×", "amount": "0.43×", "kickBurst": "1.67×", "gravity": "3.00×",
        "life": "2.03×", "sparkSize": "1.00×", "sparkBrightness": "2.74×", "twinkle": "1.93×",
        "whiteHeat": "14%", "streaks": "1.00×", "floorGlow": "1.00×", "cameraMovement": "4.00×",
        "beatPunch": "1.41×", "glow": "0.24×", "brightness": "0.44×", "darkCorners": "64%",
    ]
    for (key, text) in fountain { #expect(shown(Fountain.self, key) == text, "5.\(key)") }
    #expect(Set(fountain.keys) == Set(Fountain.controls.map(\.key)))

    let tendrils: [String: String] = [
        "speed": "0.47×", "bassPush": "1.26×", "curl": "4.00×", "curlSize": "2.07×", "turning": "3.82×",
        "holeSize": "1.77×", "strands": "1.00×", "trail": "0.050 s", "thickness": "0.90×",
        "strandBrightness": "0.75×", "specks": "3%", "twinkle": "1.00×", "cameraMovement": "4.00×",
        "beatPunch": "0.60×", "glow": "0.30×", "brightness": "1.00×", "darkCorners": "50%",
        "coloursChange": "100%", "colourSeconds": "4.68 s",
    ]
    for (key, text) in tendrils { #expect(shown(Tendrils.self, key) == text, "4.\(key)") }
}

@Test func theOwnersSavedSettingsAreTheirStandards() throws {
    // What the owner's app had saved when they asked for Visualizers 4 and 5 to be
    // their standards: the sliders as they'd left them, and one set of colours shared
    // by every visual. Opened now, both visuals are at their standard with nothing
    // showing as changed, and each visual has the colours as its own.
    let saved = """
        {"controls":{"colours":{},"numbers":{"3.heldSound":0.1,"0.coloursChange":1,"5.darkCorners":0.64368594,\
        "5.glow":0.23721966,"5.beatPunch":1.407243,"3.peakHeight":0.57588667,"4.cameraMovement":4,\
        "5.sparkBrightness":2.739141,"5.height":1.3747134,"4.curlSize":2.0685422,"4.thickness":0.8966921,\
        "5.spread":3.5,"4.beatPunch":0.59638566,"3.peakWidth":3.5412939,"3.quietPitches":5.3419714,\
        "4.speed":0.47139642,"0.colourSeconds":4.677037,"4.holeSize":1.7655804,"5.cameraMovement":4,"4.curl":4,\
        "5.amount":0.4297173,"5.kickBurst":1.6675987,"4.bassPush":1.2574229,"6.streams":40.18599,"5.gravity":3,\
        "5.life":2.0289876,"4.trail":0.05,"4.strandBrightness":0.752131,"6.reach":0.42199108,\
        "4.turning":3.8221521,"5.brightness":0.43532255,"5.twinkle":1.9324592}},\
        "quality":"high","visual":6,"limitsFlashing":true,"showsFrameTime":true}
        """
    let settings = try JSONDecoder().decode(AcceleratorSettings.self, from: Data(saved.utf8))
    let values = settings.controls
    #expect(!values.differsFromStandard(visual: 5))
    #expect(!values.differsFromStandard(visual: 4))
    for control in Fountain.controls + Tendrils.controls { #expect(!values.isChanged(control), "\(control.id)") }
    // Visualizer 3 keeps the owner's changes, as changes.
    #expect(values.isChanged(height) && abs(values.value(of: height) - 0.57588667) < 1e-6)
    // Every visual of the time has the changing colours it was showing.
    for visual in [3, 4, 5, 6] {
        let palette = BandPalette(values, visual: visual)
        #expect(palette.changesByItself && abs(palette.secondsForAChange - 4.677037) < 1e-4, "Visualizer \(visual)")
    }
    // The settings come back the same after being saved again.
    let again = try JSONDecoder().decode(AcceleratorSettings.self, from: JSONEncoder().encode(settings))
    #expect(again == settings)
}

@Test func coloursSavedWhenTheVisualsSharedThemAreGivenToEachVisual() throws {
    let old = #"{"numbers":{"0.coloursChange":0,"3.coloursChange":1},"colours":{"kick":[0.1,0.9,0.2],"4.kick":[1,1,1]}}"#
    let values = try JSONDecoder().decode(ControlValues.self, from: Data(old.utf8))
    // Each visual of the time is given the shared ones, unless it already has its own.
    #expect(values.colour(of: .kick, in: 3) == SIMD3(0.1, 0.9, 0.2))
    #expect(values.colour(of: .kick, in: 6) == SIMD3(0.1, 0.9, 0.2))
    #expect(values.colour(of: .kick, in: 4) == SIMD3(1, 1, 1))
    #expect(BandPalette(values, visual: 3).changesByItself)
    #expect(!BandPalette(values, visual: 5).changesByItself)
    // Visualizers made since start from their own standards.
    #expect(values.colour(of: .kick, in: 8) == Band.kick.colour)
}

// MARK: Reset All, Reset to Standard and Set Standard

@Test func resetAllGoesToTheBaseAndResetToStandardComesBack() {
    var values = ControlValues()
    values.resetToBase(visual: 5)
    #expect(values.value(of: fountainHeight) == 1)
    #expect(!BandPalette(values, visual: 5).changesByItself)
    #expect(!values.differsFromBase(visual: 5) && values.differsFromStandard(visual: 5))
    #expect(values.isChanged(fountainHeight))
    // A control whose standard is its base isn't a change.
    #expect(!values.isChanged(Fountain.Control.sparkSize))

    values.resetToStandard(visual: 5)
    #expect(values.value(of: fountainHeight) == 1.37)
    #expect(values.isEmpty)
}

@Test func setStandardMakesTheSettingsAsTheyAreTheStandard() {
    var values = ControlValues()
    values.set(0.5, for: height)
    values.setColour(SIMD3(0.1, 0.9, 0.2), for: .kick, in: 3)
    values.set(1, for: BandPalette.changesControl(ofVisual: 3))
    values.setStandard(visual: 3)
    // They're the standard now, so nothing reads as changed.
    #expect(values.standard(of: height) == 0.5 && values.value(of: height) == 0.5)
    #expect(!values.isChanged(height) && !values.differsFromStandard(visual: 3))
    #expect(values.standardColour(of: .kick, in: 3) == SIMD3(0.1, 0.9, 0.2))

    // A change, and back to the standard.
    values.set(0.7, for: height)
    values.setColour(SIMD3(1, 1, 1), for: .kick, in: 3)
    #expect(values.isChanged(height) && values.isColourChanged(.kick, in: 3))
    values.resetToStandard(visual: 3)
    #expect(values.value(of: height) == 0.5)
    #expect(values.colour(of: .kick, in: 3) == SIMD3(0.1, 0.9, 0.2))
    #expect(BandPalette(values, visual: 3).changesByItself)

    // Reset All still goes to the base, and the standard is still there to come back
    // to.
    values.resetToBase(visual: 3)
    #expect(values.value(of: height) == height.base)
    #expect(values.colour(of: .kick, in: 3) == Band.kick.colour)
    #expect(!BandPalette(values, visual: 3).changesByItself)
    values.resetToStandard(visual: 3)
    #expect(values.value(of: height) == 0.5)

    // Setting the base as the standard leaves nothing kept at all.
    values.resetToBase(visual: 3)
    values.setStandard(visual: 3)
    #expect(values.isEmpty)
}

@Test func oneVisualsStandardLeavesTheOthersAlone() {
    var values = ControlValues()
    values.set(0.5, for: height)
    values.set(1.8, for: fountainHeight)
    values.setStandard(visual: 3)
    #expect(values.isChanged(fountainHeight) && values.standard(of: fountainHeight) == 1.37)
    values.resetToStandard(visual: 5)
    #expect(values.value(of: height) == 0.5 && values.value(of: fountainHeight) == 1.37)
    values.resetToBase(visual: 5)
    #expect(values.standard(of: height) == 0.5)
}

@Test func aSettingThatReadsTheSameAsTheStandardIsNotAChange() {
    // A slider can land a hair away from a setting that reads the same: 1.3747 is
    // shown as 1.37×, and so is the standard.
    var values = ControlValues()
    values.set(1.3747, for: fountainHeight)
    #expect(values.value(of: fountainHeight) == 1.3747)
    #expect(!values.isChanged(fountainHeight) && !values.differsFromStandard(visual: 5))
    values.set(1.38, for: fountainHeight)
    #expect(values.isChanged(fountainHeight))
}

@Test func standardsAndLocksAreSavedWithTheSettings() throws {
    var settings = AcceleratorSettings()
    settings.controls.set(0.5, for: height)
    settings.controls.setStandard(visual: 3)
    settings.controls.set(0.7, for: height)
    settings.controls.setLocked(true, visual: 3)
    settings.controls.setLocked(false, visual: 5)
    let back = try JSONDecoder().decode(AcceleratorSettings.self, from: JSONEncoder().encode(settings))
    #expect(back == settings)
    #expect(back.controls.standard(of: height) == 0.5 && back.controls.value(of: height) == 0.7)
    #expect(back.controls.isLocked(visual: 3) && !back.controls.isLocked(visual: 5))
}

// MARK: The lock

@Test func visualizer5StartsLockedAndCanBeUnlocked() {
    var values = ControlValues()
    #expect(Fountain.startsLocked)
    #expect(values.isLocked(visual: 5))
    for visual in [3, 4, 6, 7, 8] { #expect(!values.isLocked(visual: visual), "Visualizer \(visual)") }

    values.setLocked(false, visual: 5)
    #expect(!values.isLocked(visual: 5) && !values.isEmpty)
    values.setLocked(true, visual: 5)
    // Locked again is how it started, so nothing needs keeping.
    #expect(values.isLocked(visual: 5) && values.isEmpty)

    values.setLocked(true, visual: 4)
    #expect(values.isLocked(visual: 4) && !values.isLocked(visual: 7))
    values.resetAll()
    #expect(!values.isLocked(visual: 4) && values.isLocked(visual: 5))
}

// MARK: The copies start as the owner's originals do

@Test func theCopiesStartWithTheOwnersSettingsWhereTheyShareThem() {
    let values = ControlValues()
    // Visualizer 8 from Visualizer 5.
    for key in ["amount", "kickBurst", "sparkBrightness", "twinkle", "cameraMovement", "beatPunch", "glow", "brightness", "darkCorners"] {
        let original = Fountain.controls.first { $0.key == key }
        let copy = Jets.controls.first { $0.key == key }
        #expect(original != nil && copy != nil && original?.standard == copy?.standard, "\(key)")
    }
    // Visualizer 7 from Visualizer 4, but for the two that mix the bands together.
    for key in ["speed", "bassPush", "curlSize", "holeSize", "trail", "thickness", "strandBrightness", "cameraMovement", "beatPunch"] {
        let original = Tendrils.controls.first { $0.key == key }
        let copy = Corona.controls.first { $0.key == key }
        #expect(original != nil && copy != nil && original?.standard == copy?.standard, "\(key)")
    }
    #expect(values.value(of: Corona.Control.curl) == Corona.Control.curl.base)
    #expect(values.value(of: Corona.Control.turning) == 0)
    for visual in [7, 8] { #expect(BandPalette(values, visual: visual).changesByItself) }
}
