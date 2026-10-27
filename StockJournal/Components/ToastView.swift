import SwiftUI

/// Toast notification type
enum ToastStyle {
    case success
    case error
    case info

    var icon: String {
        switch self {
        case .success: "checkmark.circle.fill"
        case .error: "xmark.circle.fill"
        case .info: "info.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .success: .semanticGreen
        case .error: .semanticRed
        case .info: .accent
        }
    }
}

/// Toast notification data
struct ToastData: Equatable {
    let style: ToastStyle
    let message: String
    /// Optional undo action — when present, toast shows an "Undo" button and extends display to 5 seconds
    var undoAction: (() -> Void)?

    var hasUndo: Bool { undoAction != nil }

    static func == (lhs: ToastData, rhs: ToastData) -> Bool {
        lhs.message == rhs.message && lhs.hasUndo == rhs.hasUndo
    }
}

/// Toast notification overlay view
struct ToastView: View {
    let toast: ToastData
    @Binding var isPresented: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: toast.style.icon)
                .foregroundStyle(toast.style.color)
            Text(toast.message)
                .font(.smallText)

            if let undoAction = toast.undoAction {
                Button {
                    undoAction()
                    withAnimation { isPresented = false }
                } label: {
                    Text("Undo")
                        .font(.smallText)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.accent)
                }
                .buttonStyle(.plain)
            }

            Spacer()
            Button {
                withAnimation { isPresented = false }
            } label: {
                Image(systemName: "xmark")
                    .font(.smallText)
                    .foregroundStyle(Color.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(toast.hasUndo ? toast.style.color.opacity(0.3) : Color.borderCard, lineWidth: 1)
        )
        .shadow(color: Color.bgApp.opacity(0.5), radius: 8, y: 4)
        .transition(.move(edge: .top).combined(with: .opacity))
        .onAppear {
            let delay: Double = toast.hasUndo ? 5.0 : 3.5
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation { isPresented = false }
            }
        }
    }
}

/// ViewModifier for showing toast notifications
struct ToastModifier: ViewModifier {
    @Binding var toast: ToastData?

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let toast {
                ToastView(toast: toast, isPresented: .init(
                    get: { self.toast != nil },
                    set: { if !$0 { self.toast = nil } }
                ))
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
        }
        .animation(.spring(duration: 0.3), value: toast)
    }
}

extension View {
    func toast(_ toast: Binding<ToastData?>) -> some View {
        modifier(ToastModifier(toast: toast))
    }
}
