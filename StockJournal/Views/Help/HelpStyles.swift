import SwiftUI

/// Reusable help content styling components
struct HelpTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.kpiValueSecondary)
            .fontWeight(.bold)
            .padding(.bottom, 4)
    }
}

struct HelpSubtitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.cardTitle)
            .padding(.top, 16)
            .padding(.bottom, 4)
    }
}

struct HelpParagraph: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.bodyText)
            .foregroundStyle(Color.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct HelpStep: View {
    let number: Int
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.smallText)
                .fontWeight(.bold)
                .foregroundStyle(Color.textPrimary)
                .frame(width: 22, height: 22)
                .background(Color.accent)
                .clipShape(Circle())
            Text(text)
                .font(.bodyText)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }
}

struct HelpTip: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lightbulb.fill")
                .foregroundStyle(.yellow)
                .font(.smallText)
            Text(text)
                .font(.bodyText)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.yellow.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.borderCard, lineWidth: 1)
        )
        .padding(.vertical, 4)
    }
}

struct HelpWarning: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.smallText)
            Text(text)
                .font(.bodyText)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.borderCard, lineWidth: 1)
        )
        .padding(.vertical, 4)
    }
}

struct HelpBullet: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\u{2022}")
                .foregroundStyle(Color.textSecondary)
            Text(text)
                .font(.bodyText)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, 8)
    }
}

struct HelpDefinition: View {
    let term: String
    let definition: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(term)
                .font(.bodyText)
                .fontWeight(.semibold)
            Text(definition)
                .font(.bodyText)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }
}
