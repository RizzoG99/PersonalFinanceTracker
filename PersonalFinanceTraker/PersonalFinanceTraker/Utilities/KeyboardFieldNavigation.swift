import SwiftUI

extension View {
    /// Adds the standard ‹ › / Done bar above the keyboard for moving between a form's text fields.
    ///
    /// Without it the only way off a field is dismissing the keyboard and scrolling to the next one —
    /// which in landscape means scrolling a form that has almost no room to scroll. The amount fields
    /// make it worse: a `decimalPad` has no Return key at all, so `submitLabel` can't help there.
    ///
    /// - Parameter order: the fields in tab order. Typed fields only — chaining into a picker would
    ///   make Next look like it dismissed the keyboard for nothing.
    func keyboardFieldNavigation<Field: Hashable>(
        _ focus: FocusState<Field?>.Binding,
        order: [Field]
    ) -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                let index = focus.wrappedValue.flatMap { order.firstIndex(of: $0) }

                Button {
                    if let index, index > 0 { focus.wrappedValue = order[index - 1] }
                } label: {
                    Image(systemName: "chevron.up")
                }
                .accessibilityLabel("Previous field")
                .disabled(index == nil || index == 0)

                Button {
                    if let index, index < order.count - 1 { focus.wrappedValue = order[index + 1] }
                } label: {
                    Image(systemName: "chevron.down")
                }
                .accessibilityLabel("Next field")
                .disabled(index == nil || index == order.count - 1)

                Spacer()

                Button("Done") { focus.wrappedValue = nil }
                    .fontWeight(.semibold)
            }
        }
    }
}
