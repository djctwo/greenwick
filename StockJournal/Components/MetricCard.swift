import SwiftUI

/// Reusable card displaying a single metric
struct MetricCard: View {
    let title: String
    let value: String
    var subtitle: String?
    var valueColor: Color = .textPrimary
    var icon: String?
    /// Optional tooltip text shown on info button tap
    var tooltip: String?
    /// Hero mode — larger value, colored left accent bar, slightly wider
    var isHero: Bool = false

    var body: some View {
        HStack(spacing: 0) {
            if isHero {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(valueColor.opacity(0.6))
                    .frame(width: 3)
                    .padding(.vertical, 8)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    if let icon {
                        Image(systemName: icon)
                            .font(.smallText)
                            .foregroundStyle(Color.textTertiary)
                    }
                    Text(title.uppercased())
                        .font(.kpiLabel)
                        .tracking(0.8)
                        .foregroundStyle(Color.textTertiary)

                    if let tooltip {
                        MetricInfoButton(text: tooltip)
                    }
                }

                Text(value)
                    .font(.kpiValue)
                    .tracking(-1)
                    .foregroundStyle(valueColor)

                if let subtitle {
                    Text(subtitle)
                        .font(.monoSubtitle)
                        .foregroundStyle(Color.textTertiary)
                }
            }
            .padding(.leading, isHero ? 8 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(12)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isHero ? valueColor.opacity(0.2) : Color.borderCard, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)\(subtitle.map { ", \($0)" } ?? "")")
    }
}

/// Smaller variant for secondary KPI rows — colored left accent bar
struct MetricCardSmall: View {
    let title: String
    let value: String
    var subtitle: String?
    var valueColor: Color = .textPrimary
    var tooltip: String?

    var body: some View {
        HStack(spacing: 0) {
            // Colored left accent bar
            RoundedRectangle(cornerRadius: 1.5)
                .fill(valueColor.opacity(0.5))
                .frame(width: 3)
                .padding(.vertical, 8)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(title.uppercased())
                        .font(.kpiLabel)
                        .tracking(0.8)
                        .foregroundStyle(Color.textTertiary)

                    if let tooltip {
                        MetricInfoButton(text: tooltip)
                    }
                }

                Text(value)
                    .font(.kpiValueSecondary)
                    .tracking(-0.5)
                    .foregroundStyle(valueColor)

                if let subtitle {
                    Text(subtitle)
                        .font(.monoSubtitle)
                        .foregroundStyle(Color.textTertiary)
                }
            }
            .padding(.leading, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(12)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.borderCard, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)\(subtitle.map { ", \($0)" } ?? "")")
    }
}

// MARK: - Info Button for Metric Tooltips

/// Small info button that shows a popover with metric explanation
struct MetricInfoButton: View {
    let text: String
    @State private var isShowing = false

    var body: some View {
        Button {
            isShowing.toggle()
        } label: {
            Image(systemName: "info.circle")
                .font(.monoSmall)
                .foregroundStyle(Color.textTertiary.opacity(0.6))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isShowing, arrowEdge: .bottom) {
            Text(text)
                .font(.smallText)
                .foregroundStyle(Color.textPrimary)
                .padding(12)
                .frame(maxWidth: 280)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
