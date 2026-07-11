import Foundation

struct StorageItem: Identifiable, Sendable, Equatable {
    let key: String
    let value: String
    var id: String { key }
}

struct StorageCookie: Identifiable, Sendable, Equatable {
    let name: String
    let value: String
    let domain: String
    let path: String
    let secure: Bool
    let httpOnly: Bool
    var id: String { "\(domain)\(path)\(name)" }
}

/// read-only snapshot of a target's cookies and web storage, fetched on demand.
struct StorageSnapshot: Sendable, Equatable {
    var cookies: [StorageCookie] = []
    var local: [StorageItem] = []
    var session: [StorageItem] = []

    var isEmpty: Bool { cookies.isEmpty && local.isEmpty && session.isEmpty }
}
