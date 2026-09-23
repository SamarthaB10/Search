import SwiftUI

/// A group holds open tabs, not a second set of saved links. Its name is nil
/// until someone names it, so numbered names can follow the groups' order.
struct TabGroup: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String?
    var color = 0
    var expanded = true

    static let colors: [(String, Color)] = [
        ("Red", Color(red: 0.78, green: 0.40, blue: 0.38)),
        ("Orange", Color(red: 0.82, green: 0.51, blue: 0.30)),
        ("Yellow", Color(red: 0.77, green: 0.64, blue: 0.27)),
        ("Green", Color(red: 0.39, green: 0.66, blue: 0.43)),
        ("Mint", Color(red: 0.32, green: 0.68, blue: 0.60)),
        ("Cyan", Color(red: 0.30, green: 0.64, blue: 0.72)),
        ("Blue", Color(red: 0.39, green: 0.55, blue: 0.80)),
        ("Purple", Color(red: 0.59, green: 0.48, blue: 0.76)),
        ("Pink", Color(red: 0.77, green: 0.46, blue: 0.64)),
        ("Grey", Color(red: 0.55, green: 0.57, blue: 0.60)),
    ]

    var tint: Color { Self.colors[min(max(color, 0), Self.colors.count - 1)].1 }
}

enum TabItem: Identifiable {
    case tab(Tab)
    case group(TabGroup)

    var id: String {
        switch self {
        case .tab(let tab): return "tab-\(tab.id)"
        case .group(let group): return "group-\(group.id)"
        }
    }
}
