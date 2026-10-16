import Foundation
import SwiftData

/// Process-local revisions for transaction read caches. didSave is observed synchronously
/// on the writer's thread, so a subsequent reader cannot miss a committed direct-context
/// or second-actor write. No live models or contexts are retained or transferred.
/// Cross-process writes require explicit invalidation on a return from the background.
final class TransactionSnapshotRevision: @unchecked Sendable {
    static let shared = TransactionSnapshotRevision()

    private struct Entry {
        weak var container: ModelContainer?
        var revision: UInt64 = 0
    }

    // All mutable state is protected by this lock, including notification callbacks.
    private let lock = NSLock()
    private var entries: [ObjectIdentifier: Entry] = [:]
    private var observer: NSObjectProtocol?

    private init() {
        observer = NotificationCenter.default.addObserver(
            forName: ModelContext.didSave, object: nil, queue: nil
        ) { [weak self] notification in
            guard let context = notification.object as? ModelContext else { return }
            guard Self.affectsTransactionSnapshots(notification) else { return }
            self?.advance(for: context.container)
        }
    }

    func revision(for container: ModelContainer) -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        let key = ObjectIdentifier(container)
        if entries[key]?.container !== container {
            // Weak entries prevent retaining stores after tests/previews/shell teardown.
            entries = entries.filter { $0.value.container != nil }
            entries[key] = Entry(container: container)
        }
        return entries[key]?.revision ?? 0
    }

    /// Also used for restore/foreground invalidation: invalidate every reader of this
    /// container rather than only the actor through which the notification was delivered.
    func advance(for container: ModelContainer) {
        lock.lock()
        defer { lock.unlock() }
        let key = ObjectIdentifier(container)
        guard var entry = entries[key], entry.container === container else { return }
        entry.revision &+= 1
        entries[key] = entry
    }

    private static func affectsTransactionSnapshots(_ notification: Notification) -> Bool {
        let info = notification.userInfo ?? [:]
        if let invalidated = info[ModelContext.NotificationKey.invalidatedAllIdentifiers.rawValue] as? Bool,
           invalidated { return true }

        var hasIdentifierDetails = false
        for key in [ModelContext.NotificationKey.insertedIdentifiers, .updatedIdentifiers, .deletedIdentifiers] {
            let value = info[key.rawValue]
            let identifiers: [PersistentIdentifier]
            if let array = value as? [PersistentIdentifier] {
                identifiers = array
            } else if let set = value as? Set<PersistentIdentifier> {
                identifiers = Array(set)
            } else {
                continue
            }
            hasIdentifierDetails = true
            if identifiers.contains(where: {
                let name = $0.entityName.split(separator: ".").last
                return name == "TransactionModel" || name == "CategoryModel"
            }) { return true }
        }
        // Be conservative when SwiftData supplies no identifier details. Health snapshots
        // and unrelated saves with details do not invalidate a 5k transaction read cache.
        return !hasIdentifierDetails
    }
}
