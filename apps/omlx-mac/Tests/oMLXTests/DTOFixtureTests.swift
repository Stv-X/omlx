// Round-trip JSON fixtures captured from a live oMLX server through each
// DTO's Codable decoder. The signal we want is "server JSON changed shape
// in a way the Swift app can't decode" — the fixture lives in git, so a
// passing test means the wire contract is unchanged.
//
// Fixtures were captured via curl against the running server (see
// docs/Fixtures/README inline note below) and sanitized: API keys
// redacted, real paths replaced with `/Users/test/...`, LAN IPs swapped
// for the RFC 5737 documentation range (192.0.2.x).
//
// To re-capture (e.g., after intentional server-side wire changes):
//   PORT=<port> KEY=<api-key> COOKIES=$(mktemp)
//   curl -s -c "$COOKIES" -X POST "http://127.0.0.1:$PORT/admin/api/login" \
//        -H "Content-Type: application/json" \
//        -d "{\"api_key\":\"$KEY\",\"remember\":true}"
//   curl -s -b "$COOKIES" "http://127.0.0.1:$PORT/admin/api/<endpoint>" \
//        | python3 -m json.tool > Fixtures/<name>.json
// Then re-sanitize before committing.

import Foundation
import Testing
@testable import oMLX

struct DTOFixtureTests {

    // Matches the JSONDecoder config in OMLXClient: snake_case keys → camelCase
    // Codable members. Any DTO that the real client decodes must round-trip
    // here too.
    private static func makeDecoder() -> JSONDecoder {
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        return dec
    }

    private func fixture(_ name: String) throws -> Data {
        let dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
        let url = dir.appendingPathComponent("\(name).json")
        return try Data(contentsOf: url)
    }

    // MARK: - Stats

    @Test("Stats Session Fixture Decodes")
    func statsSessionFixtureDecodes() throws {
        let data = try fixture("stats-session")
        let stats = try Self.makeDecoder().decode(StatsDTO.self, from: data)

        // The four-field tuple we surface across the menubar + Status screen.
        #expect(stats.host != nil)
        #expect(stats.port != nil)
        #expect(stats.cliPrefix != nil, "Stats must carry cli_prefix so Integrations can render `omlx launch …` commands.")
        #expect(stats.apiKey != nil, "Stats must surface api_key (empty string allowed) so the Welcome-skip path can recover it.")

        // active_models is the structure Status renders; nested fields can
        // be nil but the wrapper must always decode.
        _ = stats.activeModels
    }

    // MARK: - Server info

    @Test("Server Info Fixture Decodes")
    func serverInfoFixtureDecodes() throws {
        let data = try fixture("server-info")
        let info = try Self.makeDecoder().decode(ServerInfoDTO.self, from: data)

        #expect(!(info.host.isEmpty), "ServerInfo.host must be present — drives Settings → Listen Address.")
        #expect(info.port > 0)
    }

    // MARK: - Global settings

    @Test("Global Settings Fixture Decodes")
    func globalSettingsFixtureDecodes() throws {
        let data = try fixture("global-settings")
        let settings = try Self.makeDecoder().decode(GlobalSettingsDTO.self, from: data)

        // Sub-structures Server / Status / Integrations screens depend on.
        _ = settings.server
        _ = settings.model
        #expect(settings.auth != nil, "auth block missing")
        #expect(settings.claudeCode != nil, "claude_code block missing")
        #expect(settings.integrations != nil, "integrations block missing")
        #expect(settings.scheduler?.embeddingBatchSize == 32)
        #expect(settings.huggingface?.hfCacheEnabled == true)
    }

    // MARK: - Models list

    @Test("Models List Fixture Decodes")
    func modelsListFixtureDecodes() throws {
        let data = try fixture("models")
        let list = try Self.makeDecoder().decode(ListModelsResponse.self, from: data)

        // The fixture was captured with at least one model in the library.
        // Future re-captures could be empty, so just assert the array
        // structure decoded — not that it has entries.
        _ = list.models
        // Sanity-check the first entry's shape if present.
        if let first = list.models.first {
            #expect(!(first.id.isEmpty), "ModelDTO.id must be non-empty.")
        }
    }

    // MARK: - Profile list (per-model)

    @Test("Model Profiles Fixture Decodes")
    func modelProfilesFixtureDecodes() throws {
        let data = try fixture("model-profiles")
        let resp = try Self.makeDecoder().decode(ProfileListResponse.self, from: data)
        _ = resp.profiles
    }

    // MARK: - Profile templates

    @Test("Profile Templates Fixture Decodes")
    func profileTemplatesFixtureDecodes() throws {
        let data = try fixture("profile-templates")
        let resp = try Self.makeDecoder().decode(TemplateListResponse.self, from: data)
        // Templates array is empty in the captured fixture (no templates
        // configured on the dev server). Just exercise the decoder so a
        // server-side rename of `templates` → `items` would fail loudly.
        _ = resp.templates
    }
}
