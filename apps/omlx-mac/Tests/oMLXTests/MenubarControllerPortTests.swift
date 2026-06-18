// Regression coverage for the menubar-shows-stale-port bug.
//
// Before the fix, MenubarController captured `config: AppConfig` by value
// at init and rendered `config.port` in the running-status header / port
// alert / Chat URL. The user-facing flow:
//   1. ServerScreen's Apply commits a new port via
//      `AppServices.applyServerEndpoint(port:)`.
//   2. AppServices calls `server.reconfigure(port:)` and restarts the
//      ServerProcess on the new port.
//   3. The server transitions to `.running(newPid)`; the menubar's
//      stateDidChange observer fires `refreshMenuState()`.
//   4. `refreshMenuState()` rebuilds the header — and read the OLD port
//      from the stale `config` snapshot. The user saw `:8080` after
//      changing to `:8964`.
//
// Fix: `MenubarController.displayPort(server:fallback:)` sources from
// the live server (which `reconfigure(port:)` updates), falling back to
// the captured config snapshot only when there is no server (bootstrap
// failed). These tests exercise the helper directly — instantiating the
// full controller in a unit test would require a live `NSStatusBar`.

import Foundation
import Testing
@testable import oMLX

@MainActor
struct MenubarControllerPortTests {

    /// Test-only PythonRuntime. ServerProcess holds it but doesn't
    /// dereference until `start()` — these tests never start, they just
    /// read `.port` / `.host` after `reconfigure`.
    private func makeRuntime() -> PythonRuntime {
        PythonRuntime(
            executable: URL(fileURLWithPath: "/usr/bin/true"),
            homebrewPaths: [],
            pythonPath: [],
            pythonHome: nil,
            isBundled: false
        )
    }

    @Test("Spawn Environment Advertises Menubar Supervisor")
    func spawnEnvironmentAdvertisesMenubarSupervisor() {
        let env = makeRuntime().makeEnvironment()
        #expect(env["OMLX_SUPERVISED"] == "menubar")
    }

    // MARK: - displayPort

    @Test("Display Port Falls Back To Config When No Server")
    func displayPortFallsBackToConfigWhenNoServer() {
        #expect(MenubarController.displayPort(server: nil, fallback: 8080) == 8080, "With no server (bootstrap failed), the displayed port must come from the AppConfig snapshot.")
    }

    @Test("Display Port Prefers Live Server")
    func displayPortPrefersLiveServer() {
        let server = ServerProcess(runtime: makeRuntime(), port: 8888)
        #expect(MenubarController.displayPort(server: server, fallback: 8080) == 8888, "When a server is present, its `port` is authoritative — `fallback` is only for the no-server case.")
    }

    @Test("Display Port Follows Reconfigure")
    func displayPortFollowsReconfigure() throws {
        // The original bug: menubar's `config.port` snapshot never sees
        // this change, so the running-header text keeps showing 8080.
        let server = ServerProcess(runtime: makeRuntime(), port: 8080)
        try server.reconfigure(port: 8964)
        #expect(MenubarController.displayPort(server: server, fallback: 8080) == 8964, "After Server screen's Apply commits a new port (which calls server.reconfigure(port:)), the menubar must source from the live server.")
    }

    // MARK: - displayHost

    @Test("Display Host Falls Back To Config When No Server")
    func displayHostFallsBackToConfigWhenNoServer() {
        #expect(MenubarController.displayHost(server: nil, fallback: "127.0.0.1") == "127.0.0.1")
    }

    @Test("Display Host Prefers Live Server")
    func displayHostPrefersLiveServer() {
        let server = ServerProcess(runtime: makeRuntime(), bindAddress: "127.0.0.1", port: 8080)
        #expect(MenubarController.displayHost(server: server, fallback: "127.0.0.1") == "127.0.0.1")
    }

    @Test("Display Host Uses Server Connectable Host")
    func displayHostUsesServerConnectableHost() {
        let server = ServerProcess(runtime: makeRuntime(), bindAddress: "0.0.0.0", port: 8080)
        #expect(MenubarController.displayHost(server: server, fallback: "127.0.0.1") == "127.0.0.1", "ServerProcess.host returns the connectable host (0.0.0.0 → 127.0.0.1).")
    }

    @Test("Display Host Follows Reconfigure")
    func displayHostFollowsReconfigure() throws {
        let server = ServerProcess(runtime: makeRuntime(), bindAddress: "127.0.0.1", port: 8080)
        try server.reconfigure(bindAddress: "localhost")
        #expect(MenubarController.displayHost(server: server, fallback: "127.0.0.1") == "127.0.0.1", "Listen Address changes propagate through ServerProcess.host, which returns the connectable loopback host.")
    }

    @Test("Display Host Handles Comma Separated Bind Address")
    func displayHostHandlesCommaSeparatedBindAddress() throws {
        let server = ServerProcess(
            runtime: makeRuntime(),
            bindAddress: "0.0.0.0,127.0.0.1",
            port: 8080
        )
        #expect(MenubarController.displayHost(server: server, fallback: "127.0.0.1") == "127.0.0.1", "The menubar should use the first configured bind host and normalize wildcards before building URLs.")
    }

    // MARK: - webAdminURL
    //
    // The "Open Web Dashboard" menubar item routes through the server's
    // /admin/auto-login endpoint so the dashboard opens without the manual
    // login form. The action method itself needs a live NSStatusBar, so we
    // test the pure URL builder it delegates to.

    @Test("Web Admin URL Uses Auto Login With Redirect")
    func webAdminURLUsesAutoLoginWithRedirect() throws {
        let url = try #require(MenubarController.webAdminURL(host: "127.0.0.1", port: 8000, apiKey: "secret"))
        let comps = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(comps.scheme == "http")
        #expect(comps.host == "127.0.0.1")
        #expect(comps.port == 8000)
        #expect(comps.path == "/admin/auto-login")
        let items = comps.queryItems ?? []
        #expect(items.first { $0.name == "redirect" }?.value == "/admin/dashboard")
        #expect(items.first { $0.name == "key" }?.value == "secret")
    }

    @Test("Web Admin URL Builds IPv6 Host")
    func webAdminURLBuildsIPv6Host() throws {
        let url = try #require(MenubarController.webAdminURL(host: "[::1]", port: 8000, apiKey: nil))
        #expect(url.absoluteString.hasPrefix("http://[::1]:8000/admin/auto-login"))
    }

    @Test("Web Admin URL Percent Encodes Key")
    func webAdminURLPercentEncodesKey() throws {
        // A key with URL-reserved characters must survive intact — raw
        // string interpolation would corrupt it; URLComponents encodes it.
        let url = try #require(MenubarController.webAdminURL(host: "127.0.0.1", port: 8000, apiKey: "a+b/c&d"))
        // The decoded query item value round-trips to the original key.
        let comps = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(comps.queryItems?.first { $0.name == "key" }?.value == "a+b/c&d")
        // And the raw URL string carries the encoded form, not the literal.
        #expect(url.absoluteString.contains("key=a%2Bb/c%26d"), "key should be percent-encoded in the URL string, got \(url.absoluteString)")
    }

    @Test("Web Admin URL Omits Key When Missing")
    func webAdminURLOmitsKeyWhenMissing() throws {
        for key in [nil, ""] as [String?] {
            let url = try #require(MenubarController.webAdminURL(host: "127.0.0.1", port: 8000, apiKey: key))
            let comps = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
            #expect(comps.queryItems?.first { $0.name == "key" } == nil, "empty/nil key must not emit a key= param (server redirects to login instead)")
            #expect(comps.queryItems?.first { $0.name == "redirect" }?.value == "/admin/dashboard")
        }
    }

    // MARK: - menuAvailability

    @Test("Menu Availability Keeps Settings Enabled When Server Is Offline")
    func menuAvailabilityKeepsSettingsEnabledWhenServerIsOffline() {
        for state in [ServerProcess.State.stopped, .failed(message: "Port 8000 in use")] {
            let availability = MenubarController.menuAvailability(for: state)
            #expect(availability.settings)
            #expect(!(availability.webDashboard))
            #expect(!(availability.chat))
        }
    }

    @Test("Menu Availability Enables Browser Items Only When Running")
    func menuAvailabilityEnablesBrowserItemsOnlyWhenRunning() {
        let availability = MenubarController.menuAvailability(for: .running(pid: 123))
        #expect(availability.settings)
        #expect(availability.webDashboard)
        #expect(availability.chat)
    }

    @Test("Menu Availability Keeps Browser Items Disabled During Transitions")
    func menuAvailabilityKeepsBrowserItemsDisabledDuringTransitions() {
        let states: [ServerProcess.State] = [
            .starting,
            .stopping,
            .unresponsive(pid: 123),
        ]

        for state in states {
            let availability = MenubarController.menuAvailability(for: state)
            #expect(availability.settings)
            #expect(!(availability.webDashboard))
            #expect(!(availability.chat))
        }
    }

    // MARK: - failure alerts

    @Test("Generic Failure Alert Skips Port Conflict Messages")
    func genericFailureAlertSkipsPortConflictMessages() {
        #expect(!(MenubarController.shouldShowGenericFailureAlert(message: "Port 8000 in use")))
        #expect(MenubarController.shouldShowGenericFailureAlert(
                message: "Server exited with code 1 during startup"
            ))
    }

    @Test("Access Failure Hint Detects Permission Errors")
    func accessFailureHintDetectsPermissionErrors() {
        #expect(MenubarController.accessFailureHint(
                message: "Server exited with code 1 during startup",
                logTail: "PermissionError: [Errno 1] Operation not permitted"
            ) != nil)
        #expect(MenubarController.accessFailureHint(
                message: "Server exited with code 1 during startup",
                logTail: "ValueError: no models found"
            ) == nil)
    }
}
