import SwiftUI

/// HStack that forces all children to the height of the tallest child.
/// Children must NOT apply their own card background — this layout handles it.
struct EqualHeightHStack: Layout {
    var spacing: CGFloat = 16

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }

        let proposedWidth = proposal.width ?? 800
        let totalSpacing = spacing * CGFloat(subviews.count - 1)
        let childWidth = (proposedWidth - totalSpacing) / CGFloat(subviews.count)

        let childProposal = ProposedViewSize(width: childWidth, height: nil)
        let maxHeight = subviews.map { $0.sizeThatFits(childProposal).height }.max() ?? 0

        return CGSize(width: proposedWidth, height: maxHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty else { return }

        let totalSpacing = spacing * CGFloat(subviews.count - 1)
        let childWidth = (bounds.width - totalSpacing) / CGFloat(subviews.count)

        var x = bounds.minX
        for subview in subviews {
            subview.place(
                at: CGPoint(x: x, y: bounds.minY),
                proposal: ProposedViewSize(width: childWidth, height: bounds.height)
            )
            x += childWidth + spacing
        }
    }
}

/// Wraps a view so its card background stretches to fill the proposed height.
/// Applies a second card background layer outside the content to fill any gap.
struct StretchingCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.borderCard, lineWidth: 1)
            )
    }
}
