import SwiftUI

@MainActor
final class ModelsScreenVM: ObservableObject {
    @Published private(set) var allModels: [ModelDTO] = []
    @Published var lastError: String?
    /// Library row the user just clicked "trash" on; non-nil drives the
    /// confirmation dialog. Cleared on cancel or after delete completes.
    @Published var pendingRemoveID: String?
    /// While a delete is in flight, the row shows a spinner instead of the
    /// trash glyph and the whole row's button-stack is disabled to prevent
    /// double-tap deletes against a model the server is still unloading.
    @Published private(set) var deletingID: String?

    private weak var client: OMLXClient?
    private var pollTask: Task<Void, Never>?

    var activeModels: [ModelDTO] {
        allModels.filter { $0.loaded || $0.isLoading }
    }
    var libraryModels: [ModelDTO] { allModels }

    func start(client: OMLXClient) async {
        self.client = client
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    func load(id: String, client: OMLXClient) {
        Task { [weak self] in
            do {
                _ = try await client.loadModel(id: id)
                await self?.refresh()
            } catch {
                guard let self else { return }
                self.lastError = error.omlxDescription
            }
        }
    }

    func unload(id: String, client: OMLXClient) {
        Task { [weak self] in
            do {
                _ = try await client.unloadModel(id: id)
                await self?.refresh()
            } catch {
                guard let self else { return }
                self.lastError = error.omlxDescription
            }
        }
    }

    func remove(id: String, client: OMLXClient) {
        pendingRemoveID = nil
        deletingID = id
        Task { [weak self] in
            defer { Task { @MainActor [weak self] in self?.deletingID = nil } }
            do {
                _ = try await client.deleteHFModel(modelName: id)
                await self?.refresh()
                self?.lastError = nil
            } catch {
                guard let self else { return }
                self.lastError = error.omlxDescription
            }
        }
    }

    private func refresh() async {
        guard let client else { return }
        do {
            self.allModels = sortModelsByName(try await client.listModels().models)
            self.lastError = nil
        } catch {
            self.lastError = error.omlxDescription
        }
    }

}
