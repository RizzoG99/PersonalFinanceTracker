import SwiftUI

struct EditFullNameView: View {
    @Binding var fullName: String
    @FocusState private var isFocused: Bool

    var body: some View {
        List {
            
        }
        .scrollContentBackground(.hidden)
        .appBackground()
        .preferredColorScheme(.dark)
        .navigationTitle("Full Name")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { isFocused = true }
    }
}
