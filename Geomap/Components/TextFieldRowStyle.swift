import SwiftUI

private struct TextFieldRowStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.vertical, 14)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.secondary.opacity(0.35))
            )
            // Extends the tappable region to the full padded frame rather
            // than just the rendered text/border — a plain .roundedBorder
            // field's hit area is tightly bound to its visible bounds,
            // making it easy to miss with a slightly-off tap.
            .contentShape(Rectangle())
    }
}

extension View {
    func textFieldRowStyle() -> some View {
        modifier(TextFieldRowStyle())
    }
}
