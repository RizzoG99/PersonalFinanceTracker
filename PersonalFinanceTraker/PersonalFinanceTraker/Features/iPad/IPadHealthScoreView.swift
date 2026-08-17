//
//  IPadHealthScoreView.swift
//  PersonalFinanceTraker
//

import SwiftUI

/// Health Score as a full content destination rather than the sheet iPhone presents. It's
/// chart-heavy, so width is the whole point of showing it here.
///
/// `HealthScoreDetailView` brings no navigation container of its own, which is what lets it be
/// hosted either here or in a sheet without changes.
struct IPadHealthScoreView: View {
    let viewModel: CompassViewModel

    var body: some View {
        Group {
            if let score = viewModel.healthScore {
                HealthScoreDetailView(
                    healthScore: score,
                    snapshots: viewModel.scoreSnapshots,
                    payCycleStartDay: AppSettings.storedStartDay,
                    ignoreSubscriptions: Binding(
                        get: { viewModel.ignoreSubscriptions },
                        set: { viewModel.ignoreSubscriptions = $0 }
                    )
                )
            } else {
                ContentUnavailableView(
                    "No Health Score Yet",
                    systemImage: "gauge.medium",
                    description: Text("Add a few weeks of transactions to unlock your score.")
                )
            }
        }
        .appBackground()
        .onAppear { viewModel.load() }
    }
}
