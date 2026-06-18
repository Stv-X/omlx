// WelcomeViewModel drives the first-run wizard. The interesting behaviors
// are validation gates (storage + api-key) feeding `lastError`, the
// intro → setup → complete state, and the Start Server validation path.

import Testing
@testable import oMLX

@MainActor
final class WelcomeViewModelTests {

    // AppServices uses a weak reference to its services on WelcomeViewModel,
    // so the test must keep a strong reference for the lifetime of each case.
    private var services: AppServices!

    private func makeVM(basePath: String = "/Users/Fido/.omlx",
                        modelDir: String  = "/Users/Fido/.omlx/models",
                        port: Int = 8000,
                        apiKey: String? = nil) -> WelcomeViewModel {
        let cfg = AppConfig(
            bindAddress: "127.0.0.1",
            port: port,
            apiKey: apiKey,
            basePath: basePath,
            modelDir: modelDir,
            hfEndpoint: ""
        )
        services = AppServices(config: cfg, server: nil)
        return WelcomeViewModel(services: services, server: nil)
    }

    // MARK: - flow

    @Test("Starts On Intro Step")
    func startsOnIntroStep() {
        let vm = makeVM()
        #expect(vm.step == .intro)
    }

    @Test("Begin Setup Advances To Setup And Clears Error")
    func beginSetupAdvancesToSetupAndClearsError() {
        let vm = makeVM()
        vm.apiKey = "abc"
        #expect(!(vm.validateApiKey()))
        #expect(vm.lastError != nil)
        vm.beginSetup()
        #expect(vm.step == .setup)
        #expect(vm.lastError == nil)
    }

    @Test("Default Port Is 8000")
    func defaultPortIs8000() {
        let vm = makeVM()
        #expect(vm.portText == "8000")
    }

    // MARK: - validateSetup

    @Test("Validate Setup Happy Path")
    func validateSetupHappyPath() {
        let vm = makeVM()
        vm.apiKey = "secret-key"
        #expect(vm.validateSetup())
        #expect(vm.lastError == nil)
    }

    @Test("Validate Setup Fails On Empty Base")
    func validateSetupFailsOnEmptyBase() {
        let vm = makeVM()
        vm.basePath = "   "
        vm.apiKey = "secret-key"
        #expect(!(vm.validateSetup()))
        #expect(vm.lastError == "Base directory is required.")
    }

    @Test("Validate Setup Fails On Invalid Port")
    func validateSetupFailsOnInvalidPort() {
        let vm = makeVM()
        vm.apiKey = "secret-key"
        vm.portText = "0"
        #expect(!(vm.validateSetup()))
        #expect(vm.lastError == "Port must be a number between 1 and 65535.")
    }

    @Test("Validate Setup Fails On Port Non Numeric")
    func validateSetupFailsOnPortNonNumeric() {
        let vm = makeVM()
        vm.apiKey = "secret-key"
        vm.portText = "abc"
        #expect(!(vm.validateSetup()))
        #expect(vm.lastError == "Port must be a number between 1 and 65535.")
    }

    @Test("Validate Setup Fails On Short API Key")
    func validateSetupFailsOnShortApiKey() {
        let vm = makeVM()
        vm.apiKey = "abc"
        #expect(!(vm.validateSetup()))
        #expect(vm.lastError == "API key must be at least 4 characters.")
    }

    @Test("Validate Setup Fails On API Key Whitespace")
    func validateSetupFailsOnApiKeyWhitespace() {
        let vm = makeVM()
        // 4+ chars but a space inside — server-side validator rejects.
        vm.apiKey = "ab cd"
        #expect(!(vm.validateSetup()))
        #expect(vm.lastError == "API key must not contain whitespace.")
    }

    @Test("Validate Setup Fails On API Key Non Printable")
    func validateSetupFailsOnApiKeyNonPrintable() {
        let vm = makeVM()
        vm.apiKey = "abcd\u{007F}"   // DEL char, outside printable ASCII
        #expect(!(vm.validateSetup()))
        #expect(vm.lastError == "API key must contain only printable ASCII.")
    }
}
