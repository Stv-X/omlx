// The server-side default profile lives in `GlobalSettings.sampling`.
// These tests pin the decode shape of the nested `sampling` object on the
// read side and the flat `sampling_*` keys on the patch side, so a future
// rename on either edge breaks the build instead of silently dropping the
// server defaults the Profiles tab and Server screen depend on.

import Foundation
import Testing
@testable import oMLX

struct GlobalSettingsSamplingTests {

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    private func jsonObject(from data: Data) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - Decode

    @Test("Sampling Decodes From Nested Object")
    func samplingDecodesFromNestedObject() throws {
        // Mirrors `omlx.settings.SamplingSettings.to_dict()` — the read
        // shape is nested under `sampling`, separate from the flat
        // `sampling_*` keys on the patch body.
        let json = """
        {
            "server": {
                "host": "127.0.0.1",
                "port": 8080,
                "log_level": "info",
                "server_aliases": []
            },
            "sampling": {
                "max_context_window": 32768,
                "max_tokens": 4096,
                "temperature": 0.7,
                "top_p": 0.95,
                "top_k": 20,
                "repetition_penalty": 1.05
            }
        }
        """.data(using: .utf8)!

        let dto = try decoder.decode(GlobalSettingsDTO.self, from: json)
        #expect(dto.sampling?.maxContextWindow == 32768)
        #expect(dto.sampling?.maxTokens == 4096)
        #expect(dto.sampling?.temperature == 0.7)
        #expect(dto.sampling?.topP == 0.95)
        #expect(dto.sampling?.topK == 20)
        #expect(dto.sampling?.repetitionPenalty == 1.05)
    }

    @Test("Sampling Field Is Optional")
    func samplingFieldIsOptional() throws {
        // Older server builds, or a server that hasn't populated sampling
        // yet, omit the key entirely. Decode must succeed with nil.
        let json = """
        {
            "server": {
                "host": "127.0.0.1",
                "port": 8080,
                "log_level": "info",
                "server_aliases": []
            }
        }
        """.data(using: .utf8)!

        let dto = try decoder.decode(GlobalSettingsDTO.self, from: json)
        #expect(dto.sampling == nil)
    }

    // MARK: - Patch encode

    @Test("Patch Encodes Embedding Batch Size As Snake Case Flat Key")
    func patchEncodesEmbeddingBatchSizeAsSnakeCaseFlatKey() throws {
        // Scheduler writes use the flat GlobalSettingsRequest shape, so the
        // Swift camelCase property must encode to embedding_batch_size.
        var patch = GlobalSettingsPatch()
        patch.embeddingBatchSize = 8

        let data = try encoder.encode(patch)
        let str = String(data: data, encoding: .utf8) ?? ""

        #expect(str.contains("\"embedding_batch_size\":8"), "got: \(str)")
    }

    @Test("Patch Encodes Model Dirs As Snake Case Flat Key")
    func patchEncodesModelDirsAsSnakeCaseFlatKey() throws {
        var patch = GlobalSettingsPatch()
        patch.modelDirs = ["/Users/test/.omlx/models", "/Users/test/.lmstudio/models"]

        let data = try encoder.encode(patch)
        let json = try jsonObject(from: data)

        #expect(json["model_dirs"] as? [String] == [
            "/Users/test/.omlx/models",
            "/Users/test/.lmstudio/models"
        ])
    }

    @Test("Patch Encodes HF Cache Enabled As Snake Case Flat Key")
    func patchEncodesHfCacheEnabledAsSnakeCaseFlatKey() throws {
        var patch = GlobalSettingsPatch()
        patch.hfCacheEnabled = false

        let data = try encoder.encode(patch)
        let json = try jsonObject(from: data)

        #expect(json["hf_cache_enabled"] as? Bool == false)
    }

    @Test("Patch Encodes Hot Cache Max Size As Snake Case Flat Key")
    func patchEncodesHotCacheMaxSizeAsSnakeCaseFlatKey() throws {
        var patch = GlobalSettingsPatch()
        patch.hotCacheMaxSize = "8GB"

        let data = try encoder.encode(patch)
        let json = try jsonObject(from: data)

        #expect(json["hot_cache_max_size"] as? String == "8GB")
    }

    @Test("Patch Encodes Sampling Fields As Snake Case Flat Keys")
    func patchEncodesSamplingFieldsAsSnakeCaseFlatKeys() throws {
        // The Python `GlobalSettingsRequest` accepts the sampling defaults
        // as flat `sampling_*` keys (omlx/admin/routes.py:229-234), not
        // nested. The .convertToSnakeCase strategy on Swift's encoder must
        // produce exactly that wire shape.
        var patch = GlobalSettingsPatch()
        patch.samplingMaxContextWindow = 32768
        patch.samplingMaxTokens = 4096
        patch.samplingTemperature = 0.5
        patch.samplingTopP = 0.9
        patch.samplingTopK = 40
        patch.samplingRepetitionPenalty = 1.1

        let data = try encoder.encode(patch)
        let str = String(data: data, encoding: .utf8) ?? ""

        #expect(str.contains("\"sampling_max_context_window\":32768"), "got: \(str)")
        #expect(str.contains("\"sampling_max_tokens\":4096"))
        #expect(str.contains("\"sampling_temperature\":0.5"))
        #expect(str.contains("\"sampling_top_p\":0.9"))
        #expect(str.contains("\"sampling_top_k\":40"))
        #expect(str.contains("\"sampling_repetition_penalty\":1.1"))
    }

    @Test("Patch Omits Nil Sampling Fields")
    func patchOmitsNilSamplingFields() throws {
        // `encodeIfPresent` for Optionals means nil fields are skipped —
        // the server's merge semantics treat any present field as an edit.
        // A patch that only touches temperature must not also overwrite
        // top_p / top_k / etc to nil.
        var patch = GlobalSettingsPatch()
        patch.samplingTemperature = 0.42

        let data = try encoder.encode(patch)
        let str = String(data: data, encoding: .utf8) ?? ""

        #expect(str.contains("\"sampling_temperature\":0.42"))
        #expect(!(str.contains("sampling_max_tokens")))
        #expect(!(str.contains("sampling_top_p")))
        #expect(!(str.contains("sampling_top_k")))
        #expect(!(str.contains("sampling_repetition_penalty")))
        #expect(!(str.contains("sampling_max_context_window")))
    }

    @Test("Patch With No Sampling Fields Omits All Keys")
    func patchWithNoSamplingFieldsOmitsAllKeys() throws {
        // A purely network-side patch (e.g. updating port) must not carry
        // empty sampling keys, or the server's merge logic would no-op
        // through them but the wire payload bloats.
        var patch = GlobalSettingsPatch()
        patch.port = 9000

        let data = try encoder.encode(patch)
        let str = String(data: data, encoding: .utf8) ?? ""

        #expect(str.contains("\"port\":9000"))
        #expect(!(str.contains("sampling_")))
    }
}
