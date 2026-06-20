import SwiftUI

struct PayCycleAware: ViewModifier {
    @Environment(AppSettings.self) private var appSettings
    let load: () -> Void

    func body(content: Content) -> some View {
        content
            .onAppear { load() }
            .onChange(of: appSettings.payCycleStartDay) { _, _ in load() }
    }
}

extension View {
    func payCycleAware(load: @escaping () -> Void) -> some View {
        modifier(PayCycleAware(load: load))
    }
}
