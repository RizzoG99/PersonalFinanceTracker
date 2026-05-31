import SwiftUI

struct ProfilePersonalInfoSection: View {
    @Binding var fullName: String

    var body: some View {
        TextField("Enter your name", text: $fullName)
            .foregroundStyle(.textPrimary)
    }
}
