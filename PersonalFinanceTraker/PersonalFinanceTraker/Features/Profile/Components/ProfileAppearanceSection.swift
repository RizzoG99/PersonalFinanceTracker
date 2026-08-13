import SwiftUI

struct ProfileAppearanceSection: View {
    @AppStorage("app_theme_mode") private var themeMode: ThemeMode = .auto

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("APPEARANCE")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.textDim)
                .padding(.horizontal, 4)

            Picker("Appearance", selection: $themeMode) {
                ForEach(ThemeMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .tint(.accentIndigo)
        }
    }
}
