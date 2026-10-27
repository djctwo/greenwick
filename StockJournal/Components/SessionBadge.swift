import SwiftUI

/// Badge showing a market session with colored background
struct SessionBadge: View {
    let session: MarketSession

    var body: some View {
        Text(session.displayName)
            .font(.smallText)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.forSession(session).opacity(0.2))
            .foregroundStyle(Color.forSession(session))
            .clipShape(Capsule())
    }
}
