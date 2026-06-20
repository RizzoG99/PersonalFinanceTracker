import SwiftUI

struct ProfilePayCycleSection: View {
    @Environment(AppSettings.self) private var appSettings

    var body: some View {
        @Bindable var appSettings = appSettings
        VStack(alignment: .leading, spacing: 8) {
            ProfileSectionLabel(title: "Pay Cycle")
            VStack(alignment: .leading, spacing: 12) {
                Text("Financial month starts on day:")
                    .font(.subheadline)
                    .foregroundStyle(.textMid)

                HStack(spacing: 12) {
                    Stepper(
                        value: $appSettings.payCycleStartDay,
                        in: 1...28,
                        label: { EmptyView() }
                    )
                    .tint(.accentIndigo)

                    Text("Day \(appSettings.payCycleStartDay)")
                        .font(.headline)
                        .foregroundStyle(.textPrimary)
                        .frame(minWidth: 80, alignment: .leading)
                }

                Text("Your financial periods run from day \(appSettings.payCycleStartDay) to day \(appSettings.payCycleStartDay > 1 ? appSettings.payCycleStartDay - 1 : 28) of the following month. This affects health score calculations and budget windows.")
                    .font(.caption)
                    .foregroundStyle(.textDim)
            }
        }
    }
}
