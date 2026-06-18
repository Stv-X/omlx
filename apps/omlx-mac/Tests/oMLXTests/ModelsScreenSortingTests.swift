import Testing
@testable import oMLX

struct ModelsScreenSortingTests {

    @Test("Sort Models By Name Ignores Case")
    func sortModelsByNameIgnoresCase() {
        let models = [
            makeModel("Qwen"),
            makeModel("gpt"),
            makeModel("Llama"),
            makeModel("mistral"),
        ]

        let ids = sortModelsByName(models).map(\.id)

        #expect(ids == ["gpt", "Llama", "mistral", "Qwen"])
    }

    @Test("Sort Models By Name Preserves Input Order For Case Only Ties")
    func sortModelsByNamePreservesInputOrderForCaseOnlyTies() {
        let models = [
            makeModel("qwen"),
            makeModel("Qwen"),
            makeModel("QWEN"),
        ]

        let ids = sortModelsByName(models).map(\.id)

        #expect(ids == ["qwen", "Qwen", "QWEN"])
    }

    private func makeModel(_ id: String) -> ModelDTO {
        ModelDTO(
            id: id,
            modelPath: nil,
            loaded: false,
            isLoading: false,
            estimatedSize: 0,
            estimatedSizeFormatted: nil,
            pinned: nil,
            isDefault: nil,
            engineType: nil,
            modelType: nil,
            configModelType: nil,
            thinkingDefault: nil,
            dflashCompatible: nil,
            dflashCompatibilityReason: nil,
            dflashSsdCacheAvailable: nil,
            mtpCompatible: nil,
            mtpCompatibilityReason: nil,
            settings: nil
        )
    }
}
