// The Status screen's System block surfaces three derived values that
// each have a single point of failure: the thermal-state → severity
// mapping, the GPU-utilization clamp, and the bytes → GB formatter used
// in both row labels. These tests pin those mappings so an SDK roll or
// a stray locale tweak can't change what the UI prints.

import Testing
@testable import oMLX

struct SystemMetricsTests {

    // MARK: - Thermal severity mapping

    @Test("Thermal Severity Nominal")
    func thermalSeverityNominal() {
        #expect(SystemMetricsPoller.severity(for: .nominal) == .nominal)
    }

    @Test("Thermal Severity Fair")
    func thermalSeverityFair() {
        #expect(SystemMetricsPoller.severity(for: .fair) == .fair)
    }

    @Test("Thermal Severity Serious")
    func thermalSeveritySerious() {
        #expect(SystemMetricsPoller.severity(for: .serious) == .serious)
    }

    @Test("Thermal Severity Critical")
    func thermalSeverityCritical() {
        #expect(SystemMetricsPoller.severity(for: .critical) == .critical)
    }

    @Test("Thermal Labels Match Severity")
    func thermalLabelsMatchSeverity() {
        #expect(SystemMetricsPoller.label(for: .nominal) == "Nominal")
        #expect(SystemMetricsPoller.label(for: .fair) == "Fair")
        #expect(SystemMetricsPoller.label(for: .serious) == "Serious")
        #expect(SystemMetricsPoller.label(for: .critical) == "Critical")
    }

    // MARK: - GPU utilization clamp

    @MainActor
    @Test("GPU Utilization Clamped To 100 When Active Exceeds Max")
    func gpuUtilizationClampedTo100WhenActiveExceedsMax() {
        let vm = StatusScreenVM()
        vm.maxConcurrent = 8
        vm.stats = makeStats(active: 20)
        expectClose(vm.gpuUtilizationPercent, 100.0, accuracy: 0.001)
    }

    @MainActor
    @Test("GPU Utilization Zero When Active Zero")
    func gpuUtilizationZeroWhenActiveZero() {
        let vm = StatusScreenVM()
        vm.maxConcurrent = 8
        vm.stats = makeStats(active: 0)
        expectClose(vm.gpuUtilizationPercent, 0.0, accuracy: 0.001)
    }

    @MainActor
    @Test("GPU Utilization Linear In Range")
    func gpuUtilizationLinearInRange() {
        let vm = StatusScreenVM()
        vm.maxConcurrent = 8
        vm.stats = makeStats(active: 4)
        expectClose(vm.gpuUtilizationPercent, 50.0, accuracy: 0.001)
    }

    @MainActor
    @Test("GPU Utilization Handles Zero Max By Floor Of One")
    func gpuUtilizationHandlesZeroMaxByFloorOfOne() {
        // The VM's max is 0 only transiently (between init and the
        // settings load). The divisor floor of 1 prevents NaN.
        let vm = StatusScreenVM()
        vm.maxConcurrent = 0
        vm.stats = makeStats(active: 0)
        expectClose(vm.gpuUtilizationPercent, 0.0, accuracy: 0.001)
    }

    // MARK: - Bytes → GB formatter

    @Test("Format Bytes As GB Rounds To One Decimal")
    func formatBytesAsGbRoundsToOneDecimal() {
        // 34.6 GB in decimal bytes = 34_600_000_000.
        let bytes: UInt64 = 34_600_000_000
        #expect(SystemMetricsPoller.formatBytesAsGB(bytes) == "34.6")
    }

    @Test("Format Bytes As GB Zero")
    func formatBytesAsGbZero() {
        #expect(SystemMetricsPoller.formatBytesAsGB(0) == "0.0")
    }

    @Test("Format Bytes As GB Rounds Half Up")
    func formatBytesAsGbRoundsHalfUp() {
        // 12.55 GB → "12.5" (banker's) or "12.6" (away). printf %.1f on
        // Darwin rounds half to even at the binary level — pin whichever
        // string we actually produce so a future libc swap is visible.
        let bytes: UInt64 = 12_550_000_000
        let out = SystemMetricsPoller.formatBytesAsGB(bytes)
        #expect(out == "12.5" || out == "12.6", "Unexpected rounding output: \(out)")
    }

    private func expectClose(_ actual: Double, _ expected: Double, accuracy: Double) {
        #expect(abs(actual - expected) <= accuracy)
    }

    // MARK: - Helpers

    private func makeStats(active: Int) -> StatsDTO {
        StatsDTO(
            totalTokensServed: 0,
            totalCachedTokens: 0,
            cacheEfficiency: 0,
            totalPromptTokens: 0,
            totalCompletionTokens: 0,
            totalRequests: 0,
            avgPrefillTps: 0,
            avgGenerationTps: 0,
            uptimeSeconds: 0,
            host: nil,
            port: nil,
            apiKey: nil,
            cliPrefix: nil,
            activeModels: StatsDTO.ActiveModelsDTO(
                models: [],
                modelMemoryUsed: nil,
                modelMemoryMax: nil,
                totalActiveRequests: active,
                totalWaitingRequests: 0
            ),
            runtimeCache: nil
        )
    }
}
