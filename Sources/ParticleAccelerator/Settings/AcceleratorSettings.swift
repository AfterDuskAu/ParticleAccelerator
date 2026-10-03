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

    public init() {}
}
