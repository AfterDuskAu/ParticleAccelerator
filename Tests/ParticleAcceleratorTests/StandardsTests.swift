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
    #expect(fountainHeight.base == 1 && fountainHeight.standard == 1.24)
    #expect(values.value(of: fountainHeight) == 1.24)
    #expect(values.value(of: Fountain.Control.common.cameraMovement) == 1.10)
    #expect(!values.differsFromStandard(visual: 5) && values.differsFromBase(visual: 5))
    // A standard covers the colours too: Visualizer 8's change by themselves.
    #expect(BandPalette(values, visual: 8).changesByItself)
    #expect(!values.differsFromStandard(visual: 8) && values.differsFromBase(visual: 8))
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

@Test func theOwnersStandardsAreAsTheySetThem() {
    // Visualizer 4's is from the owner's screenshot of the morning of 2026-10-04.
    // Visualizers 5, 7 and 8's are what the panel showed for the standards the owner
    // set that afternoon, and Visualizer 8's again later that day (the tests after
    // this have what their app had saved).
    func shown(_ visual: Visual.Type, _ key: String) -> String? {
        let controls = visual.controls + BandPalette.controls(ofVisual: visual.number)
        return controls.first { $0.key == key }.map { $0.text(for: ControlValues().value(of: $0)) }
    }
    let fountain: [String: String] = [
        "height": "1.24×", "spread": "1.56×", "amount": "1.13×", "kickBurst": "2.16×", "gravity": "3.00×",
        "life": "2.50×", "sparkSize": "0.65×", "sparkBrightness": "4.00×", "twinkle": "1.93×",
        "whiteHeat": "3%", "streaks": "1.39×", "floorGlow": "0.17×", "cameraMovement": "1.10×",
        "beatPunch": "0.21×", "glow": "0.24×", "brightness": "0.44×", "darkCorners": "64%",
    ]
    for (key, text) in fountain { #expect(shown(Fountain.self, key) == text, "5.\(key)") }
    #expect(Set(fountain.keys) == Set(Fountain.controls.map(\.key)))
    #expect(shown(Fountain.self, "coloursChange") == "0%" && shown(Fountain.self, "colourSeconds") == "4.68 s")

    let corona: [String: String] = [
        "reach": "1.71×", "tips": "3.71×", "quietPitches": "4.4 dB", "heldSound": "86%",
        "responseWidth": "8.0 bars", "fall": "0.052 s", "speed": "1.03×", "bassPush": "3.30×",
        "curl": "1.84×", "curlSize": "0.31×", "turning": "1.06×", "holeSize": "0.81×", "strands": "4.00×",
        "trail": "0.14 s", "thickness": "0.76×", "strandBrightness": "1.68×", "specks": "3%",
        "twinkle": "0.98×", "cameraMovement": "4.00×", "beatPunch": "1.60×", "glow": "0.30×",
        "brightness": "1.00×", "darkCorners": "50%",
    ]
    for (key, text) in corona { #expect(shown(Corona.self, key) == text, "7.\(key)") }
    #expect(Set(corona.keys) == Set(Corona.controls.map(\.key)))
    #expect(shown(Corona.self, "coloursChange") == "0%" && shown(Corona.self, "colourSeconds") == "4.68 s")

    let jets: [String: String] = [
        "jetsForEachBand": "8", "height": "1.17×", "quickness": "0.51×", "rowWidth": "0.60×",
        "spread": "3.05×", "fan": "4.21×", "amount": "3.74×", "kickBurst": "1.22×", "life": "2.50×",
        "quietPitches": "2.7 dB", "heldSound": "35%", "responseWidth": "1.5 bars", "fall": "0.12 s",
        "sparkSize": "0.61×", "sparkBrightness": "1.43×", "twinkle": "2.00×", "whiteHeat": "5%",
        "streaks": "4.00×", "floorGlow": "0.00×", "cameraMovement": "0.24×", "beatPunch": "0.17×",
        "glow": "0.07×", "brightness": "0.37×", "darkCorners": "100%",
    ]
    for (key, text) in jets { #expect(shown(Jets.self, key) == text, "8.\(key)") }
    #expect(Set(jets.keys) == Set(Jets.controls.map(\.key)))
    #expect(shown(Jets.self, "coloursChange") == "100%" && shown(Jets.self, "colourSeconds") == "4.68 s")

    let tendrils: [String: String] = [
        "speed": "0.47×", "bassPush": "1.26×", "curl": "4.00×", "curlSize": "2.07×", "turning": "3.82×",
        "holeSize": "1.77×", "strands": "1.00×", "trail": "0.050 s", "thickness": "0.90×",
        "strandBrightness": "0.75×", "specks": "3%", "twinkle": "1.00×", "cameraMovement": "4.00×",
        "beatPunch": "0.60×", "glow": "0.30×", "brightness": "1.00×", "darkCorners": "50%",
        "coloursChange": "100%", "colourSeconds": "4.68 s",
    ]
    for (key, text) in tendrils { #expect(shown(Tendrils.self, key) == text, "4.\(key)") }
}

@Test func theOwnersSavedSettingsOfTheMorningStillOpen() throws {
    // What the owner's app had saved on the morning of 2026-10-04, when they asked for
    // Visualizers 4 and 5 to be their standards: the sliders as they'd left them, and
    // one set of colours shared by every visual. Opened now, Visualizer 4 is at its
    // standard with nothing showing as changed, and each visual has the colours as its
    // own. Visualizer 5 has had a newer standard since (the next test), so these
    // sliders of the morning show as what they are: changes from it.
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
    #expect(!values.differsFromStandard(visual: 4))
    for control in Tendrils.controls { #expect(!values.isChanged(control), "\(control.id)") }
    #expect(values.differsFromStandard(visual: 5))
    #expect(values.isChanged(fountainHeight) && abs(values.value(of: fountainHeight) - 1.3747134) < 1e-6)
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

@Test func theOwnersSavedSettingsOfTheAfternoonAreTheStandards() throws {
    // What the owner's app had saved on the afternoon of 2026-10-04, when they asked for
    // Visualizers 5, 7 and 8 as they'd set them: a standard of their own for each
    // ("Set Standard"), and Visualizer 5 unlocked to be tuned again. Those are the
    // library's standards now. So opened now, every control of the three reads as the
    // library has it, and a person with no saved settings sees the same.
    //
    // Later that day the owner set Visualizer 8 again (the next test). The four
    // controls they changed then weren't saved here, being at the library's standard
    // of the time, so here they follow the library's newer one, as anything not saved
    // does.
    let saved = """
        {"limitsFlashing":true,"controls":{"numbers":{"6.speed":2.6521173,"4.strandBrightness":0.752131,\
        "6.heads":0,"4.holeSize":1.7655804,"4.colourSeconds":4.677037,"6.spread":0.35046774,\
        "4.coloursChange":1,"4.curlSize":3,"6.flow":2.3066504,"4.thickness":0.8966921,"4.trail":0.05,\
        "4.speed":0.7197942,"6.trail":1.06116,"6.streams":50.210663,"4.bassPush":1.2574229,\
        "4.cameraMovement":0,"6.reach":0.42199108,"4.turning":4.518806,"4.beatPunch":0.59638566},\
        "colours":{},"standardColours":{},"standardNumbers":{"7.quietPitches":4.4195414,\
        "8.quickness":0.5068112,"5.height":1.2432789,"5.colourSeconds":4.677037,"8.jetsForEachBand":8,\
        "6.beatPunch":0.49069795,"5.cameraMovement":1.1017061,"8.cameraMovement":0.2352995,\
        "3.quietPitches":5.3419714,"5.twinkle":1.9324592,"3.floating":0.01924233,"8.sparkSize":0.61326164,\
        "7.turning":1.0622137,"3.lineThickness":5.768134,"3.cameraMovement":0.63102454,\
        "3.peakWidth":3.5412939,"5.kickBurst":2.1631,"8.spread":3.04733,"8.twinkle":2,\
        "8.whiteHeat":0.047033582,"7.tips":3.708022,"7.holeSize":0.80711305,"3.lineBrightness":0.119300395,\
        "3.colourSeconds":4.677037,"5.amount":1.1270142,"7.coloursChange":0,"3.rise":0.0155228535,\
        "7.speed":1.032677,"8.life":2.5,"8.rowWidth":0.60253716,"5.coloursChange":0,"8.floorGlow":0,\
        "3.reflection":1,"5.sparkSize":0.6512971,"3.streaks":3.3625488,"6.slowing":1.569126,\
        "5.beatPunch":0.20553482,"7.bassPush":3.2986677,"7.heldSound":0.86074185,"3.fullness":2.5,\
        "6.sparkSize":0.53684264,"6.twinkle":2,"3.fall":0.11295794,"3.tremble":2.7926297,\
        "3.sparkSize":0.5940413,"6.droop":6,"6.cameraMovement":4,"5.whiteHeat":0.0265527,"6.life":2.5,\
        "8.amount":3.7413692,"7.beatPunch":1.599056,"6.kickBurst":0.57186544,"3.peakHeight":0.57588667,\
        "5.floorGlow":0.16587022,"3.coloursChange":1,"6.sparkBrightness":0.42201707,"7.responseWidth":8,\
        "3.drift":0.62902117,"8.kickBurst":1.2167834,"7.curl":1.8424718,"5.spread":1.5581821,\
        "7.strandBrightness":1.6842536,"3.twinkle":2,"8.height":1.1660613,"7.thickness":0.7614616,\
        "3.heldSound":0.1,"7.strands":4,"5.sparkBrightness":4,"3.ripple":2.8888228,"3.lineGlow":0,\
        "7.trail":0.13750051,"6.colourSeconds":4.677037,"5.streaks":1.3933034,"7.curlSize":0.31111592,\
        "6.whiteness":0.045372114,"5.darkCorners":0.64368594,"7.fall":0.05221963,"6.brightFor":0.5960067,\
        "3.sparkBrightness":0.64240277,"7.twinkle":0.978337,"6.blur":0,"8.beatPunch":0.17024097,\
        "3.beatPunch":0.6946492,"6.streaks":2.00731,"5.brightness":0.43532255,"7.specks":0.03013198,\
        "8.streaks":4,"5.life":2.5,"7.reach":1.7135773,"8.fan":4.212895,"6.launchSpeed":0.5357151,\
        "6.turning":6,"6.amount":4,"8.sparkBrightness":1.4327991,"5.glow":0.23721966,\
        "6.centreGlow":0.56973255},"locks":{"5":false}},"quality":"medium","showsFrameTime":true,\
        "visual":7}
        """
    let settings = try JSONDecoder().decode(AcceleratorSettings.self, from: Data(saved.utf8))
    let values = settings.controls
    let nothingSaved = ControlValues()
    for visual in [5, 7, 8] {
        #expect(!values.differsFromStandard(visual: visual), "Visualizer \(visual)")
        for control in StageRenderer.controls(ofVisual: visual) + BandPalette.controls(ofVisual: visual) {
            // The owner's own standard, and the library's.
            #expect(control.readsTheSame(values.standard(of: control), control.standard), "\(control.id)")
            #expect(control.readsTheSame(values.value(of: control), nothingSaved.value(of: control)), "\(control.id)")
        }
    }
    #expect(!BandPalette(values, visual: 5).changesByItself && !BandPalette(nothingSaved, visual: 5).changesByItself)
    #expect(!BandPalette(values, visual: 7).changesByItself && !BandPalette(nothingSaved, visual: 7).changesByItself)
    #expect(BandPalette(values, visual: 8).changesByItself && BandPalette(nothingSaved, visual: 8).changesByItself)
    // The owner had unlocked Visualizer 5 to tune it. For anyone else it still starts
    // locked.
    #expect(!values.isLocked(visual: 5) && nothingSaved.isLocked(visual: 5))
    let again = try JSONDecoder().decode(AcceleratorSettings.self, from: JSONEncoder().encode(settings))
    #expect(again == settings)
}

@Test func theOwnersLaterSavedSettingsAreVisualizer8sStandard() throws {
    // The part about Visualizer 8 of what the owner's app had saved later on
    // 2026-10-04, when they'd set its standard again and locked it ("visualizer 8
    // standard/lock"): only the strongest pitches showing, a darker picture with
    // hardly any glow, and corners as dark as they go. That's the library's standard
    // now, and Visualizer 8 starts locked.
    let saved = """
        {"controls":{"standardNumbers":{"8.amount":3.7413692,"8.beatPunch":0.17024097,\
        "8.brightness":0.36753595,"8.cameraMovement":0.2352995,"8.darkCorners":1,"8.fan":4.212895,\
        "8.floorGlow":0,"8.glow":0.06512586,"8.height":1.1660613,"8.jetsForEachBand":8,\
        "8.kickBurst":1.2167834,"8.life":2.5,"8.quickness":0.5068112,"8.quietPitches":2.675643,\
        "8.rowWidth":0.60253716,"8.sparkBrightness":1.4327991,"8.sparkSize":0.61326164,"8.spread":3.04733,\
        "8.streaks":4,"8.twinkle":2,"8.whiteHeat":0.047033582},"locks":{"8":true,"5":false}},\
        "quality":"medium","visual":8}
        """
    let settings = try JSONDecoder().decode(AcceleratorSettings.self, from: Data(saved.utf8))
    let values = settings.controls
    let nothingSaved = ControlValues()
    #expect(!values.differsFromStandard(visual: 8))
    for control in Jets.controls + BandPalette.controls(ofVisual: 8) {
        #expect(control.readsTheSame(values.standard(of: control), control.standard), "\(control.id)")
        #expect(control.readsTheSame(values.value(of: control), nothingSaved.value(of: control)), "\(control.id)")
    }
    #expect(values.isLocked(visual: 8) && nothingSaved.isLocked(visual: 8))
    #expect(nothingSaved.value(of: Jets.Control.response.quietPitches) == 2.68)
    #expect(nothingSaved.value(of: Jets.Control.common.darkCorners) == 1)
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
    #expect(!values.isChanged(BandPalette.changesControl(ofVisual: 5)))

    values.resetToStandard(visual: 5)
    #expect(values.value(of: fountainHeight) == 1.24)
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
    #expect(values.isChanged(fountainHeight) && values.standard(of: fountainHeight) == 1.24)
    values.resetToStandard(visual: 5)
    #expect(values.value(of: height) == 0.5 && values.value(of: fountainHeight) == 1.24)
    values.resetToBase(visual: 5)
    #expect(values.standard(of: height) == 0.5)
}

@Test func aSettingThatReadsTheSameAsTheStandardIsNotAChange() {
    // A slider can land a hair away from a setting that reads the same: 1.2433 is
    // shown as 1.24×, and so is the standard.
    var values = ControlValues()
    values.set(1.2433, for: fountainHeight)
    #expect(values.value(of: fountainHeight) == 1.2433)
    #expect(!values.isChanged(fountainHeight) && !values.differsFromStandard(visual: 5))
    values.set(1.25, for: fountainHeight)
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

@Test func visualizers5And8StartLockedAndCanBeUnlocked() {
    var values = ControlValues()
    #expect(Fountain.startsLocked && Jets.startsLocked)
    #expect(values.isLocked(visual: 5) && values.isLocked(visual: 8))
    for visual in [3, 4, 6, 7] { #expect(!values.isLocked(visual: visual), "Visualizer \(visual)") }

    values.setLocked(false, visual: 8)
    #expect(!values.isLocked(visual: 8) && values.isLocked(visual: 5) && !values.isEmpty)
    values.setLocked(true, visual: 8)
    #expect(values.isLocked(visual: 8) && values.isEmpty)

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

// MARK: The copies have standards of their own

@Test func theCopiesNoLongerFollowTheirOriginals() {
    // Visualizers 7 and 8 began with their originals' standards in everything they
    // shared. The owner has since tuned each for itself (2026-10-04), down to the two
    // controls that mix Visualizer 7's bands together, Curl and Turning, which had
    // been left at their base.
    let values = ControlValues()
    #expect(values.value(of: Corona.Control.curl) == 1.84 && values.value(of: Corona.Control.turning) == 1.06)
    #expect(values.value(of: Corona.Control.speed) != values.value(of: Tendrils.Control.speed))
    #expect(values.value(of: Jets.Control.amount) != values.value(of: Fountain.Control.amount))
    #expect(!BandPalette(values, visual: 7).changesByItself && BandPalette(values, visual: 8).changesByItself)
    // Visualizer 8 is locked in. Visualizer 7 isn't: it's still the owner's to shape.
    #expect(!values.isLocked(visual: 7) && values.isLocked(visual: 8))
}
