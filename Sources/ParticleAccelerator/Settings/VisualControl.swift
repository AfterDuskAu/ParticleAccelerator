import Foundation
import simd

/// One thing about a visual that a person can change while it plays: a number with a
/// name, a range and the visual's own settings for it.
///
/// Each visual lists its controls (`ParticleWave.controls`), and the controls panel
/// (`AcceleratorControls`) is drawn from that list. So a new visual gets a panel by
/// listing its controls, with nothing else to write.
///
/// A control has two settings of the visual's own (the owner, 2026-10-04):
/// - its **base**: the plain first setting, which "Reset All" goes back to;
/// - its **standard**: what the visual shows until a person changes it, and what
///   "Reset to Standard" goes back to. It's the base unless the visual says otherwise
///   (`Visual.standard`), and a person can set a standard of their own.
struct VisualControl: Identifiable, Equatable {
    /// What the number means, for showing it: "1.2×", "0.11 s", "55%", "64".
    enum Unit {
        case times, seconds, decibels, bars, share, count
    }

    /// The visual it belongs to (docs/VISUALS.md).
    let visual: Int
    /// Its name in saved settings. Never changed once a version is out, or saved
    /// settings would lose it.
    let key: String
    /// Unique among every visual's controls: "3.peakHeight".
    let id: String
    /// What the panel calls it, and the heading it goes under.
    let name: String
    let group: String
    let unit: Unit
    let range: ClosedRange<Float>
    let base: Float
    let standard: Float
    /// True when the slider should give as much room to 0.1–0.2 as to 1–2: for times
    /// and for "so many times as big".
    let spreadsEvenlyByRatio: Bool
    /// One plain sentence on what it does, shown when the pointer rests on it.
    let help: String

    /// - Parameter standard: the visual's standard for it, or nil if that's its base.
    init(
        visual: Int, key: String, name: String, group: String, unit: Unit, range: ClosedRange<Float>,
        base: Float, standard: Float? = nil, spreadsEvenlyByRatio: Bool = false, help: String
    ) {
        self.visual = visual
        self.key = key
        id = "\(visual).\(key)"
        self.name = name
        self.group = group
        self.unit = unit
        self.range = range
        self.base = base
        self.standard = min(range.upperBound, max(range.lowerBound, standard ?? base))
        self.spreadsEvenlyByRatio = spreadsEvenlyByRatio
        self.help = help
    }

    /// A value kept inside the control's range.
    func clamped(_ value: Float) -> Float {
        min(range.upperBound, max(range.lowerBound, value))
    }

    /// A value as the panel shows it.
    func text(for value: Float) -> String {
        switch unit {
        case .times: return String(format: "%.2f×", value)
        case .seconds: return String(format: value < 0.1 ? "%.3f s" : value < 10 ? "%.2f s" : "%.0f s", value)
        case .decibels: return String(format: "%.1f dB", value)
        case .bars: return String(format: "%.1f bars", value)
        case .share: return "\(Int((value * 100).rounded()))%"
        case .count: return "\(Int(value.rounded()))"
        }
    }

    /// True when two values read the same in the panel. Two settings a person can't
    /// tell apart count as the same setting.
    func readsTheSame(_ one: Float, _ other: Float) -> Bool {
        one == other || text(for: one) == text(for: other)
    }

    /// Where a value sits along the slider, from 0 to 1, and back again.
    func sliderPlace(of value: Float) -> Double {
        let value = clamped(value)
        if spreadsEvenlyByRatio, range.lowerBound > 0 {
            return Double(log(value / range.lowerBound) / log(range.upperBound / range.lowerBound))
        }
        return Double((value - range.lowerBound) / (range.upperBound - range.lowerBound))
    }

    func value(atSliderPlace place: Double) -> Float {
        let place = Float(min(1, max(0, place)))
        if spreadsEvenlyByRatio, range.lowerBound > 0 {
            return range.lowerBound * pow(range.upperBound / range.lowerBound, place)
        }
        return range.lowerBound + (range.upperBound - range.lowerBound) * place
    }
}

/// A person's own changes to the visuals: the controls they've moved, the colours
/// they've picked, the standards they've set and the visuals they've locked.
///
/// Only what differs is kept. Anything a person hasn't touched follows the visual's
/// own standard, so when that gets better in a later version, theirs follows.
///
/// It's part of `AcceleratorSettings`, and saved with it.
public struct ControlValues: Codable, Equatable, Sendable {
    /// Controls that differ from their standard, by the control's id ("3.peakHeight").
    private var numbers: [String: Float] = [:]
    /// Band colours that differ from their standard, by visual and band ("5.kick"):
    /// red, green and blue from 0 to 1, as a screen shows them.
    private var colours: [String: [Float]] = [:]
    /// The standards a person has set themselves ("Set Standard"), where they differ
    /// from the visual's own, under the same names.
    private var standardNumbers: [String: Float] = [:]
    private var standardColours: [String: [Float]] = [:]
    /// Visuals a person has locked or unlocked, by number ("5"), where that differs
    /// from how the visual starts.
    private var locks: [String: Bool] = [:]

    public init() {}

    /// True when nothing has been changed, set or locked.
    public var isEmpty: Bool {
        numbers.isEmpty && colours.isEmpty && standardNumbers.isEmpty && standardColours.isEmpty && locks.isEmpty
    }

    /// Forgets everything a person changed, set or locked: every visual is back as
    /// the library has it.
    public mutating func resetAll() {
        self = ControlValues()
    }

    private enum CodingKeys: String, CodingKey {
        case numbers, colours, standardNumbers, standardColours, locks
    }

    public init(from decoder: Decoder) throws {
        // Settings saved by an older or newer version may lack any part.
        let saved = try decoder.container(keyedBy: CodingKeys.self)
        numbers = try saved.decodeIfPresent([String: Float].self, forKey: .numbers) ?? [:]
        colours = try saved.decodeIfPresent([String: [Float]].self, forKey: .colours) ?? [:]
        standardNumbers = try saved.decodeIfPresent([String: Float].self, forKey: .standardNumbers) ?? [:]
        standardColours = try saved.decodeIfPresent([String: [Float]].self, forKey: .standardColours) ?? [:]
        locks = try saved.decodeIfPresent([String: Bool].self, forKey: .locks) ?? [:]
        giveEachVisualTheColoursTheyShared()
    }

    /// Until 2026-10-04 every visual shared one set of colours, saved under no visual's
    /// number. Each visual that existed then is given them as its own, so every visual
    /// still looks as the person left it.
    private mutating func giveEachVisualTheColoursTheyShared() {
        let visualsThen = [3, 4, 5, 6]
        for key in [BandPalette.changesKey, BandPalette.secondsKey] {
            guard let shared = numbers.removeValue(forKey: "0.\(key)") else { continue }
            for visual in visualsThen where numbers["\(visual).\(key)"] == nil {
                numbers["\(visual).\(key)"] = shared
            }
        }
        for band in Band.allCases {
            guard let shared = colours.removeValue(forKey: band.savedName) else { continue }
            for visual in visualsThen where colours[Self.name(of: band, in: visual)] == nil {
                colours[Self.name(of: band, in: visual)] = shared
            }
        }
    }
}

// MARK: One control

extension ControlValues {
    /// The control's standard: the person's own if they've set one, or else the
    /// visual's.
    func standard(of control: VisualControl) -> Float {
        guard let own = standardNumbers[control.id], own.isFinite else { return control.standard }
        return control.clamped(own)
    }

    /// The control's value: the person's own if they've changed it, or else its
    /// standard.
    func value(of control: VisualControl) -> Float {
        guard let own = numbers[control.id], own.isFinite else { return standard(of: control) }
        return control.clamped(own)
    }

    /// True when the control reads differently from its standard.
    func isChanged(_ control: VisualControl) -> Bool {
        numbers[control.id] != nil && !control.readsTheSame(value(of: control), standard(of: control))
    }

    mutating func set(_ value: Float, for control: VisualControl) {
        let value = control.clamped(value)
        numbers[control.id] = value == standard(of: control) ? nil : value
    }

    /// Puts the control back to its standard.
    mutating func reset(_ control: VisualControl) {
        numbers[control.id] = nil
    }
}

// MARK: One band's colour in one visual

extension ControlValues {
    private static func name(of band: Band, in visual: Int) -> String {
        "\(visual).\(band.savedName)"
    }

    /// A saved colour, if it makes sense.
    private static func colour(_ saved: [Float]?) -> SIMD3<Float>? {
        guard let saved, saved.count == 3, saved.allSatisfy(\.isFinite) else { return nil }
        return simd_clamp(SIMD3(saved[0], saved[1], saved[2]), SIMD3(repeating: 0), SIMD3(repeating: 1))
    }

    /// The band's standard colour in a visual: the person's own if they've set one, or
    /// else the band's.
    func standardColour(of band: Band, in visual: Int) -> SIMD3<Float> {
        Self.colour(standardColours[Self.name(of: band, in: visual)]) ?? band.colour
    }

    /// The band's colour in a visual: the person's own if they've picked one, or else
    /// its standard.
    func colour(of band: Band, in visual: Int) -> SIMD3<Float> {
        Self.colour(colours[Self.name(of: band, in: visual)]) ?? standardColour(of: band, in: visual)
    }

    func isColourChanged(_ band: Band, in visual: Int) -> Bool {
        colour(of: band, in: visual) != standardColour(of: band, in: visual)
    }

    mutating func setColour(_ colour: SIMD3<Float>, for band: Band, in visual: Int) {
        let isStandard = colour == standardColour(of: band, in: visual)
        colours[Self.name(of: band, in: visual)] = isStandard ? nil : [colour.x, colour.y, colour.z]
    }

    /// Puts the band's colour back to its standard.
    mutating func resetColour(of band: Band, in visual: Int) {
        colours[Self.name(of: band, in: visual)] = nil
    }
}

// MARK: A whole visual: its standard and its lock

extension ControlValues {
    /// Everything about a visual that's a number: its controls, and whether and how
    /// fast its colours change.
    private static func everyControl(ofVisual visual: Int) -> [VisualControl] {
        StageRenderer.controls(ofVisual: visual) + BandPalette.controls(ofVisual: visual)
    }

    /// True when anything about the visual reads differently from its standard.
    func differsFromStandard(visual: Int) -> Bool {
        Self.everyControl(ofVisual: visual).contains { isChanged($0) }
            || Band.allCases.contains { isColourChanged($0, in: visual) }
    }

    /// True when anything about the visual reads differently from its base.
    func differsFromBase(visual: Int) -> Bool {
        Self.everyControl(ofVisual: visual).contains { !$0.readsTheSame(value(of: $0), $0.base) }
            || Band.allCases.contains { colour(of: $0, in: visual) != $0.colour }
    }

    /// "Reset to Standard": every control and colour of the visual goes back to its
    /// standard.
    mutating func resetToStandard(visual: Int) {
        for control in Self.everyControl(ofVisual: visual) { reset(control) }
        for band in Band.allCases { resetColour(of: band, in: visual) }
    }

    /// "Reset All": every control and colour of the visual goes back to its base, the
    /// plain first settings. Its standard is left as it is, to come back to.
    mutating func resetToBase(visual: Int) {
        for control in Self.everyControl(ofVisual: visual) { set(control.base, for: control) }
        for band in Band.allCases { setColour(band.colour, for: band, in: visual) }
    }

    /// "Set Standard": the visual's settings as they are now become its standard.
    mutating func setStandard(visual: Int) {
        for control in Self.everyControl(ofVisual: visual) {
            let now = value(of: control)
            standardNumbers[control.id] = now == control.standard ? nil : now
            numbers[control.id] = nil
        }
        for band in Band.allCases {
            let now = colour(of: band, in: visual)
            let name = Self.name(of: band, in: visual)
            standardColours[name] = now == band.colour ? nil : [now.x, now.y, now.z]
            colours[name] = nil
        }
    }

    /// Whether the visual's controls are locked, so nothing is moved by accident. The
    /// controls panel honours it; the settings themselves can still be changed in code.
    func isLocked(visual: Int) -> Bool {
        locks["\(visual)"] ?? StageRenderer.startsLocked(visual: visual)
    }

    mutating func setLocked(_ isLocked: Bool, visual: Int) {
        locks["\(visual)"] = isLocked == StageRenderer.startsLocked(visual: visual) ? nil : isLocked
    }
}

extension Band {
    /// The band's name in saved settings. Never changed, or saved colours would be lost.
    var savedName: String {
        switch self {
        case .sub: return "sub"
        case .kick: return "kick"
        case .lowMids: return "lowMids"
        case .mids: return "mids"
        case .vocals: return "vocals"
        case .air: return "air"
        }
    }

    /// A colour as a screen shows it, as amounts of light, which is what the shaders add
    /// up. (A screen's numbers aren't amounts of light: half the number is about a
    /// fifth of the light.)
    static func light(of colour: SIMD3<Float>) -> SIMD3<Float> {
        func asLight(_ shown: Float) -> Float {
            shown <= 0.04045 ? shown / 12.92 : pow((shown + 0.055) / 1.055, 2.4)
        }
        return SIMD3(asLight(colour.x), asLight(colour.y), asLight(colour.z))
    }
}
