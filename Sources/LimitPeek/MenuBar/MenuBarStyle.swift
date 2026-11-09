import Foundation

/// What the menu bar item shows: the gauge, the percentage, or both.
enum MenuBarStyle: String, CaseIterable, Sendable {
    case both
    case bar
    case percentage

    var showsBar: Bool { self != .percentage }
    var showsPercentage: Bool { self != .bar }

    var title: String {
        switch self {
        case .both: "Bar and Percentage"
        case .bar: "Bar Only"
        case .percentage: "Percentage Only"
        }
    }

    private static let defaultsKey = "menuBarStyle"

    static var saved: MenuBarStyle {
        get { UserDefaults.standard.string(forKey: defaultsKey).flatMap(MenuBarStyle.init) ?? .both }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey) }
    }
}
