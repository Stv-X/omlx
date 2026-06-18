import Foundation
import Testing
@testable import oMLX

struct ReleasesCheckerTests {

    @Test("Compare Versions Orders Prerelease Suffixes")
    func compareVersionsOrdersPrereleaseSuffixes() {
        #expect(ReleasesChecker.compareVersions("0.4.0rc2", "0.4.0rc1") == .orderedDescending)
        #expect(ReleasesChecker.compareVersions("0.4.0", "0.4.0rc2") == .orderedDescending)
        #expect(ReleasesChecker.compareVersions("0.4.0rc1", "0.4.0.dev1") == .orderedDescending)
    }

    @Test("Stable Channel Excludes Prereleases")
    func stableChannelExcludesPrereleases() {
        let selected = ReleasesChecker.selectLatest(
            [
                release("v0.4.0rc2"),
                release("v0.3.12"),
            ],
            channel: .stable
        )

        #expect(selected?.tagName == "v0.3.12")
    }

    @Test("Release Candidate Channel Includes RC But Excludes Dev")
    func releaseCandidateChannelIncludesRCButExcludesDev() {
        let selected = ReleasesChecker.selectLatest(
            [
                release("v0.4.1.dev1"),
                release("v0.4.0rc2"),
                release("v0.4.0rc1"),
            ],
            channel: .releaseCandidate
        )

        #expect(selected?.tagName == "v0.4.0rc2")
    }

    @Test("Dev Channel Includes Dev")
    func devChannelIncludesDev() {
        let selected = ReleasesChecker.selectLatest(
            [
                release("v0.4.1.dev1"),
                release("v0.4.0rc2"),
                release("v0.4.0"),
            ],
            channel: .dev
        )

        #expect(selected?.tagName == "v0.4.1.dev1")
    }

    @Test("Find Matching DMG Supports Mac OS Range Assets")
    func findMatchingDMGSupportsMacOSRangeAssets() {
        let sequoia = "oMLX-0.4.4-macos15-sequoia.dmg"
        let tahoeAndNext = "oMLX-0.4.4-macos26-27.dmg"
        let assets = [
            asset(sequoia),
            asset(tahoeAndNext),
        ]

        #expect(ReleasesChecker.findMatchingDMG(
                assets: assets,
                macOSMajor: 15
            )?.name == sequoia)
        #expect(ReleasesChecker.findMatchingDMG(
                assets: assets,
                macOSMajor: 26
            )?.name == tahoeAndNext)
        #expect(ReleasesChecker.findMatchingDMG(
                assets: assets,
                macOSMajor: 27
            )?.name == tahoeAndNext)
        #expect(ReleasesChecker.findMatchingDMG(
                assets: assets,
                macOSMajor: 28
            ) == nil)
    }

    @Test("Find Matching DMG Prefers Exact Asset Over Range Asset")
    func findMatchingDMGPrefersExactAssetOverRangeAsset() {
        let range = "oMLX-0.4.4-macos26-27.dmg"
        let exact = "oMLX-0.4.4-macos27-beta.dmg"
        let assets = [
            asset(range),
            asset(exact),
        ]

        #expect(ReleasesChecker.findMatchingDMG(
                assets: assets,
                macOSMajor: 27
            )?.name == exact)
    }

    private func release(
        _ tag: String,
        prerelease: Bool = false,
        draft: Bool = false
    ) -> GitHubRelease {
        GitHubRelease(
            tagName: tag,
            name: tag,
            body: nil,
            htmlURL: URL(string: "https://github.com/jundot/omlx/releases/tag/\(tag)")!,
            prerelease: prerelease,
            draft: draft,
            assets: []
        )
    }

    private func asset(_ name: String) -> GitHubRelease.Asset {
        GitHubRelease.Asset(
            name: name,
            browserDownloadURL: URL(string: "https://example.com/\(name)")!,
            size: 123
        )
    }
}

@MainActor
struct UpdateControllerPrefsTests {

    @Test("Legacy Auto Download Pref Migrates To Auto Notify")
    func legacyAutoDownloadPrefMigratesToAutoNotify() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("omlx-update-prefs-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = dir.appendingPathComponent("update-prefs.json")
        try Data(
            #"{"channel":"stable","autoCheck":true,"autoDownload":true}"#.utf8
        ).write(to: url)

        let controller = UpdateController(storeURL: url, currentVersion: "0.0.0")
        #expect(controller.autoNotify)

        controller.autoNotify = false

        let saved = try JSONSerialization.jsonObject(
            with: Data(contentsOf: url)
        ) as? [String: Any]
        #expect(saved?["autoNotify"] as? Bool == false)
        #expect(saved?["autoDownload"] == nil)
    }
}
