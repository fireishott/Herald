import Foundation

/// Coordinates periodic sensor data uploads to the relay.
///
/// Location is sent whenever the location service provides an update.
/// Health snapshots are collected and sent every 5 minutes while active.
@MainActor
@Observable
final class SensorUploadService {
    private struct SensorLocationBody: Encodable {
        let latitude: Double
        let longitude: Double
        let altitude: Double?
        let accuracy: Double
        let address: String?
        let recordedAt: String
    }

    private struct SensorHealthBody: Encodable {
        struct Sample: Encodable {
            let metric: String
            let value: Double
            let unit: String
            let startAt: String
            let endAt: String?
        }

        let samples: [Sample]
    }

    private struct ForwardResult: Decodable {
        let forwarded: Bool
    }

    private let apiClient: RelayAPIClient
    private let accessTokenProvider: @MainActor () async -> String?
    private let locationService: LiveLocationService
    private let healthService: LiveHealthService

    private var healthTimer: Task<Void, Never>?
    private var isActive = false

    private let iso8601Formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    init(
        apiClient: RelayAPIClient,
        accessTokenProvider: @escaping @MainActor () async -> String?,
        locationService: LiveLocationService,
        healthService: LiveHealthService
    ) {
        self.apiClient = apiClient
        self.accessTokenProvider = accessTokenProvider
        self.locationService = locationService
        self.healthService = healthService
    }

    func start() {
        guard !isActive else { return }
        isActive = true

        // Wire location updates
        locationService.onLocationUpdate = { [weak self] update in
            guard let self else { return }
            Task { await self.uploadLocation(update) }
        }
        locationService.startMonitoring()
        locationService.requestSingleLocation()

        // Start health snapshot timer
        healthTimer = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                await self.collectAndUploadHealth()
                try? await Task.sleep(for: .seconds(300)) // 5 minutes
            }
        }
    }

    func stop() {
        isActive = false
        locationService.onLocationUpdate = nil
        locationService.stopMonitoring()
        healthTimer?.cancel()
        healthTimer = nil
    }

    // MARK: - Upload

    private func uploadLocation(_ update: LocationUpdate) async {
        let body = SensorLocationBody(
            latitude: update.latitude,
            longitude: update.longitude,
            altitude: update.altitude,
            accuracy: update.accuracy,
            address: nil,
            recordedAt: iso8601Formatter.string(from: update.timestamp)
        )

        do {
            let _: ForwardResult = try await apiClient.post(
                path: "device/sensor/location",
                body: body,
                accessToken: await accessTokenProvider()
            )
        } catch {
            // Sensor uploads are best-effort — next update will retry
        }
    }

    private func collectAndUploadHealth() async {
        guard let snapshot = await healthService.collectSnapshot() else { return }

        let samples = snapshot.samples.map { sample in
            SensorHealthBody.Sample(
                metric: sample.metric,
                value: sample.value,
                unit: sample.unit,
                startAt: iso8601Formatter.string(from: sample.startAt),
                endAt: sample.endAt.map { iso8601Formatter.string(from: $0) }
            )
        }

        guard !samples.isEmpty else { return }

        do {
            let _: ForwardResult = try await apiClient.post(
                path: "device/sensor/health",
                body: SensorHealthBody(samples: samples),
                accessToken: await accessTokenProvider()
            )
        } catch {
            // Best-effort — will retry on next cycle
        }
    }
}
