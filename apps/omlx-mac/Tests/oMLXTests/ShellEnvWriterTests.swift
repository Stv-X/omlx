import Foundation
import Testing
@testable import oMLX

@Suite(.serialized)
final class ShellEnvWriterTests {
    private let tempHome: URL

    init() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShellEnvWriterTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        tempHome = dir
        ShellEnvWriter.homeOverrideForTests = dir
        ShellEnvWriter.shellOverrideForTests = "/bin/zsh"
        ShellEnvWriter.publicBinDirsOverrideForTests = []
        ShellEnvWriter.cliPathPrefsURLOverrideForTests = dir
            .appendingPathComponent("prefs", isDirectory: true)
            .appendingPathComponent("cli-path-prefs.json")
        ShellEnvWriter.pathOverrideForTests = "/usr/bin"
    }

    deinit {
        ShellEnvWriter.homeOverrideForTests = nil
        ShellEnvWriter.shellOverrideForTests = nil
        ShellEnvWriter.publicBinDirsOverrideForTests = nil
        ShellEnvWriter.cliPathPrefsURLOverrideForTests = nil
        ShellEnvWriter.pathOverrideForTests = nil
        try? FileManager.default.removeItem(at: tempHome)
    }

    @Test("Ensure CLI Shim Writes Executable Wrapper Without Editing Shell Files")
    func ensureCLIShimWritesExecutableWrapperWithoutEditingShellFiles() throws {
        let appURL = try makeFakeAppURL()

        let result = try ShellEnvWriter.ensureCLIShim(appBundleURL: appURL)

        let shim = tempHome
            .appendingPathComponent(".omlx", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("omlx")
        #expect(FileManager.default.isExecutableFile(atPath: shim.path))
        let shimText = try String(contentsOf: shim, encoding: .utf8)
        #expect(shimText.contains("Contents/MacOS/omlx-cli"))
        #expect(shimText.contains("exec "))

        let zshrc = tempHome.appendingPathComponent(".zshrc")
        #expect(!(FileManager.default.fileExists(atPath: zshrc.path)))
        guard case .needsShellPathPrompt = result else {
            try #require(Bool(false), "Expected shell PATH prompt when no public bin dir is available")
            return
        }
        // Expected: rc edits require an explicit prompt now.
    }

    @Test("Ensure CLI Shim Creates Public Symlink When Writable")
    func ensureCLIShimCreatesPublicSymlinkWhenWritable() throws {
        let publicBin = tempHome.appendingPathComponent("public-bin", isDirectory: true)
        try FileManager.default.createDirectory(at: publicBin, withIntermediateDirectories: true)
        ShellEnvWriter.publicBinDirsOverrideForTests = [publicBin]
        ShellEnvWriter.pathOverrideForTests = "\(publicBin.path):/usr/bin"
        let appURL = try makeFakeAppURL()

        let result = try ShellEnvWriter.ensureCLIShim(appBundleURL: appURL)

        let publicCLI = publicBin.appendingPathComponent("omlx")
        #expect(FileManager.default.fileExists(atPath: publicCLI.path))
        let destination = try FileManager.default.destinationOfSymbolicLink(atPath: publicCLI.path)
        #expect(destination.hasSuffix("/.omlx/bin/omlx"))
        #expect(result == .publicCommandReady(path: publicCLI.path))
        #expect(!(FileManager.default.fileExists(atPath: tempHome.appendingPathComponent(".zshrc").path)))
    }

    @Test("Ensure CLI Shim Does Not Overwrite Existing Public Command")
    func ensureCLIShimDoesNotOverwriteExistingPublicCommand() throws {
        let publicBin = tempHome.appendingPathComponent("public-bin", isDirectory: true)
        try FileManager.default.createDirectory(at: publicBin, withIntermediateDirectories: true)
        ShellEnvWriter.publicBinDirsOverrideForTests = [publicBin]
        ShellEnvWriter.pathOverrideForTests = "\(publicBin.path):/usr/bin"
        let existing = publicBin.appendingPathComponent("omlx")
        try "#!/bin/sh\n".write(to: existing, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: existing.path)

        let result = try ShellEnvWriter.ensureCLIShim(appBundleURL: try makeFakeAppURL())

        let text = try String(contentsOf: existing, encoding: .utf8)
        #expect(text == "#!/bin/sh\n")
        guard case .needsShellPathPrompt(let reason) = result else {
            try #require(Bool(false), "Expected shell PATH prompt when public command conflicts")
            return
        }
        #expect(reason.contains("already exists"))
    }

    @Test("Explicit Shell Path Export Is Idempotent")
    func explicitShellPathExportIsIdempotent() throws {
        try ShellEnvWriter.ensureShellPathExport()
        try ShellEnvWriter.ensureShellPathExport()

        let zshrc = tempHome.appendingPathComponent(".zshrc")
        let rcText = try String(contentsOf: zshrc, encoding: .utf8)
        #expect(rcText.contains("# oMLX: CLI shim path begin"))
        #expect(rcText.contains("$HOME/.omlx/bin"))
        let count = rcText.components(separatedBy: "# oMLX: CLI shim path begin").count - 1
        #expect(count == 1)
    }

    @Test("Shim Exports Bootstrap Base Path")
    func shimExportsBootstrapBasePath() throws {
        let appURL = try makeFakeAppURL()
        let output = tempHome.appendingPathComponent("base-path-output.txt")
        let cli = appURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("MacOS", isDirectory: true)
            .appendingPathComponent("omlx-cli")
        try """
        #!/bin/sh
        printf "%s" "$OMLX_BASE_PATH" > \(shellQuote(output.path))
        """.write(to: cli, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cli.path)

        try ShellEnvWriter.ensureCLIShim(appBundleURL: appURL)

        let support = tempHome
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("oMLX", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try "/tmp/custom-omlx\n".write(
            to: support.appendingPathComponent("base-path"),
            atomically: true,
            encoding: .utf8
        )

        let shim = tempHome
            .appendingPathComponent(".omlx", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("omlx")
        let process = Process()
        process.executableURL = shim
        process.environment = [
            "HOME": tempHome.path,
            "PATH": "/usr/bin:/bin",
        ]
        try process.run()
        process.waitUntilExit()

        #expect(process.terminationStatus == 0)
        #expect(try String(contentsOf: output, encoding: .utf8) == "/tmp/custom-omlx")
    }

    @Test("Dismiss Forever Preference Round Trips")
    func dismissForeverPreferenceRoundTrips() throws {
        #expect(!(ShellEnvWriter.shouldSuppressCLIPathPrompt()))

        ShellEnvWriter.suppressCLIPathPromptForever()

        #expect(ShellEnvWriter.shouldSuppressCLIPathPrompt())
    }

    private func makeFakeAppURL() throws -> URL {
        let appURL = tempHome
            .appendingPathComponent("Apps", isDirectory: true)
            .appendingPathComponent("oMLX.app", isDirectory: true)
        let cli = appURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("MacOS", isDirectory: true)
            .appendingPathComponent("omlx-cli")
        try FileManager.default.createDirectory(
            at: cli.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "#!/bin/sh\n".write(to: cli, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: cli.path
        )
        return appURL
    }

    private func shellQuote(_ value: String) -> String {
        if value.isEmpty { return "''" }
        return "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }
}
