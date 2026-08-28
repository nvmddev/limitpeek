/// What the menu bar item shows: the gauge, the percentage, or both.
enum MenuBarStyle: String, CaseIterable, Identifiable {
    case both
    case bar
    case percentage

    /// Read by the popover and by the label renderer, so the string lives in
    /// one place.
    static let defaultsKey = "menuBarStyle"

    var id: Self { self }
    var showsBar: Bool { self != .percentage }
    var showsPercentage: Bool { self != .bar }

    /// Short enough for three segments inside the popover's width.
    var shortTitle: String {
        switch self {
        case .both: "Bar + %"
        case .bar: "Bar"
        case .percentage: "%"
        }
    }
}
