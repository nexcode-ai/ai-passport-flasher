import SwiftUI

enum AppTheme {
    static let accent = Brand.accent
    static let cornerRadius: CGFloat = 18

    static var pageBackground: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            LinearGradient(
                colors: [accent.opacity(0.055), Color.clear, Color.cyan.opacity(0.025)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }
}

struct PageHeader: View {
    let eyebrow: String?
    let title: String
    let subtitle: String
    let symbol: String

    init(eyebrow: String? = nil, title: String, subtitle: String, symbol: String) {
        self.eyebrow = eyebrow
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
    }

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            Image(systemName: symbol)
                .font(.system(size: 25, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(
                    Brand.gradient,
                    in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                )
                .shadow(color: AppTheme.accent.opacity(0.22), radius: 12, y: 5)
            VStack(alignment: .leading, spacing: 5) {
                if let eyebrow {
                    Text(eyebrow.uppercased())
                        .font(.caption2.weight(.bold))
                        .tracking(1.3)
                        .foregroundStyle(AppTheme.accent)
                }
                Text(title)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
            }
        }
    }
}

struct ModernCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    var padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                    .stroke(colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.07))
            }
            .shadow(
                color: colorScheme == .dark ? Color.black.opacity(0.18) : Color.black.opacity(0.07),
                radius: 14,
                y: 6
            )
    }
}

extension View {
    func modernCard(padding: CGFloat = 20) -> some View {
        modifier(ModernCardModifier(padding: padding))
    }
}

struct EmptyState: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 62, height: 62)
                .background(AppTheme.accent.opacity(0.1), in: Circle())
            Text(title).font(.headline)
            Text(message).font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 38)
        .modernCard()
    }
}
