import SwiftUI

/// One grid for the whole panel, so text, gauges, separators and row
/// highlights share the same edges.
enum PanelMetrics {
    static let width: CGFloat = 320
    /// The edge every text, gauge and separator starts and ends on.
    static let margin: CGFloat = 14
    /// How far a row highlight sits from the panel edge, as in a system menu.
    static let highlightInset: CGFloat = 5
    static let highlightRadius: CGFloat = 7
    static let rowHeight: CGFloat = 24
    /// The menu bar extra window's own corner on macOS 26 and later.
    static let cornerRadius: CGFloat = 6
}

extension View {
    /// Liquid Glass lets whatever sits behind the menu bar extra show through,
    /// so over a dark window a light popover turns mid-gray and the palette's
    /// fixed colors lose their contrast. The material behind system menus stays
    /// as light or as dark as the appearance, and follows Reduce Transparency
    /// and Increase Contrast on its own.
    @ViewBuilder
    func panelBackground() -> some View {
        if #available(macOS 26, *) {
            background(MenuMaterial()
                .clipShape(RoundedRectangle(cornerRadius: PanelMetrics.cornerRadius,
                                            style: .continuous)))
        } else {
            self
        }
    }
}

private struct MenuMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .menu
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// The app glyph beside a bold title and a secondary line, like the header of
/// a system menu bar extra.
struct PanelHeader: View {
    let title: String
    var subtitle: String?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 10) {
            AppGlyph()
                .fill(Palette.glyph(for: colorScheme))
                .frame(width: 26, height: 26 / AppGlyph.aspectRatio)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.headline)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, PanelMetrics.margin)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

struct PanelSeparator: View {
    var body: some View {
        Divider()
            .padding(.horizontal, PanelMetrics.margin)
            .padding(.vertical, 5)
    }
}

/// A menu-item-sized line: the title on the leading edge, an accessory on the
/// trailing edge. Text accessories align on the title's baseline, controls on
/// its center.
struct PanelRow<Accessory: View>: View {
    let title: String
    var alignment: VerticalAlignment = .firstTextBaseline
    var isHighlighted = false
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        HStack(alignment: alignment, spacing: 8) {
            Text(title)
            Spacer(minLength: 8)
            accessory()
        }
        .frame(minHeight: PanelMetrics.rowHeight)
        .padding(.horizontal, PanelMetrics.margin - PanelMetrics.highlightInset)
        .background {
            if isHighlighted {
                RoundedRectangle(cornerRadius: PanelMetrics.highlightRadius, style: .continuous)
                    .fill(.quaternary)
            }
        }
        .padding(.horizontal, PanelMetrics.highlightInset)
        .contentShape(.rect)
    }
}

extension PanelRow where Accessory == EmptyView {
    init(title: String, isHighlighted: Bool = false) {
        self.init(title: title, isHighlighted: isHighlighted) { EmptyView() }
    }
}

/// A button that looks and behaves like a menu item: no chrome, a highlight
/// under the pointer, and the shortcut or a status on the trailing edge.
/// SwiftUI has no menu-item button style for a window-style menu bar extra.
struct MenuActionRow: View {
    let title: String
    var trailing: String?
    var shortcut: Character?
    let action: () -> Void

    @State private var isHovering = false
    @Environment(\.isEnabled) private var isEnabled

    init(title: String,
         trailing: String? = nil,
         shortcut: Character? = nil,
         action: @escaping () -> Void) {
        self.title = title
        self.trailing = trailing
        self.shortcut = shortcut
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            PanelRow(title: title, isHighlighted: isHovering && isEnabled) {
                if let detail = trailing ?? shortcut.map({ "⌘\(String($0).uppercased())" }) {
                    Text(detail)
                        .monospacedDigit()
                        .foregroundStyle(isEnabled ? .secondary : .tertiary)
                }
            }
            .foregroundStyle(isEnabled ? .primary : .tertiary)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { isHovering = $0 }
        .modifier(OptionalShortcut(key: shortcut))
    }
}

private struct OptionalShortcut: ViewModifier {
    let key: Character?

    func body(content: Content) -> some View {
        if let key {
            content.keyboardShortcut(KeyEquivalent(key))
        } else {
            content
        }
    }
}
