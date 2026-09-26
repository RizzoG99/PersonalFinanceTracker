import Foundation

extension FeatureDiscoveryManifest {
    static var fallback: FeatureDiscoveryManifest {
        fallback(for: Locale.current.language.languageCode?.identifier)
    }

    static func fallback(for languageCode: String?) -> FeatureDiscoveryManifest {
        let isItalian = languageCode == "it"
        func copy(_ english: String, _ italian: String) -> String { isItalian ? italian : english }

        return FeatureDiscoveryManifest(
            schemaVersion: 1,
            contentVersion: "2026.09.26.1",
            onboarding: Onboarding(
            id: "explore-the-app",
            title: copy("Explore Personal Finance", "Scopri Personal Finance"),
            pages: [
                Page(
                    id: "overview",
                    title: copy("Your money, in one place", "Tutto il tuo denaro, in un unico posto"),
                    body: copy("Keep everyday spending and income together, so your financial picture stays clear.", "Tieni insieme spese ed entrate quotidiane, per avere sempre un quadro finanziario chiaro."),
                    symbolName: "sparkles",
                    media: nil,
                    destination: .home
                ),
                Page(
                    id: "activity",
                    title: copy("Stay close to every transaction", "Tieni d'occhio ogni transazione"),
                    body: copy("Add, search, and filter activity whenever you need to understand where your money went.", "Aggiungi, cerca e filtra le attività per capire sempre dove sono finiti i tuoi soldi."),
                    symbolName: "list.bullet.rectangle",
                    media: nil,
                    destination: .activity
                ),
                Page(
                    id: "budgets",
                    title: copy("Plan with confidence", "Pianifica con sicurezza"),
                    body: copy("Set category budgets and see your progress before a small expense becomes a surprise.", "Imposta budget per categoria e controlla i progressi prima che una piccola spesa diventi una sorpresa."),
                    symbolName: "chart.pie",
                    media: nil,
                    destination: .budgets
                ),
                Page(
                    id: "insights",
                    title: copy("Start with one transaction", "Inizia con una transazione"),
                    body: copy("Add an expense or income in less than a minute, then let Personal Finance reveal your progress.", "Aggiungi una spesa o un'entrata in meno di un minuto, poi lascia che Personal Finance mostri i tuoi progressi."),
                    symbolName: "plus.circle",
                    media: nil,
                    destination: .addTransaction
                )
            ]
            ),
            releases: [
            Release(
                id: "1.0-feature-discovery",
                version: "1.0",
                title: copy("A clearer way to explore", "Un modo più chiaro per esplorare"),
                summary: copy("Meet the tools that help you understand, plan, and move forward with your money.", "Scopri gli strumenti che ti aiutano a capire, pianificare e progredire con i tuoi soldi."),
                items: [
                    ReleaseItem(
                        id: "feature-tour",
                        title: copy("Explore the app", "Scopri l'app"),
                        body: copy("A fresh guide introduces the essentials when you are new, and remains available whenever you want a refresher.", "Una guida rapida presenta le funzioni essenziali e resta disponibile quando vuoi rivederle."),
                        symbolName: "sparkles",
                        media: nil,
                        destination: .home,
                        actionTitle: copy("Explore now", "Esplora ora")
                    )
                ]
            ),
            Release(
                id: "1.0-financial-pulse",
                version: "1.0",
                title: copy("Financial Pulse is here", "È arrivato l'Impulso finanziario"),
                summary: copy("Build a daily money habit and keep your weekly spending room close at hand.", "Crea un'abitudine quotidiana con il denaro e tieni sempre a portata di mano il margine di spesa settimanale."),
                items: [
                    ReleaseItem(
                        id: "daily-financial-pulse",
                        title: copy("A daily money check-in", "Un check-in quotidiano con il denaro"),
                        body: copy("The new Financial Pulse helps you log your day, confirm a no-spend day, and build a calm check-in streak.", "Il nuovo Impulso finanziario ti aiuta a registrare la giornata, confermare una giornata senza spese e creare una tranquilla serie di check-in."),
                        symbolName: "waveform.path.ecg",
                        media: nil,
                        destination: .home,
                        actionTitle: copy("Open Home", "Apri Home")
                    ),
                    ReleaseItem(
                        id: "safe-to-spend-widget",
                        title: copy("Safe to spend, at a glance", "Quanto puoi spendere, a colpo d'occhio"),
                        body: copy("Add the new Home Screen widget to see your daily spending room and open Insights when you need the full picture.", "Aggiungi il nuovo widget alla schermata Home per vedere il margine di spesa giornaliero e aprire Insights quando vuoi il quadro completo."),
                        symbolName: "calendar.day.timeline.leading",
                        media: nil,
                        destination: .insights,
                        actionTitle: copy("Open Insights", "Apri Insights")
                    )
                ]
            ),
            Release(
                id: "1.0-highlights-2026-09",
                version: "1.0",
                title: copy("More ways to stay on top of your money", "Più modi per gestire il tuo denaro"),
                summary: copy("Catch up on four powerful features you may have missed.", "Scopri quattro funzioni che potresti non aver ancora provato."),
                items: [
                    ReleaseItem(
                        id: "travels",
                        title: copy("Organize spending by trip", "Organizza le spese per viaggio"),
                        body: copy("Group Activity rows by trip, then see travel dates, daily cost, and spending by category. Every expense still counts normally in Budgets and Insights.", "Raggruppa per viaggio le righe in Attività, poi consulta date, costo giornaliero e spese per categoria. Ogni spesa continua a essere conteggiata normalmente in Budget e Analisi."),
                        symbolName: "airplane",
                        media: nil,
                        destination: .travels,
                        actionTitle: copy("Open Travels", "Apri Viaggi")
                    ),
                    ReleaseItem(
                        id: "receipt-scan",
                        title: copy("Scan a receipt in seconds", "Scansiona uno scontrino in pochi secondi"),
                        body: copy("Scan a receipt on your device to prefill the amount, date, merchant, and category, then review everything before saving.", "Scansiona uno scontrino sul dispositivo per precompilare importo, data, esercente e categoria, poi controlla tutto prima di salvare."),
                        symbolName: "doc.text.viewfinder",
                        media: nil,
                        destination: .receiptScan,
                        actionTitle: copy("Scan a receipt", "Scansiona uno scontrino")
                    ),
                    ReleaseItem(
                        id: "recurring-transactions",
                        title: copy("Manage recurring payments in one place", "Gestisci i pagamenti ricorrenti in un unico posto"),
                        body: copy("Create recurring rules, detect them while importing bank files, and manage every recurring payment from one place.", "Crea regole ricorrenti, rilevale durante l’importazione dei file bancari e gestisci tutti i pagamenti ricorrenti in un unico posto."),
                        symbolName: "repeat.circle",
                        media: nil,
                        destination: .recurring,
                        actionTitle: copy("Open Recurring", "Apri Ricorrenti")
                    ),
                    ReleaseItem(
                        id: "siri-widgets",
                        title: copy("Siri and widgets, ready when you are", "Siri e widget, sempre a portata di mano"),
                        body: copy("Ask **Siri** to add a transaction, or add **Financial Pulse**, **Scan Receipt**, and **Safe to Spend** widgets to your Home or Lock Screen.", "Chiedi a **Siri** di aggiungere una transazione oppure aggiungi i widget **Impulso finanziario**, **Scansiona uno scontrino** e **Quanto puoi spendere** alla schermata Home o di blocco."),
                        symbolName: "waveform",
                        media: nil,
                        destination: .siriWidgetsGuide,
                        actionTitle: copy("Learn how", "Scopri come")
                    )
                ]
            )
            ]
        )
    }

    /// Keeps the remote media and routing while preventing known, first-party cards
    /// from displaying English copy if a locale-specific manifest is temporarily
    /// unavailable during a rollout.
    func applyingBuiltInCopy(for languageCode: String?) -> FeatureDiscoveryManifest {
        guard languageCode == "it" else { return self }

        let italianFallback = FeatureDiscoveryManifest.fallback(for: languageCode)
        let localizedPages = onboarding.pages.map { page in
            guard let translatedPage = italianFallback.onboarding.pages.first(where: { $0.id == page.id }) else {
                return page
            }
            return Page(
                id: page.id,
                title: translatedPage.title,
                body: translatedPage.body,
                symbolName: page.symbolName,
                media: page.media,
                destination: page.destination
            )
        }

        let localizedReleases = releases.map { release in
            guard let translatedRelease = italianFallback.releases.first(where: { $0.id == release.id }) else {
                return release
            }
            let localizedItems = release.items.map { item in
                guard let translatedItem = translatedRelease.items.first(where: { $0.id == item.id }) else {
                    return item
                }
                return ReleaseItem(
                    id: item.id,
                    title: translatedItem.title,
                    body: translatedItem.body,
                    symbolName: item.symbolName,
                    media: item.media,
                    destination: item.destination,
                    actionTitle: translatedItem.actionTitle
                )
            }
            return Release(
                id: release.id,
                version: release.version,
                title: translatedRelease.title,
                summary: translatedRelease.summary,
                items: localizedItems
            )
        }

        return FeatureDiscoveryManifest(
            schemaVersion: schemaVersion,
            contentVersion: contentVersion,
            onboarding: Onboarding(id: onboarding.id, title: italianFallback.onboarding.title, pages: localizedPages),
            releases: localizedReleases
        )
    }
}
