import SwiftUI

struct ProfilePayCycleSection: View {
    @Environment(AppSettings.self) private var appSettings

    var body: some View {
        @Bindable var appSettings = appSettings
        VStack(alignment: .leading, spacing: 12) {
            Text("PAY CYCLE")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.textDim)
                .padding(.horizontal, 4)

            Picker("Financial month starts on day", selection: $appSettings.payCycleStartDay) {
                ForEach(1...28, id: \.self) { day in
                    Text("\(day)").tag(day)
                }
            }
            .tint(.accentIndigo)

            Text("Periods run from day \(appSettings.payCycleStartDay) to day \(appSettings.payCycleStartDay > 1 ? appSettings.payCycleStartDay - 1 : 28) of the next month.")
                .font(.caption)
                .foregroundStyle(.textDim)
        }
    }
}
