import SwiftUI

enum AppTheme {
    static let accent = Brand.accent
    static let cornerRadius: CGFloat = Radius.card

    static var pageBackground: some View { PageBackground() }
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
        HStack(alignment: .center, spacing: Space.m) {
            IconTile(symbol: symbol, size: 46)
            VStack(alignment: .leading, spacing: Space.xxs) {
                if let eyebrow {
                    Text(eyebrow)
                        .font(.eyebrow)
                        .foregroundStyle(Brand.accent)
                }
                Text(title).font(.pageTitle)
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct ModernCardModifier: ViewModifier {
    var padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .card()
    }
}

extension View {
    func modernCard(padding: CGFloat = Space.l) -> some View {
        modifier(ModernCardModifier(padding: padding))
    }
}

struct EmptyState: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        EmptyStateView(symbol: symbol, title: title, message: message)
            .card()
    }
}
