import Foundation

extension DebugSession {

    // MARK: - Storage

    func loadStorage(force: Bool = false) {
        guard let connection = activeConnection else { return }
        if workspace.storage != nil && !force { return }
        workspace.storageLoading = true
        storageLoadTask?.cancel()
        storageLoadTask = Task { [weak self] in
            let snapshot = await connection.fetchStorage()
            guard let self, !Task.isCancelled else { return }
            self.workspace.storage = snapshot
            self.workspace.storageLoading = false
        }
    }
}
