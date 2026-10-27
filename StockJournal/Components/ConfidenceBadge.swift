import SwiftUI

/// Statistical confidence level based on sample size
enum ConfidenceLevel: Sendable {
    case insufficient  // n < 10
    case low           // 10-29
    case significant   // 30+

    var label: String {
        switch self {
        case .insufficient: "Insufficient"
        case .low: "Low confidence"
        case .significant: "Significant"
        }
    }

    var color: Color {
        switch self {
        case .insufficient: .semanticRed
        case .low: .orange
        case .significant: .semanticGreen
        }
    }

    var icon: String {
        switch self {
        case .insufficient: "exclamationmark.triangle.fill"
        case .low: "info.circle.fill"
        case .significant: "checkmark.seal.fill"
        }
    }
}

/// Reusable badge showing statistical confidence based on sample size
struct ConfidenceBadge: View {
    let sampleSize: Int
    var compact: Bool = false

    private var level: ConfidenceLevel {
        MetricsCalculator.confidenceLevel(sampleSize: sampleSize)
    }

    var body: some View {
        if compact {
            Image(systemName: level.icon)
                .font(.smallText)
                .foregroundStyle(level.color.opacity(0.8))
                .help("\(level.label) (n=\(sampleSize))")
        } else {
            HStack(spacing: 3) {
                Image(systemName: level.icon)
                Text("n=\(sampleSize)")
            }
            .font(.smallText)
            .foregroundStyle(level.color.opacity(0.8))
            .help(level.label)
        }
    }
}
