import SwiftUI

@MainActor
final class NetworkScreenVM: ObservableObject {
    // Editable drafts
    @Published var httpProxy: String = ""
    @Published var httpsProxy: String = ""
    @Published var noProxy: String = ""
    @Published var caBundle: String = ""

    // Last-loaded values. Drives the Apply button's enabled state.
    @Published private(set) var loadedHttpProxy: String = ""
    @Published private(set) var loadedHttpsProxy: String = ""
    @Published private(set) var loadedNoProxy: String = ""
    @Published private(set) var loadedCaBundle: String = ""

    @Published private(set) var isSaving: Bool = false
    @Published var lastError: String?

    /// Trimmed draft != loaded for at least one field. Whitespace-only edits
    /// don't count as changes.
    var hasPendingChanges: Bool {
        trim(httpProxy)  != loadedHttpProxy
        || trim(httpsProxy) != loadedHttpsProxy
        || trim(noProxy)    != loadedNoProxy
        || trim(caBundle)   != loadedCaBundle
    }

    func load(client: OMLXClient) async {
        do {
            let settings = try await client.getGlobalSettings()
            if let net = settings.network {
                self.httpProxy = net.httpProxy
                self.httpsProxy = net.httpsProxy
                self.noProxy = net.noProxy
                self.caBundle = net.caBundle
                self.loadedHttpProxy  = net.httpProxy
                self.loadedHttpsProxy = net.httpsProxy
                self.loadedNoProxy    = net.noProxy
                self.loadedCaBundle   = net.caBundle
            }
            self.lastError = nil
        } catch {
            self.lastError = error.omlxDescription
        }
    }

    func save(client: OMLXClient) async {
        // Only send fields the user actually changed so we don't clobber
        // values set out-of-band (e.g. CLI or another admin client).
        var patch = GlobalSettingsPatch()
        var touched: [String] = []
        if trim(httpProxy) != loadedHttpProxy {
            patch.networkHttpProxy = trim(httpProxy)
            touched.append("http_proxy")
        }
        if trim(httpsProxy) != loadedHttpsProxy {
            patch.networkHttpsProxy = trim(httpsProxy)
            touched.append("https_proxy")
        }
        if trim(noProxy) != loadedNoProxy {
            patch.networkNoProxy = trim(noProxy)
            touched.append("no_proxy")
        }
        if trim(caBundle) != loadedCaBundle {
            patch.networkCaBundle = trim(caBundle)
            touched.append("ca_bundle")
        }
        guard !touched.isEmpty else { return }

        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await client.updateGlobalSettings(patch)
            // Converge loaded baselines on success.
            self.loadedHttpProxy  = trim(httpProxy)
            self.loadedHttpsProxy = trim(httpsProxy)
            self.loadedNoProxy    = trim(noProxy)
            self.loadedCaBundle   = trim(caBundle)
            self.lastError = nil
        } catch {
            self.lastError = error.omlxDescription
        }
    }

    private func trim(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespaces)
    }

}
