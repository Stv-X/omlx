import SwiftUI

@MainActor
final class LogsScreenVM: ObservableObject {
    @Published var lines: Int = 100
    @Published var selectedFile: String = ""
    @Published var logText: String = ""
    @Published var availableFiles: [String] = []
    @Published var lastError: String?
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var totalLines: Int = 0
    @Published private(set) var refreshKey: Int = 0

    private weak var client: OMLXClient?
    private var pollTask: Task<Void, Never>?

    var subtitle: String {
        guard !logText.isEmpty else { return "" }
        return String(localized: "logs.subtitle.line_count",
                      defaultValue: "\(totalLines) lines",
                      comment: "Section header subtitle on the Logs screen; placeholder is the total number of log lines")
    }

    var fileOptions: [(String, String)] {
        availableFiles.map { name in
            let label = name == "server.log"
                ? String(localized: "logs.file.current",
                         defaultValue: "server.log (current)",
                         comment: "Popup label for the active server log file in the Logs screen file selector")
                : name
            return (name, label)
        }
    }

    func start(client: OMLXClient) async {
        self.client = client
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.tick()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    func reload() async {
        await tick()
    }

    func bumpRefreshKey() {
        refreshKey &+= 1
    }

    func copyToPasteboard() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(logText, forType: .string)
    }

    private func tick() async {
        guard let client else { return }
        isLoading = true
        defer { isLoading = false }

        let file = selectedFile.isEmpty ? nil : selectedFile
        do {
            let dto = try await client.getLogs(lines: lines, file: file)
            self.logText = dto.logs
            self.totalLines = dto.totalLines
            self.availableFiles = dto.availableFiles
            if selectedFile.isEmpty {
                self.selectedFile = dto.logFile
            }
            self.lastError = nil
        } catch {
            self.lastError = error.omlxDescription
        }
    }

}
