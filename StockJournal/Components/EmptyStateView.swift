import SwiftUI

/// Reusable empty state placeholder shown when there's no data to display
struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(Color.textTertiary)

            Text(title)
                .font(.kpiValueSecondary)
                .fontWeight(.medium)
                .foregroundStyle(Color.textPrimary)

            Text(message)
                .font(.bodyText)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                    .tint(Color.accent)
                    .padding(.top, 4)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}
