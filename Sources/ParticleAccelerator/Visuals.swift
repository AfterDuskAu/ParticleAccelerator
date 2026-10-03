/// What this version of the library is. Shown in the app's About box and by hosts.
public enum Accelerator {
    public static let version = "0.1.0"
}

/// One visual, as the app's menus show it.
public struct VisualInfo: Identifiable, Hashable, Sendable {
    /// Given in the order the reference pictures arrived (docs/VISUALS.md), never reused.
    public let number: Int
    /// What the visual is called in the docs. Menus don't show it yet (see `title`).
    public let name: String
    /// False until it's built: menus list it as coming.
    public let isBuilt: Bool

    public var id: Int { number }
    /// What menus show: the number only for now, such as "Visualizer 3". The names can
    /// come into the menus later, once more visuals are built (owner, 2026-10-03).
    public var title: String { "Visualizer \(number)" }
}

/// Every visual, built or planned, in number order.
public enum Visuals {
    public static let all: [VisualInfo] = [
        VisualInfo(number: 1, name: "Ring & Ink", isBuilt: false),
        VisualInfo(number: 2, name: "Iron Maw", isBuilt: false),
        VisualInfo(number: 3, name: "Particle Wave", isBuilt: false),
        VisualInfo(number: 4, name: "Tendrils", isBuilt: false),
        VisualInfo(number: 5, name: "Fountain", isBuilt: false),
        VisualInfo(number: 6, name: "Starburst", isBuilt: false),
    ]
}
