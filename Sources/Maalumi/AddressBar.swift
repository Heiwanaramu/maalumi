import SwiftUI

// MARK: - AddressBar
// Native SwiftUI TextField tied to FocusState for Safari-style smart expanding address bar.

struct AddressBar: View {
    @Binding var text: String
    var placeholder: String = "Search or enter website"
    @FocusState.Binding var isFocused: Bool
    var textAlignment: TextAlignment = .center
    var fontSize: CGFloat = 13
    var onSubmit: () -> Void

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .focused($isFocused)
            .font(.system(size: fontSize))
            .multilineTextAlignment(textAlignment)
            .lineLimit(1)
            .onSubmit(onSubmit)
    }
}
