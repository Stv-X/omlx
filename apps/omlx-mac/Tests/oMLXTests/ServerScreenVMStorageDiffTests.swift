// ServerScreenVM.storageDiff is what gates the Apply button and the actual
// migration. The risk is false-positive diffs (claiming a change when there
// isn't one) that would bounce the server for an idempotent click — or
// false-negative diffs that silently swallow user edits.
//
// All cases below feed the diff text fields that look textually different
// from `services.config` but are semantically equivalent — and assert no
// diff is reported.

import Foundation
import Testing
@testable import oMLX

@MainActor
struct ServerScreenVMStorageDiffTests {

    private func makeServices(basePath: String, modelDirs: [String]) -> AppServices {
        let cfg = AppConfig(
            bindAddress: "127.0.0.1",
            port: 8080,
            apiKey: nil,
            basePath: basePath,
            modelDir: modelDirs[0],
            modelDirs: modelDirs,
            hfEndpoint: ""
        )
        return AppServices(config: cfg, server: nil)
    }

    private func makeServices(basePath: String, modelDir: String) -> AppServices {
        makeServices(basePath: basePath, modelDirs: [modelDir])
    }

    @Test("No Changes")
    func noChanges() {
        let services = makeServices(basePath: "/Users/Fido/.omlx",
                                    modelDir: "/Users/Fido/.omlx/models")
        let vm = ServerScreenVM()
        vm.basePathText = "/Users/Fido/.omlx"
        vm.modelDirTexts = ["/Users/Fido/.omlx/models"]

        let diff = vm.storageDiff(services: services)
        #expect(!(diff.baseChanged))
        #expect(!(diff.modelDirsChanged))
        #expect(!(diff.hasChanges))
    }

    @Test("Base Changed Only")
    func baseChangedOnly() {
        let services = makeServices(basePath: "/Users/Fido/.omlx",
                                    modelDir: "/Users/Fido/.omlx/models")
        let vm = ServerScreenVM()
        vm.basePathText = "/Users/Fido/.omlx-other"
        vm.modelDirTexts = ["/Users/Fido/.omlx/models"]

        let diff = vm.storageDiff(services: services)
        #expect(diff.baseChanged)
        #expect(!(diff.modelDirsChanged))
        #expect(diff.normalizedBase == "/Users/Fido/.omlx-other")
    }

    @Test("Model Dir Changed Only")
    func modelDirChangedOnly() {
        let services = makeServices(basePath: "/Users/Fido/.omlx",
                                    modelDir: "/Users/Fido/.omlx/models")
        let vm = ServerScreenVM()
        vm.basePathText = "/Users/Fido/.omlx"
        vm.modelDirTexts = ["/Volumes/SSD/models"]

        let diff = vm.storageDiff(services: services)
        #expect(!(diff.baseChanged))
        #expect(diff.modelDirsChanged)
        #expect(diff.normalizedModelDir == "/Volumes/SSD/models")
        #expect(diff.normalizedModelDirs == ["/Volumes/SSD/models"])
    }

    @Test("Both Changed")
    func bothChanged() {
        let services = makeServices(basePath: "/Users/Fido/.omlx",
                                    modelDir: "/Users/Fido/.omlx/models")
        let vm = ServerScreenVM()
        vm.basePathText = "/Users/Fido/.omlx-other"
        vm.modelDirTexts = ["/Volumes/SSD/models"]

        #expect(vm.storageDiff(services: services).hasChanges)
    }

    @Test("Trailing Slash Normalizes To No Diff")
    func trailingSlashNormalizesToNoDiff() {
        // standardizingPath strips the trailing slash. Typing it in the
        // field must not flip the Apply button into "pending".
        let services = makeServices(basePath: "/Users/Fido/.omlx",
                                    modelDir: "/Users/Fido/.omlx/models")
        let vm = ServerScreenVM()
        vm.basePathText = "/Users/Fido/.omlx/"
        vm.modelDirTexts = ["/Users/Fido/.omlx/models/"]

        let diff = vm.storageDiff(services: services)
        #expect(!(diff.baseChanged))
        #expect(!(diff.modelDirsChanged))
    }

    @Test("Whitespace Normalizes To No Diff")
    func whitespaceNormalizesToNoDiff() {
        let services = makeServices(basePath: "/Users/Fido/.omlx",
                                    modelDir: "/Users/Fido/.omlx/models")
        let vm = ServerScreenVM()
        vm.basePathText = "  /Users/Fido/.omlx  "
        vm.modelDirTexts = ["\n/Users/Fido/.omlx/models\t"]

        let diff = vm.storageDiff(services: services)
        #expect(!(diff.baseChanged))
        #expect(!(diff.modelDirsChanged))
    }

    @Test("Tilde Expansion")
    func tildeExpansion() {
        let home = NSHomeDirectory()
        let services = makeServices(basePath: "\(home)/.omlx",
                                    modelDir: "\(home)/.omlx/models")
        let vm = ServerScreenVM()
        vm.basePathText = "~/.omlx"
        vm.modelDirTexts = ["~/.omlx/models"]

        let diff = vm.storageDiff(services: services)
        #expect(!(diff.baseChanged), "tilde must expand before comparing to the home-absolute config value")
        #expect(!(diff.modelDirsChanged))
    }

    @Test("Empty Model Dirs Triggers Invalid Change")
    func emptyModelDirsTriggersInvalidChange() {
        // Clearing every row is a real edit, but applyServerSettings rejects
        // it before sending a patch because the server requires at least one
        // model root.
        let services = makeServices(basePath: "/Users/Fido/.omlx",
                                    modelDir: "/Users/Fido/.omlx/models")
        let vm = ServerScreenVM()
        vm.basePathText = ""
        vm.modelDirTexts = [""]

        let diff = vm.storageDiff(services: services)
        #expect(!(diff.baseChanged))
        #expect(diff.modelDirsChanged)
        #expect(diff.normalizedModelDirs == [])
    }

    @Test("Multiple Model Dirs Normalize To No Diff")
    func multipleModelDirsNormalizeToNoDiff() {
        let services = makeServices(
            basePath: "/Users/Fido/.omlx",
            modelDirs: ["/Users/Fido/.omlx/models", "/Volumes/SSD/models"]
        )
        let vm = ServerScreenVM()
        vm.basePathText = "/Users/Fido/.omlx"
        vm.modelDirTexts = [
            " /Users/Fido/.omlx/models/ ",
            "/Volumes/SSD/models",
            "/Volumes/SSD/models/"
        ]

        let diff = vm.storageDiff(services: services)
        #expect(!(diff.modelDirsChanged))
        #expect(diff.normalizedModelDirs == [
            "/Users/Fido/.omlx/models",
            "/Volumes/SSD/models"
        ])
    }

    @Test("Model Dir Reorder Triggers Change")
    func modelDirReorderTriggersChange() {
        let services = makeServices(
            basePath: "/Users/Fido/.omlx",
            modelDirs: ["/Users/Fido/.omlx/models", "/Volumes/SSD/models"]
        )
        let vm = ServerScreenVM()
        vm.basePathText = "/Users/Fido/.omlx"
        vm.modelDirTexts = ["/Volumes/SSD/models", "/Users/Fido/.omlx/models"]

        let diff = vm.storageDiff(services: services)
        #expect(diff.modelDirsChanged)
        #expect(diff.normalizedModelDir == "/Volumes/SSD/models")
    }

    @Test("Apply Config Keeps Wildcard Bind But Uses Loopback Endpoint")
    func applyConfigKeepsWildcardBindButUsesLoopbackEndpoint() {
        let cfg = AppConfig(
            bindAddress: "0.0.0.0",
            port: 8080,
            apiKey: nil,
            basePath: "/Users/Fido/.omlx",
            modelDir: "/Users/Fido/.omlx/models",
            modelDirs: ["/Users/Fido/.omlx/models"],
            hfEndpoint: ""
        )
        let vm = ServerScreenVM()

        vm.applyConfig(cfg)

        #expect(vm.host == "0.0.0.0")
        #expect(vm.appliedBindAddress == "0.0.0.0")
        #expect(vm.effectiveHost == "127.0.0.1")
    }
}
