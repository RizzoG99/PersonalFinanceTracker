import SwiftUI

/// Shared empty-state card: optional icon + message + optional subtitle + optional CTA button.
/// Used across Home, Activity, and Insights for consistent "nothing here yet" messaging.
/// ponytail: kept the name InsightsEmptyCard (originally Insights-only) as a typealias so
/// existing call sites (HabitsSection, ForecastSection, CategoryTrendsSection) don't need edits.
struct EmptyStateView: View {
    var icon: String? = nil
    let message: LocalizedStringKey
    var subtitle: LocalizedStringKey? = nil
    var actionTitle: LocalizedStringKey? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        GlassCard {
            VStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon)
                        .font(.title2)
                        .foregroundStyle(.accentIndigo.opacity(0.6))
                }
                Text(message)
                    .font(.subheadline.bold())
                    .foregroundStyle(.textMid)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.textDim)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                }
                if let actionTitle, let action {
                    Button(action: action) {
                        Text(actionTitle)
                            .font(.subheadline.bold())
                            .foregroundStyle(.primaryActionForeground)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .glassEffect(.regular.tint(Color.accentIndigo).interactive())
                    }
                    .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }
}

typealias InsightsEmptyCard = EmptyStateView
