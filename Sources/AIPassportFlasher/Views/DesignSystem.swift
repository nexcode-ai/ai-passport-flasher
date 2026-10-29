import AppKit
import SwiftUI

// MARK: - Brand

enum Brand {
    /// AI Passport site accent (`--passport-accent: #20e47c`); darkened in light mode for contrast.
    static let accent = dynamic(light: 0x0E9F57, dark: 0x20E47C)
    static let onAccent = dynamic(light: 0xFFFFFF, dark: 0x05261A)
    static let accentSoft = dynamic(light: 0x0E9F57, dark: 0x20E47C, lightAlpha: 0.12, darkAlpha: 0.16)
    static let warning = dynamic(light: 0xB25E00, dark: 0xFFB648)
    static let danger = dynamic(light: 0xD1352B, dark: 0xFF6B60)
    static let surface = dynamic(light: 0xFFFFFF, dark: 0x232528)
    static let surfaceSunken = dynamic(light: 0xF4F5F4, dark: 0x1A1C1E)
    static let hairline = Color.primary.opacity(0.08)
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
    static let pageTitle = Font.system(size: 28, weight: .bold)
    static let sectionTitle = Font.system(size: 19, weight: .semibold)
    static let cardTitle = Font.system(size: 14.5, weight: .semibold)
}

enum Metrics {
    static let pagePadding: CGFloat = 36
    static let sectionSpacing: CGFloat = 30
    static let cardRadius: CGFloat = 16
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
                HStack(alignment: .center, spacing: 16) {
                    IconTile(symbol: symbol, size: 48)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title).font(.pageTitle)
                        Text(subtitle)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 16)
                    accessory
                }
                content
            }
            .padding(.horizontal, Metrics.pagePadding)
            .padding(.top, 28)
            .padding(.bottom, 44)
            .frame(maxWidth: maxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
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
            RadialGradient(colors: [Brand.accent.opacity(0.10), .clear], center: .topLeading, startRadius: 0, endRadius: 560)
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
                    .font(.system(size: size * 0.46, weight: .semibold))
                    .foregroundStyle(Color(rgb: 0x05261A))
            )
            .shadow(color: Color(rgb: 0x20E47C).opacity(0.35), radius: 8, y: 3)
    }
}

struct SectionHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    let trailing: Trailing

    init(_ title: String, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title).font(.sectionTitle)
            if let subtitle { Text(subtitle).font(.callout).foregroundStyle(.secondary) }
            Spacer()
            trailing
        }
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(_ title: String, subtitle: String? = nil) {
        self.init(title, subtitle: subtitle) { EmptyView() }
    }
}

// MARK: - Cards

struct CardStyle: ViewModifier {
    var radius: CGFloat = Metrics.cardRadius
    var elevated = false

    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Brand.surface))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Brand.hairline))
            .shadow(color: .black.opacity(elevated ? 0.16 : 0.05), radius: elevated ? 18 : 6, y: elevated ? 10 : 2)
    }
}

extension View {
    func card(radius: CGFloat = Metrics.cardRadius, elevated: Bool = false) -> some View {
        modifier(CardStyle(radius: radius, elevated: elevated))
    }

    func sunken(radius: CGFloat = 12) -> some View {
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
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                if !number.isEmpty {
                    Text(number)
                        .font(.system(size: 13, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(Brand.accent)
                        .frame(width: 30, height: 30)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Brand.accentSoft))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 17, weight: .semibold))
                    if let subtitle {
                        Text(subtitle).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, number.isEmpty ? 0 : 4)
            }
            content
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

// MARK: - Buttons

struct PrimaryButtonStyle: ButtonStyle {
    enum Size { case small, regular, large }
    var size: Size = .regular
    var fullWidth = false

    func makeBody(configuration: Configuration) -> some View {
        PrimaryButtonBody(configuration: configuration, size: size, fullWidth: fullWidth)
    }

    private struct PrimaryButtonBody: View {
        let configuration: Configuration
        let size: Size
        let fullWidth: Bool
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(font)
                .labelStyle(.titleAndIcon)
                .foregroundStyle(isEnabled ? Brand.onAccent : Color.secondary)
                .padding(.horizontal, hPad)
                .frame(minHeight: height)
                .frame(maxWidth: fullWidth ? .infinity : nil)
                .background(
                    RoundedRectangle(cornerRadius: height / 2.6, style: .continuous)
                        .fill(isEnabled ? AnyShapeStyle(Brand.accent) : AnyShapeStyle(Color.primary.opacity(0.08)))
                        .brightness(isEnabled && hovering ? 0.04 : 0)
                )
                .shadow(color: isEnabled && size == .large ? Brand.accent.opacity(0.35) : .clear, radius: 10, y: 4)
                .opacity(configuration.isPressed ? 0.85 : 1)
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
                .animation(.easeOut(duration: 0.15), value: hovering)
        }

        private var font: Font {
            switch size {
            case .small: return .system(size: 12, weight: .semibold)
            case .regular: return .system(size: 13, weight: .semibold)
            case .large: return .system(size: 15, weight: .semibold)
            }
        }
        private var height: CGFloat { size == .small ? 26 : (size == .regular ? 32 : 44) }
        private var hPad: CGFloat { size == .small ? 10 : (size == .regular ? 14 : 22) }
    }
}

struct SoftButtonStyle: ButtonStyle {
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        SoftButtonBody(configuration: configuration, compact: compact)
    }

    private struct SoftButtonBody: View {
        let configuration: Configuration
        let compact: Bool
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.system(size: compact ? 12 : 13, weight: .medium))
                .foregroundStyle(isEnabled ? Color.primary : Color.secondary.opacity(0.6))
                .padding(.horizontal, compact ? 10 : 13)
                .frame(minHeight: compact ? 26 : 32)
                .background(
                    RoundedRectangle(cornerRadius: compact ? 8 : 10, style: .continuous)
                        .fill(Color.primary.opacity(configuration.isPressed ? 0.14 : (hovering && isEnabled ? 0.10 : 0.06)))
                )
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
        }
    }
}

struct IconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.primary.opacity(hovering ? 0.10 : 0.06)))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
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
                Text(title).font(.system(size: 13, weight: selected ? .semibold : .regular))
            }
            .padding(.horizontal, 13).padding(.vertical, 7)
            .foregroundStyle(selected ? Brand.onAccent : Color.primary)
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
        HStack(alignment: .top, spacing: 12) {
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
                Button { onClose() } label: { Image(systemName: "xmark").font(.caption.weight(.bold)) }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(color.opacity(0.09)))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2).fill(color.opacity(0.8)).frame(width: 3).padding(.vertical, 10)
        }
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
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(.secondary)
                .frame(width: 64, height: 64)
                .background(Circle().fill(Color.primary.opacity(0.05)))
            Text(title).font(.headline)
            Text(message).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(SoftButtonStyle()).padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
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
