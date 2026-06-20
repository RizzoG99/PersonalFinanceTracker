import SwiftUI

struct ProfilePayCycleSection: View {
    @Binding var payCycleStartDay: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProfileSectionLabel(title: "Pay Cycle")
            VStack(alignment: .leading, spacing: 12) {
                Text("Financial month starts on day:")
                    .font(.subheadline)
                    .foregroundStyle(.textMid)

                HStack(spacing: 12) {
                    Stepper(
                        value: $payCycleStartDay,
                        in: 1...28,
                        label: { EmptyView() }
                    )
                    .tint(.accentIndigo)

                    Text("Day \(payCycleStartDay)")
                        .font(.headline)
                        .foregroundStyle(.textPrimary)
                        .frame(minWidth: 80, alignment: .leading)
                }

                Text("Your financial periods run from day \(payCycleStartDay) to day \(payCycleStartDay > 1 ? payCycleStartDay - 1 : 28) of the following month. This affects health score calculations and budget windows.")
                    .font(.caption)
                    .foregroundStyle(.textDim)
            }
        }
    }
}
