import Foundation
import simd

/// One thing about a visual that a person can change while it plays: a number with a
/// name, a range and the visual's own setting for it.
///
/// Each visual lists its controls (`ParticleWave.controls`), and the controls panel
/// (`AcceleratorControls`) is drawn from that list. So a new visual gets a panel by
/// listing its controls, with nothing else to write.
struct VisualControl: Identifiable, Equatable {
    /// What the number means, for showing it: "1.2×", "0.11 s", "55%".
    enum Unit {
        case times, seconds, decibels, bars, share
    }

    /// The visual it belongs to (docs/VISUALS.md).
    let visual: Int
    /// Its name in saved settings. Never changed once a version is out, or saved
    /// settings would lose it.
    let key: String
    /// What the panel calls it, and the heading it goes under.
    let name: String
    let group: String
    let unit: Unit
    let range: ClosedRange<Float>
    /// The visual's own setting.
    let usual: Float
    /// True when the slider should give as much room to 0.1–0.2 as to 1–2: for times
    /// and for "so many times as big".
    let spreadsEvenlyByRatio: Bool
    /// One plain sentence on what it does, shown when the pointer rests on it.
    let help: String

    init(
        visual: Int, key: String, name: String, group: String, unit: Unit, range: ClosedRange<Float>,
        usual: Float, spreadsEvenlyByRatio: Bool = false, help: String
    ) {
        self.visual = visual
        self.key = key
        self.name = name
        self.group = group
        self.unit = unit
        self.range = range
        self.usual = usual
        self.spreadsEvenlyByRatio = spreadsEvenlyByRatio
        self.help = help
    }

    /// Unique among every visual's controls: "3.peakHeight".
    var id: String { "\(visual).\(key)" }

    /// A value as the panel shows it.
    func text(for value: Float) -> String {
        switch unit {
        case .times: return String(format: "%.2f×", value)
        case .seconds: return String(format: value < 0.1 ? "%.3f s" : "%.2f s", value)
        case .decibels: return String(format: "%.1f dB", value)
        case .bars: return String(format: "%.1f bars", value)
        case .share: return "\(Int((value * 100).rounded()))%"
        }
    }

    /// Where a value sits along the slider, from 0 to 1, and back again.
    func sliderPlace(of value: Float) -> Double {
        let value = min(range.upperBound, max(range.lowerBound, value))
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

/// A person's own changes to the visuals: the controls they've moved and the colours
/// they've picked. Anything they haven't touched keeps the visual's own setting, so
/// when a visual's own settings get better in a later version, theirs follow.
///
/// It's part of `AcceleratorSettings`, and saved with it.
public struct ControlValues: Codable, Equatable, Sendable {
    /// Changed controls, by the control's id ("3.peakHeight").
    private var numbers: [String: Float] = [:]
    /// Changed band colours, by the band's name: red, green and blue from 0 to 1, as a
    /// screen shows them.
    private var colours: [String: [Float]] = [:]

    public init() {}

    /// True when nothing has been changed.
    public var isEmpty: Bool { numbers.isEmpty && colours.isEmpty }

    /// Puts everything back to the visuals' own settings.
    public mutating func resetAll() {
        numbers = [:]
        colours = [:]
    }

    private enum CodingKeys: String, CodingKey {
        case numbers, colours
    }

    public init(from decoder: Decoder) throws {
        // Settings saved by an older or newer version may lack either part.
        let saved = try decoder.container(keyedBy: CodingKeys.self)
        numbers = try saved.decodeIfPresent([String: Float].self, forKey: .numbers) ?? [:]
        colours = try saved.decodeIfPresent([String: [Float]].self, forKey: .colours) ?? [:]
    }
}

extension ControlValues {
    /// The control's value: the person's own if they've changed it, kept inside the
    /// control's range, or else the visual's.
    func value(of control: VisualControl) -> Float {
        guard let own = numbers[control.id], own.isFinite else { return control.usual }
        return min(control.range.upperBound, max(control.range.lowerBound, own))
    }

    func isChanged(_ control: VisualControl) -> Bool {
        numbers[control.id] != nil
    }

    mutating func set(_ value: Float, for control: VisualControl) {
        let value = min(control.range.upperBound, max(control.range.lowerBound, value))
        numbers[control.id] = value
    }

    mutating func reset(_ control: VisualControl) {
        numbers[control.id] = nil
    }

    /// A band's colour: the person's own if they've picked one, or else the band's.
    func colour(of band: Band) -> SIMD3<Float> {
        guard let own = colours[band.savedName], own.count == 3, own.allSatisfy(\.isFinite) else {
            return band.colour
        }
        return simd_clamp(SIMD3(own[0], own[1], own[2]), SIMD3(repeating: 0), SIMD3(repeating: 1))
    }

    func isColourChanged(_ band: Band) -> Bool {
        colours[band.savedName] != nil
    }

    mutating func setColour(_ colour: SIMD3<Float>, for band: Band) {
        colours[band.savedName] = [colour.x, colour.y, colour.z]
    }

    mutating func resetColour(of band: Band) {
        colours[band.savedName] = nil
    }

    /// True when any of these controls, or any colour, has been changed.
    func hasChanges(among controls: [VisualControl]) -> Bool {
        !colours.isEmpty || controls.contains { isChanged($0) }
    }

    /// Puts these controls, and the colours, back to the visual's own.
    mutating func reset(_ controls: [VisualControl]) {
        for control in controls { numbers[control.id] = nil }
        colours = [:]
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
