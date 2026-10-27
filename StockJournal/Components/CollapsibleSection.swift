import SwiftUI

/// A collapsible section with header, chevron, and animated content reveal.
/// Remembers expanded/collapsed state in UserDefaults per section key.
struct CollapsibleSection<Content: View>: View {
    let title: String
    let icon: String
    let storageKey: String
    @ViewBuilder let content: () -> Content

    @State private var isExpanded: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        title: String,
        icon: String,
        storageKey: String,
        defaultExpanded: Bool = false,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.storageKey = storageKey
        self.content = content
        // Restore saved state, defaulting to collapsed
        self._isExpanded = State(initialValue: UserDefaults.standard.object(forKey: storageKey) as? Bool ?? defaultExpanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header — always visible
            Button {
                if reduceMotion {
                    isExpanded.toggle()
                    UserDefaults.standard.set(isExpanded, forKey: storageKey)
                } else {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                        UserDefaults.standard.set(isExpanded, forKey: storageKey)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.smallText)
                        .foregroundStyle(Color.accent)
                        .frame(width: 20)

                    Text(title.uppercased())
                        .font(.sectionLabel)
                        .tracking(1.2)
                        .foregroundStyle(Color.textSecondary)

                    Spacer()

                    Text(isExpanded ? "Collapse" : "Expand")
                        .font(.smallText)
                        .foregroundStyle(Color.textTertiary)

                    Image(systemName: "chevron.right")
                        .font(.monoSmall)
                        .foregroundStyle(Color.textTertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Accent divider
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color.accent.opacity(0.3), Color.accent.opacity(0.05)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)

            // Collapsible content
            if isExpanded {
                VStack(spacing: 16) {
                    content()
                }
                .padding(.top, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}
