import HealthKit

struct HealthSnapshot: Sendable {
    struct Sample: Sendable {
        let metric: String
        let value: Double
        let unit: String
        let startAt: Date
        let endAt: Date?
    }

    let samples: [Sample]
    let collectedAt: Date
}

@MainActor
@Observable
final class LiveHealthService: HealthServiceProtocol {
    private(set) var authorizationStatus: PermissionStatus

    private let store: HKHealthStore?
    private let readTypes: Set<HKObjectType>

    init() {
        guard HKHealthStore.isHealthDataAvailable() else {
            self.store = nil
            self.readTypes = []
            self.authorizationStatus = .unsupported
            return
        }

        let store = HKHealthStore()
        self.store = store
        var types = Set<HKObjectType>()
        if let steps = HKQuantityType.quantityType(forIdentifier: .stepCount) { types.insert(steps) }
        if let hr = HKQuantityType.quantityType(forIdentifier: .heartRate) { types.insert(hr) }
        if let cal = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) { types.insert(cal) }
        if let dist = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning) { types.insert(dist) }
        if let sleep = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) { types.insert(sleep) }
        self.readTypes = types
        self.authorizationStatus = .notDetermined
    }

    func requestAuthorization() async -> PermissionStatus {
        guard let store else {
            authorizationStatus = .unsupported
            return .unsupported
        }

        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            authorizationStatus = .limited
        } catch {
            authorizationStatus = .denied
        }

        return authorizationStatus
    }

    func collectSnapshot() async -> HealthSnapshot? {
        guard let store else { return nil }

        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        var samples: [HealthSnapshot.Sample] = []

        // Steps today
        if let value = await queryCumulativeSum(.stepCount, unit: .count(), from: startOfDay, to: now) {
            samples.append(.init(metric: "steps", value: value, unit: "count", startAt: startOfDay, endAt: now))
        }

        // Active calories today
        if let value = await queryCumulativeSum(.activeEnergyBurned, unit: .kilocalorie(), from: startOfDay, to: now) {
            samples.append(.init(metric: "active_calories", value: value, unit: "kcal", startAt: startOfDay, endAt: now))
        }

        // Walking/running distance today
        if let value = await queryCumulativeSum(.distanceWalkingRunning, unit: .meter(), from: startOfDay, to: now) {
            samples.append(.init(metric: "distance_walking", value: value, unit: "meters", startAt: startOfDay, endAt: now))
        }

        // Latest heart rate
        if let (value, date) = await queryLatestSample(.heartRate, unit: .count().unitDivided(by: .minute())) {
            samples.append(.init(metric: "heart_rate", value: value, unit: "bpm", startAt: date, endAt: nil))
        }

        guard !samples.isEmpty else { return nil }
        return HealthSnapshot(samples: samples, collectedAt: now)
    }

    // MARK: - HealthKit Queries

    private func queryCumulativeSum(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        from startDate: Date,
        to endDate: Date
    ) async -> Double? {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, result, _ in
                let value = result?.sumQuantity()?.doubleValue(for: unit)
                continuation.resume(returning: value)
            }
            store?.execute(query)
        }
    }

    private func queryLatestSample(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit
    ) async -> (Double, Date)? {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: quantityType,
                predicate: nil,
                limit: 1,
                sortDescriptors: [sort]
            ) { _, results, _ in
                guard let sample = results?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }
                let value = sample.quantity.doubleValue(for: unit)
                continuation.resume(returning: (value, sample.startDate))
            }
            store?.execute(query)
        }
    }
}
