import SwiftUI

// MARK: - Card Style

/// Standard card surface: charcoal background, 12px radius, 1px neutral border, hover effect
struct CardStyleModifier: ViewModifier {
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .background(isHovered ? Color.bgCardHover : Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.borderCard, lineWidth: 1)
            )
            .onHover { isHovered = $0 }
    }
}

// MARK: - Inset Surface

/// Nested surface inside cards: neutral inset background, 8px radius
struct InsetSurfaceModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color.bgInset)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.borderSubtle, lineWidth: 1)
            )
    }
}

// MARK: - Hero Card Style

/// Hero card surface: no border, subtle bottom shadow for depth. For primary dashboard components.
struct HeroCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: Color.bgApp.opacity(0.6), radius: 8, y: 4)
    }
}

// MARK: - Inline Style

/// Minimal inline surface: background only, no border, no radius. For compact secondary data.
struct InlineStyleModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color.bgCard.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Accent Top Bar

/// Teal gradient bar along top edge of a card
struct AccentTopBarModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                LinearGradient(
                    colors: [Color.accent, Color.accentDark],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(height: 2)
            }
    }
}

// MARK: - View Extensions

extension View {
    /// Apply standard card styling
    func cardStyle() -> some View {
        modifier(CardStyleModifier())
    }

    /// Apply inset surface styling (for nested containers within cards)
    func insetSurface() -> some View {
        modifier(InsetSurfaceModifier())
    }

    /// Apply hero card styling (borderless, shadow depth)
    func heroCard() -> some View {
        modifier(HeroCardModifier())
    }

    /// Apply inline styling (minimal, low-contrast background)
    func inlineStyle() -> some View {
        modifier(InlineStyleModifier())
    }

    /// Add a teal gradient accent bar along the top edge
    func accentTopBar() -> some View {
        modifier(AccentTopBarModifier())
    }
}
