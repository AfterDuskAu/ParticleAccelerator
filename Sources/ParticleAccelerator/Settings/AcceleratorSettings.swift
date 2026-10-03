/// How much the stage draws: how many particles, and how big a picture
/// (docs/OUTPUT.md).
public enum Quality: String, Codable, CaseIterable, Sendable {
    /// Picks for this Mac.
    case auto
    case low, medium, high, ultra
}

/// Everything a person can choose about the visuals. A host app saves it wherever it
/// keeps its own settings: the library saves nothing itself.
public struct AcceleratorSettings: Codable, Equatable, Sendable {
    /// Which visual to show, by its number (`Visuals.all`).
    public var visual: Int = 3
    public var quality: Quality = .auto
    /// Keeps whole-screen flashes to three a second at most, for people sensitive to
    /// flashing light. On unless the person turns it off.
    public var limitsFlashing: Bool = true
    /// Shows how long each frame takes, in a corner.
    public var showsFrameTime: Bool = false
    /// The person's own changes to the visuals' controls and colours
    /// (`AcceleratorControls` is the panel that changes them).
    public var controls = ControlValues()

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case visual, quality, limitsFlashing, showsFrameTime, controls
    }

    public init(from decoder: Decoder) throws {
        // Settings saved by an older version lack whatever has been added since. Each
        // missing one starts as it would in new settings, and the rest are kept.
        let fresh = AcceleratorSettings()
        let saved = try decoder.container(keyedBy: CodingKeys.self)
        visual = try saved.decodeIfPresent(Int.self, forKey: .visual) ?? fresh.visual
        quality = try saved.decodeIfPresent(Quality.self, forKey: .quality) ?? fresh.quality
        limitsFlashing = try saved.decodeIfPresent(Bool.self, forKey: .limitsFlashing) ?? fresh.limitsFlashing
        showsFrameTime = try saved.decodeIfPresent(Bool.self, forKey: .showsFrameTime) ?? fresh.showsFrameTime
        controls = try saved.decodeIfPresent(ControlValues.self, forKey: .controls) ?? fresh.controls
    }
}
