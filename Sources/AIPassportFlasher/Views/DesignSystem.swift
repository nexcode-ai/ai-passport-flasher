import AppKit
import SwiftUI

// MARK: - Tokens

enum Brand {
    /// AI Passport site accent (`--passport-accent: #20e47c`); darkened in light mode for contrast.
    static let accent = dynamic(light: 0x0E9F57, dark: 0x20E47C)
    static let accentPressed = dynamic(light: 0x0B8549, dark: 0x1BC86C)
    static let onAccent = dynamic(light: 0xFFFFFF, dark: 0x05261A)
    static let accentSoft = dynamic(light: 0x0E9F57, dark: 0x20E47C, lightAlpha: 0.12, darkAlpha: 0.16)
    static let warning = dynamic(light: 0xB25E00, dark: 0xFFB648)
    static let danger = dynamic(light: 0xD1352B, dark: 0xFF6B60)
    static let surface = dynamic(light: 0xFFFFFF, dark: 0x26282B)
    static let surfaceRaised = dynamic(light: 0xFFFFFF, dark: 0x2F3236)
    static let surfaceSunken = dynamic(light: 0xF4F5F4, dark: 0x1C1E20)
    static let hairline = Color.primary.opacity(0.09)
    static let gradient = LinearGradient(
        colors: [Color(rgb: 0x20E47C), Color(rgb: 0x0FB5A6)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    private static func dynamic(light: UInt32, dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(rgb: isDark ? dark : light, alpha: isDark ? darkAlpha : lightAlpha)
        })
    }
}

/// 4-point spacing scale shared by every screen.
enum Space {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let s: CGFloat = 12
    static let m: CGFloat = 16
    static let l: CGFloat = 20
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

enum Radius {
    static let control: CGFloat = 8
    static let field: CGFloat = 10
    static let inset: CGFloat = 12
    static let card: CGFloat = 14
    static let hero: CGFloat = 20
}

extension NSColor {
    convenience init(rgb: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
                  green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255,
                  alpha: alpha)
    }
}

extension Color {
    init(rgb: UInt32) { self.init(nsColor: NSColor(rgb: rgb)) }
}

extension Font {
    static let pageTitle = Font.system(size: 26, weight: .bold)
    static let heroTitle = Font.system(size: 24, weight: .bold)
    static let sectionTitle = Font.system(size: 18, weight: .semibold)
    static let cardTitle = Font.system(size: 15, weight: .semibold)
    static let bodyText = Font.system(size: 13)
    static let meta = Font.system(size: 11.5)
    static let eyebrow = Font.system(size: 11, weight: .semibold)
}

enum Metrics {
    static let pagePadding: CGFloat = Space.xxl
    static let sectionSpacing: CGFloat = 28
    static let cardRadius: CGFloat = Radius.card
    static let pageMaxWidth: CGFloat = 1240
}

// MARK: - Page scaffold

struct Page<Accessory: View, Content: View>: View {
    let title: String
    let subtitle: String
    let symbol: String
    var maxWidth: CGFloat
    let accessory: Accessory
    let content: Content

    init(title: String, subtitle: String, symbol: String, maxWidth: CGFloat = 1000,
         @ViewBuilder accessory: () -> Accessory, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.maxWidth = maxWidth
        self.accessory = accessory()
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
                HStack(alignment: .center, spacing: Space.m) {
                    PageHeader(title: title, subtitle: subtitle, symbol: symbol)
                    Spacer(minLength: Space.m)
                    accessory
                }
                content
            }
            .padding(.horizontal, Metrics.pagePadding)
            .padding(.top, Space.xl)
            .padding(.bottom, 44)
            .frame(maxWidth: maxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
            .overlayScrollers()
        }
        .background(PageBackground())
    }
}

extension Page where Accessory == EmptyView {
    init(title: String, subtitle: String, symbol: String, maxWidth: CGFloat = 1000, @ViewBuilder content: () -> Content) {
        self.init(title: title, subtitle: subtitle, symbol: symbol, maxWidth: maxWidth, accessory: { EmptyView() }, content: content)
    }
}

struct PageBackground: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            Color(nsColor: .windowBackgroundColor)
            RadialGradient(colors: [Brand.accent.opacity(0.08), .clear], center: .topLeading, startRadius: 0, endRadius: 560)
                .frame(height: 520)
                .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }
}

struct IconTile: View {
    let symbol: String
    var size: CGFloat = 40
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(Brand.gradient)
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: size * 0.44, weight: .semibold))
                    .foregroundStyle(Color(rgb: 0x05261A))
            )
            .shadow(color: Color(rgb: 0x20E47C).opacity(0.28), radius: 6, y: 2)
    }
}

struct SectionHeader<Trailing: View>: View {
    let title: String
    var symbol: String?
    var subtitle: String?
    let trailing: Trailing

    init(_ title: String, symbol: String? = nil, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.symbol = symbol
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(Brand.accent)
            }
            Text(title).font(.sectionTitle)
            if let subtitle { Text(subtitle).font(.callout).foregroundStyle(.secondary) }
            Spacer()
            trailing
        }
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(_ title: String, symbol: String? = nil, subtitle: String? = nil) {
        self.init(title, symbol: symbol, subtitle: subtitle) { EmptyView() }
    }
}

// MARK: - Cards

struct CardStyle: ViewModifier {
    var radius: CGFloat = Metrics.cardRadius
    var elevated = false
    var hovering = false

    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Brand.surface))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(hovering ? Brand.accent.opacity(0.35) : Brand.hairline))
            .shadow(color: .black.opacity(elevated || hovering ? 0.13 : 0.05),
                    radius: elevated || hovering ? 16 : 5, y: elevated || hovering ? 8 : 2)
    }
}

extension View {
    func card(radius: CGFloat = Metrics.cardRadius, elevated: Bool = false, hovering: Bool = false) -> some View {
        modifier(CardStyle(radius: radius, elevated: elevated, hovering: hovering))
    }

    func sunken(radius: CGFloat = Radius.inset) -> some View {
        background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Brand.surfaceSunken))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Brand.hairline))
    }
}

/// Numbered section card used by the connect/flash, restore and about pages.
struct StepCard<Content: View>: View {
    let number: String
    let title: String
    var subtitle: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(alignment: .top, spacing: Space.s) {
                if !number.isEmpty {
                    Text(number)
                        .font(.system(size: 13, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(Brand.accent)
                        .frame(width: 28, height: 28)
                        .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(Brand.accentSoft))
                }
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text(title).font(.cardTitle)
                    if let subtitle {
                        Text(subtitle).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, number.isEmpty ? 0 : 4)
            }
            content
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

// MARK: - Buttons

/// The only button style in the app: three emphasis levels in three sizes, always icon + label on one line.
struct AppButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, tertiary, destructive }
    enum Size { case small, regular, large }

    var kind: Kind = .secondary
    var size: Size = .regular
    var fullWidth = false

    func makeBody(configuration: Configuration) -> Body {
        Body(configuration: configuration, kind: kind, size: size, fullWidth: fullWidth)
    }

    struct Body: View {
        let configuration: Configuration
        let kind: Kind
        let size: Size
        let fullWidth: Bool
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.colorScheme) private var colorScheme
        @State private var hovering = false

        var body: some View {
            configuration.label
                .labelStyle(AppButtonLabelStyle(iconSize: iconSize))
                .font(font)
                .lineLimit(1)
                .fixedSize(horizontal: !fullWidth, vertical: true)
                .foregroundStyle(foreground)
                .padding(.horizontal, horizontalPadding)
                .frame(height: height)
                .frame(maxWidth: fullWidth ? .infinity : nil)
                .background(background)
                .overlay(border)
                .shadow(color: shadowColor, radius: kind == .primary ? 6 : 1.5, y: kind == .primary ? 3 : 0.5)
                .opacity(isEnabled ? 1 : 0.45)
                .scaleEffect(configuration.isPressed ? 0.975 : 1)
                .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                .onHover { hovering = $0 && isEnabled }
                .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
                .animation(.easeOut(duration: 0.14), value: hovering)
        }

        private var height: CGFloat {
            switch size { case .small: 26; case .regular: 32; case .large: 40 }
        }
        private var horizontalPadding: CGFloat {
            switch size { case .small: 10; case .regular: 14; case .large: 20 }
        }
        private var radius: CGFloat {
            switch size { case .small: 7; case .regular: Radius.control; case .large: Radius.field }
        }
        private var iconSize: CGFloat {
            switch size { case .small: 11; case .regular: 12.5; case .large: 14 }
        }
        private var font: Font {
            let weight: Font.Weight = kind == .tertiary ? .medium : .semibold
            switch size {
            case .small: return .system(size: 12, weight: weight)
            case .regular: return .system(size: 13, weight: weight)
            case .large: return .system(size: 14.5, weight: weight)
            }
        }

        private var foreground: Color {
            switch kind {
            case .primary: return Brand.onAccent
            case .secondary: return .primary
            case .tertiary: return Brand.accent
            case .destructive: return .white
            }
        }

        @ViewBuilder private var background: some View {
            let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
            switch kind {
            case .primary:
                shape.fill(configuration.isPressed ? Brand.accentPressed : Brand.accent)
                    .overlay(shape.fill(Color.white.opacity(hovering && !configuration.isPressed ? 0.08 : 0)))
            case .destructive:
                shape.fill(Brand.danger).brightness(configuration.isPressed ? -0.08 : (hovering ? 0.04 : 0))
            case .secondary:
                shape.fill(Brand.surfaceRaised)
                    .overlay(shape.fill(Color.primary.opacity(configuration.isPressed ? 0.10 : (hovering ? 0.05 : 0))))
            case .tertiary:
                shape.fill(Brand.accent.opacity(configuration.isPressed ? 0.18 : (hovering ? 0.11 : 0)))
            }
        }

        @ViewBuilder private var border: some View {
            if kind == .secondary {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.13))
            }
        }

        private var shadowColor: Color {
            guard isEnabled else { return .clear }
            switch kind {
            case .primary: return Brand.accent.opacity(hovering ? 0.32 : 0.22)
            case .secondary: return .black.opacity(colorScheme == .dark ? 0.25 : 0.06)
            default: return .clear
            }
        }
    }
}

struct AppButtonLabelStyle: LabelStyle {
    var iconSize: CGFloat = 12.5
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.font(.system(size: iconSize, weight: .semibold)).imageScale(.medium)
            configuration.title
        }
    }
}

extension ButtonStyle where Self == AppButtonStyle {
    static func app(_ kind: AppButtonStyle.Kind = .secondary, size: AppButtonStyle.Size = .regular, fullWidth: Bool = false) -> AppButtonStyle {
        AppButtonStyle(kind: kind, size: size, fullWidth: fullWidth)
    }
}

/// Square icon-only button on the same height grid as `AppButtonStyle`.
struct IconButton: View {
    let symbol: String
    let help: String
    var size: AppButtonStyle.Size = .regular
    var active = false
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size == .small ? 11 : 13, weight: .semibold))
                .foregroundStyle(active ? Brand.accent : Color.primary.opacity(0.8))
                .frame(width: side, height: side)
                .background(
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .fill(active ? Brand.accentSoft : Color.primary.opacity(hovering ? 0.08 : 0.0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.4)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }

    private var side: CGFloat { size == .small ? 26 : (size == .regular ? 32 : 40) }
}

// MARK: - Inputs

/// A compact segmented control that follows the same surface, radius and
/// interaction rules as the rest of the app instead of inheriting the
/// system's solid accent fill.
struct AppSegmentedControl<Value: Hashable>: View {
    let items: [(Value, String)]
    @Binding var selection: Value

    init(_ items: [(Value, String)], selection: Binding<Value>) {
        self.items = items
        _selection = selection
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items.indices, id: \.self) { index in
                let item = items[index]
                let selected = item.0 == selection
                Button {
                    selection = item.0
                } label: {
                    Text(item.1)
                        .font(.system(size: 12.5, weight: selected ? .semibold : .medium))
                        .foregroundStyle(selected ? Brand.accent : Color.primary.opacity(0.78))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(selected ? Brand.surfaceRaised : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(selected ? Brand.accent.opacity(0.28) : Color.clear)
                        )
                        .shadow(color: selected ? .black.opacity(0.06) : .clear, radius: 2, y: 1)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: Radius.field, style: .continuous)
                .fill(Brand.surfaceSunken)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.field, style: .continuous)
                .strokeBorder(Brand.hairline)
        )
        .animation(.easeOut(duration: 0.14), value: selection)
    }
}

extension View {
    func appField() -> some View {
        textFieldStyle(.plain)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: Radius.field, style: .continuous)
                    .fill(Brand.surfaceSunken)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.field, style: .continuous)
                    .strokeBorder(Brand.hairline)
            )
    }
}

// MARK: - Native overlay scrollers

/// Forces the thin, auto-hiding macOS overlay scroller on the enclosing scroll view,
/// even when the system preference or an attached mouse would show legacy scrollbars.
private struct OverlayScrollerConfigurator: NSViewRepresentable {
    final class Probe: NSView {
        private var observer: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply()
            if observer == nil {
                observer = NotificationCenter.default.addObserver(
                    forName: NSScroller.preferredScrollerStyleDidChangeNotification,
                    object: nil, queue: .main
                ) { [weak self] _ in self?.apply() }
            }
        }

        deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }

        func apply() {
            DispatchQueue.main.async { [weak self] in
                guard let scrollView = self?.enclosingScrollView else { return }
                scrollView.scrollerStyle = .overlay
                scrollView.autohidesScrollers = true
                scrollView.verticalScroller?.controlSize = .small
            }
        }
    }

    func makeNSView(context: Context) -> Probe { Probe() }
    func updateNSView(_ nsView: Probe, context: Context) { nsView.apply() }
}

extension View {
    /// Apply inside a `ScrollView`'s content.
    func overlayScrollers() -> some View {
        background(OverlayScrollerConfigurator().frame(width: 0, height: 0))
    }
}

// MARK: - Small components

struct Tag: View {
    let text: String
    var tint: Color = Brand.accent
    var onDark = false
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .lineLimit(1)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .foregroundStyle(onDark ? Color.white : tint)
            .background(Capsule().fill(onDark ? Color.black.opacity(0.5) : tint.opacity(0.14)))
    }
}

struct Chip: View {
    let title: String
    var symbol: String?
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    init(title: String, symbol: String? = nil, selected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.selected = selected
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol).font(.system(size: 11, weight: .semibold)) }
                Text(title).font(.system(size: 12.5, weight: selected ? .semibold : .medium)).lineLimit(1)
            }
            .padding(.horizontal, 12)
            .frame(height: 28)
            .foregroundStyle(selected ? Brand.onAccent : Color.primary.opacity(0.85))
            .background(
                Capsule().fill(selected ? AnyShapeStyle(Brand.accent)
                               : AnyShapeStyle(Color.primary.opacity(hovering ? 0.09 : 0.05)))
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: selected)
    }
}

struct Banner: View {
    enum Kind { case error, warning, info }
    let kind: Kind
    let text: String
    var onClose: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: Space.s) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 18)
                .padding(.top, 1)
            Text(text)
                .font(.callout)
                .foregroundStyle(.primary.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let onClose {
                IconButton(symbol: "xmark", help: "关闭", size: .small, action: onClose)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, Space.s)
        .background(RoundedRectangle(cornerRadius: Radius.inset, style: .continuous).fill(color.opacity(0.09)))
        .overlay(RoundedRectangle(cornerRadius: Radius.inset, style: .continuous).strokeBorder(color.opacity(0.18)))
    }

    private var symbol: String {
        switch kind {
        case .error: return "xmark.octagon.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }

    private var color: Color {
        switch kind {
        case .error: return Brand.danger
        case .warning: return Brand.warning
        case .info: return .blue
        }
    }
}

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String?
    var actionSymbol: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: Space.s) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(Brand.accent)
                .frame(width: 60, height: 60)
                .background(Circle().fill(Brand.accentSoft))
            Text(title).font(.cardTitle)
            Text(message).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            if let actionTitle, let action {
                Button(action: action) {
                    Label(actionTitle, systemImage: actionSymbol ?? "arrow.clockwise")
                }
                .buttonStyle(.app(.secondary))
                .padding(.top, Space.xxs)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
    }
}

struct Pulsing: ViewModifier {
    @State private var on = false
    func body(content: Content) -> some View {
        content
            .opacity(on ? 0.45 : 1)
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: on)
            .onAppear { on = true }
    }
}

extension View {
    func pulsing() -> some View { modifier(Pulsing()) }
}

struct SkeletonBlock: View {
    var radius: CGFloat = 8
    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Color.primary.opacity(0.07))
    }
}

struct InfoPair: View {
    let label: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.callout.monospaced()).textSelection(.enabled)
        }
    }
}
