// AppConfig invariants we rely on at runtime:
//   • modelDir is always a literal path (never empty).
//   • save() preserves unknown keys (e.g. cache, integrations, ui).
//   • defaultModelDir is `<basePath>/models`, no shell expansion games.
//
// Tests write to a per-test temp directory so they don't trample the user's
// real ~/.omlx or Library/Application Support state.

import Foundation
import Testing
@testable import oMLX

@Suite(.serialized)
final class AppConfigTests {

    private let tempBase: String

    init() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppConfigTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        tempBase = dir.path
        AppConfig.bootstrapFileURLOverrideForTests = dir.appendingPathComponent("base-path")
    }

    deinit {
        AppConfig.bootstrapFileURLOverrideForTests = nil
        try? FileManager.default.removeItem(atPath: tempBase)
    }

    private func jsonObject(from data: Data) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func dictionary(_ value: Any?) throws -> [String: Any] {
        try #require(value as? [String: Any])
    }

    // MARK: defaultModelDir

    @Test("Default Model Dir Is Base Path Slash Models")
    func defaultModelDirIsBasePathSlashModels() {
        #expect(AppConfig.defaultModelDir(forBasePath: "/some/base") == "/some/base/models")
    }

    @Test("Default Model Dir Handles Trailing Slash")
    func defaultModelDirHandlesTrailingSlash() {
        #expect(AppConfig.defaultModelDir(forBasePath: "/some/base/") == "/some/base/models")
    }

    // MARK: save / round-trip

    @Test("Save Produces Expected Top Level Keys")
    func saveProducesExpectedTopLevelKeys() throws {
        let cfg = AppConfig(
            bindAddress: "127.0.0.1",
            port: 9000,
            apiKey: "secret",
            basePath: tempBase,
            modelDir: "\(tempBase)/models",
            hfEndpoint: "https://hf-mirror.example"
        )

        try cfg.save()

        let url = AppConfig.settingsURL(basePath: tempBase)
        let data = try Data(contentsOf: url)
        let json = try jsonObject(from: data)

        let server = try dictionary(json["server"])
        #expect(server["host"] as? String == "127.0.0.1")
        #expect(server["bind_address"] == nil)
        #expect(server["port"] as? Int == 9000)
        #expect(server["auto_start_on_launch"] as? Bool == true)
        let auth = try dictionary(json["auth"])
        #expect(auth["api_key"] as? String == "secret")
        let model = try dictionary(json["model"])
        #expect(model["model_dirs"] as? [String] == ["\(tempBase)/models"])
        #expect(model["model_dir"] as? String == "\(tempBase)/models")
        let huggingface = try dictionary(json["huggingface"])
        #expect(huggingface["endpoint"] as? String == "https://hf-mirror.example")
        #expect(json["version"] as? String == "1.0")
    }

    @Test("Save Preserves Unknown Keys")
    func savePreservesUnknownKeys() throws {
        // Pre-populate settings.json with keys AppConfig doesn't own. These
        // come from the running Python server (claude_code, integrations, ui,
        // etc.) and must round-trip untouched through Swift saves.
        let url = AppConfig.settingsURL(basePath: tempBase)
        let original: [String: Any] = [
            "version": "1.0",
            "claude_code": ["enabled": true, "model": "claude-opus-4-5"],
            "integrations": ["github": ["token": "abc"]],
            "ui": ["theme": "dark"],
            "server": ["host": "0.0.0.0", "bind_address": "0.0.0.0", "port": 1234],
            "model": [
                "model_dirs": ["/some/where/else"],
                "model_dir": "/will-be-overwritten",
                "max_model_memory": "auto"             // also unknown
            ],
            "cache": ["enabled": true, "ssd_cache_dir": "/x/cache"]
        ]
        try JSONSerialization.data(withJSONObject: original, options: [.prettyPrinted])
            .write(to: url)

        let cfg = AppConfig(
            bindAddress: "127.0.0.1",
            port: 8080,
            autoStartOnLaunch: false,
            apiKey: nil,
            basePath: tempBase,
            modelDir: "/new/models",
            hfEndpoint: ""
        )
        try cfg.save()

        let after = try jsonObject(from: Data(contentsOf: url))

        // Foreign top-level keys survive.
        let claudeCode = try dictionary(after["claude_code"])
        #expect(claudeCode["model"] as? String == "claude-opus-4-5")
        let integrations = try dictionary(after["integrations"])
        #expect(integrations["github"] as? [String: String] == ["token": "abc"])
        let ui = try dictionary(after["ui"])
        #expect(ui["theme"] as? String == "dark")

        // Unknown sub-keys under owned sections survive too — only the fields
        // AppConfig owns get rewritten.
        let server = try dictionary(after["server"])
        #expect(server["host"] as? String == "127.0.0.1")
        #expect(server["auto_start_on_launch"] as? Bool == false)
        #expect(server["bind_address"] == nil)

        let model = try dictionary(after["model"])
        #expect(model["model_dirs"] as? [String] == ["/new/models"], "model_dirs is AppConfig-owned and must stay in sync with model_dir")
        #expect(model["max_model_memory"] as? String == "auto")
        #expect(model["model_dir"] as? String == "/new/models", "model_dir is AppConfig-owned and gets the new value")

        let cache = try dictionary(after["cache"])
        #expect(cache["ssd_cache_dir"] as? String == "/x/cache", "cache.ssd_cache_dir is not in AppConfig's slice")
    }

    @Test("Wildcard Bind Address Uses Host Key But Connects Via Loopback")
    func wildcardBindAddressUsesHostKeyButConnectsViaLoopback() throws {
        let cfg = AppConfig(
            bindAddress: "0.0.0.0",
            port: 9000,
            apiKey: nil,
            basePath: tempBase,
            modelDir: "\(tempBase)/models",
            hfEndpoint: ""
        )

        #expect(cfg.host == "127.0.0.1")

        try cfg.save()

        let url = AppConfig.settingsURL(basePath: tempBase)
        let json = try jsonObject(from: Data(contentsOf: url))
        let server = try dictionary(json["server"])
        #expect(server["host"] as? String == "0.0.0.0")
        #expect(server["bind_address"] == nil)
    }

    @Test("Connectable Host Normalizes Local And Wildcard Hosts")
    func connectableHostNormalizesLocalAndWildcardHosts() {
        #expect(AppConfig.connectableHost(for: "") == "127.0.0.1")
        #expect(AppConfig.connectableHost(for: "0.0.0.0") == "127.0.0.1")
        #expect(AppConfig.connectableHost(for: "::") == "127.0.0.1")
        #expect(AppConfig.connectableHost(for: "localhost") == "127.0.0.1")
        #expect(AppConfig.connectableHost(for: "127.0.0.1") == "127.0.0.1")
    }

    @Test("Connectable Host Uses First Configured Bind Host")
    func connectableHostUsesFirstConfiguredBindHost() {
        #expect(AppConfig.connectableHost(for: "0.0.0.0,127.0.0.1") == "127.0.0.1")
        #expect(AppConfig.connectableHost(for: "192.168.1.10,127.0.0.1") == "192.168.1.10")
    }

    @Test("Connectable Host Preserves IPv6 Loopback")
    func connectableHostPreservesIPv6Loopback() {
        #expect(AppConfig.connectableHost(for: "::1") == "::1")
        #expect(AppConfig.connectableHost(for: "[::1]") == "::1")
    }

    @Test("HTTP URL Builds IPv6 URL")
    func httpURLBuildsIPv6URL() throws {
        let url = try #require(AppConfig.httpURL(host: "::1", port: 9000, path: "/health"))
        #expect(url.absoluteString == "http://[::1]:9000/health")
    }

    @Test("Load Accepts Bind Address Fallback")
    func loadAcceptsBindAddressFallback() throws {
        let url = AppConfig.settingsURL(basePath: tempBase)
        let original: [String: Any] = [
            "server": ["bind_address": "0.0.0.0", "port": 9000],
            "model": ["model_dir": "\(tempBase)/models"]
        ]
        try JSONSerialization.data(withJSONObject: original, options: [.prettyPrinted])
            .write(to: url)

        let slice = try AppConfig.readSettingsForTests(basePath: tempBase)

        #expect(slice.bindAddress == "0.0.0.0")
        #expect(slice.port == 9000)
    }

    @Test("Load Reads Auto Start On Launch")
    func loadReadsAutoStartOnLaunch() throws {
        let url = AppConfig.settingsURL(basePath: tempBase)
        let original: [String: Any] = [
            "server": [
                "host": "127.0.0.1",
                "port": 9000,
                "auto_start_on_launch": false
            ],
            "model": ["model_dir": "\(tempBase)/models"]
        ]
        try JSONSerialization.data(withJSONObject: original, options: [.prettyPrinted])
            .write(to: url)

        let slice = try AppConfig.readSettingsForTests(basePath: tempBase)

        #expect(slice.autoStartOnLaunch == false)
    }

    @Test("Load Reads Model Dirs And Primary Model Dir")
    func loadReadsModelDirsAndPrimaryModelDir() throws {
        let url = AppConfig.settingsURL(basePath: tempBase)
        let original: [String: Any] = [
            "server": ["host": "127.0.0.1", "port": 9000],
            "model": [
                "model_dirs": ["/models/a", "/models/b"],
                "model_dir": "/models/a"
            ]
        ]
        try JSONSerialization.data(withJSONObject: original, options: [.prettyPrinted])
            .write(to: url)

        let slice = try AppConfig.readSettingsForTests(basePath: tempBase)

        #expect(slice.modelDirs ?? [] == ["/models/a", "/models/b"])
        #expect(slice.modelDir == "/models/a")
    }

    // MARK: modelDir invariant

    @Test("Default Config Has Non Empty Model Dir")
    func defaultConfigHasNonEmptyModelDir() {
        // Even on a fresh install with no settings.json, AppConfig.default
        // must hand back a usable modelDir. Otherwise the UI shows a blank
        // field and the server falls through to its own default — diverging.
        #expect(!(AppConfig.default.modelDir.isEmpty))
        #expect(!(AppConfig.default.effectiveModelDirs.isEmpty))
        #expect(AppConfig.default.modelDir.hasSuffix("/models"))
    }

    // MARK: bootstrap file

    @Test("Bootstrap Round Trips")
    func bootstrapRoundTrips() throws {
        // The bootstrap file is the fallback for Finder/Dock launches that
        // don't inherit the user's shell rc. Write a path, read it, clear it.
        let writtenPath = "\(tempBase)/custom-base"
        try AppConfig.writeBootstrapBasePath(writtenPath)

        #expect(AppConfig.readBootstrapBasePath() == writtenPath)

        try AppConfig.writeBootstrapBasePath(nil)
        #expect(AppConfig.readBootstrapBasePath() == nil, "passing nil should remove the file")
    }
}
