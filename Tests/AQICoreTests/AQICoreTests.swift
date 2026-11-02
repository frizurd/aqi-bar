import XCTest
@testable import AQICore

final class AQICoreTests: XCTestCase {
    private func payload(_ value: String = "160", status: String = "success") -> Data {
        Data("""
        {"status":"\(status)","data":{"city":"Jakarta","country":"Indonesia","current":{"pollution":{"ts":"2026-11-02T08:00:00.000Z","aqius":\(value)}}}}
        """.utf8)
    }

    func testAllCategoryBoundariesMatchSketchyBar() {
        let cases: [(Int, AQIBand)] = [
            (0, .good), (50, .good), (51, .moderate), (100, .moderate),
            (101, .sensitive), (150, .sensitive), (151, .unhealthy), (200, .unhealthy),
            (201, .veryUnhealthy), (300, .veryUnhealthy), (301, .hazardous), (999, .hazardous)
        ]
        for (value, band) in cases { XCTAssertEqual(AQIBand(value: value), band) }
        XCTAssertEqual(AQIBand.allCases.map(\.rgb), [0xa6da95, 0xeed49f, 0xf5a97f, 0xed8796, 0xc6a0f6, 0xff6685])
    }

    func testParsesRealAPIShapeAndTimestamp() throws {
        let now = Date()
        let reading = try IQAirClient.parse(payload("160.6"), now: now)
        XCTAssertEqual(reading.value, 161)
        XCTAssertEqual(reading.place, "Jakarta, Indonesia")
        XCTAssertEqual(reading.band, .unhealthy)
        XCTAssertNotNil(reading.observedAt)
        XCTAssertEqual(reading.fetchedAt, now)
        XCTAssertEqual(try IQAirClient.parse(payload("0")).value, 0)
    }

    func testRejectsMissingNegativeBooleanAndNonNumericAQI() {
        for value in ["null", "-1", "true", "\"160\"", "1e100"] {
            XCTAssertThrowsError(try IQAirClient.parse(payload(value)), value)
        }
        XCTAssertThrowsError(try IQAirClient.parse(Data("{}".utf8)))
    }

    func testClassifiesAPIKeyAndQuotaFailures() {
        for (message, expected) in [("incorrect_api_key", AQIError.invalidKey), ("call_limit_reached", .rateLimited), ("city_not_found", .unavailable)] {
            let data = Data("{\"status\":\"fail\",\"data\":{\"message\":\"\(message)\"}}".utf8)
            XCTAssertThrowsError(try IQAirClient.parse(data)) { XCTAssertEqual($0 as? AQIError, expected) }
        }
    }

    func testCoordinatesAndKeyAreEncodedInHTTPSRequest() throws {
        let location = SavedLocation(name: "Jakarta", latitude: -6.2, longitude: 106.8)
        let request = try IQAirClient.request(selection: .fixed(location), key: " test+key&value \n")
        let url = try XCTUnwrap(request.url)
        XCTAssertEqual(url.scheme, "https")
        let query = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(query.first { $0.name == "lat" }?.value, "-6.2")
        XCTAssertEqual(query.first { $0.name == "lon" }?.value, "106.8")
        XCTAssertEqual(query.first { $0.name == "key" }?.value, "test+key&value")
        let automatic = try IQAirClient.request(selection: .automatic, key: "key")
        XCTAssertFalse(automatic.url!.absoluteString.contains("lat="))
        XCTAssertThrowsError(try IQAirClient.request(selection: .automatic, key: "  "))
        XCTAssertThrowsError(try IQAirClient.request(selection: .fixed(.init(name: "bad", latitude: 91, longitude: 0)), key: "key"))
    }

    func testHTTPFailureDoesNotGetParsedAsAReading() async throws {
        let client = IQAirClient { request in
            (self.payload(), HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: nil)!)
        }
        do {
            _ = try await client.fetch(selection: .automatic, key: "test")
            XCTFail("Expected rate limit failure")
        } catch { XCTAssertEqual(error as? AQIError, .rateLimited) }
    }

    func testStaleObservationAndFetchAgeAreIndependent() {
        let now = Date()
        let oldObservation = AQIReading(value: 99, city: "A", country: "B", observedAt: now.addingTimeInterval(-10_801), fetchedAt: now)
        XCTAssertTrue(oldObservation.isOld(at: now))
        let oldFetch = AQIReading(value: 99, city: "A", country: "B", observedAt: nil, fetchedAt: now.addingTimeInterval(-1_801))
        XCTAssertTrue(oldFetch.isOld(at: now))
        let fresh = AQIReading(value: 99, city: "A", country: "B", observedAt: now, fetchedAt: now)
        XCTAssertFalse(fresh.isOld(at: now))
    }
}

@MainActor
final class AQIStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() async throws {
        suite = "AQIBar.tests.\(UUID())"
        defaults = UserDefaults(suiteName: suite)!
    }

    override func tearDown() async throws { defaults.removePersistentDomain(forName: suite) }

    func testFailedRefreshKeepsLastReadingAndRestartRestoresIt() async throws {
        let provider = StubProvider()
        let store = AQIStore(provider: provider, defaults: defaults, retryDelays: [], key: { "test" })
        store.refresh()
        await store.waitForRefresh()
        XCTAssertEqual(store.reading?.value, 160)
        XCTAssertFalse(store.isStale)
        provider.shouldFail = true
        store.refresh()
        await store.waitForRefresh()
        XCTAssertEqual(store.reading?.value, 160)
        XCTAssertTrue(store.isStale)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertFalse(store.isRefreshing)
        let restored = AQIStore(provider: provider, defaults: defaults, key: { "test" })
        XCTAssertEqual(restored.reading?.city, "Jakarta")
    }

    func testSwitchingCitiesClearsPreviousReadingEvenIfNewCityFails() async {
        let provider = StubProvider()
        let store = AQIStore(provider: provider, defaults: defaults, retryDelays: [], key: { "test" })
        store.refresh()
        await store.waitForRefresh()
        provider.shouldFail = true
        let selection = LocationSelection.fixed(.init(name: "Tokyo", latitude: 35.7, longitude: 139.7))
        store.select(selection)
        XCTAssertNil(store.reading)
        await store.waitForRefresh()
        XCTAssertNil(store.reading)
        let restored = AQIStore(provider: provider, defaults: defaults, key: { "test" })
        XCTAssertEqual(restored.selection, selection)
        XCTAssertNil(restored.reading)
    }

    func testCancelledOldRequestCannotOverwriteNewCity() async {
        let provider = DelayedProvider()
        let store = AQIStore(provider: provider, defaults: defaults, retryDelays: [], key: { "test" })
        store.refresh()
        await Task.yield()
        store.select(.fixed(.init(name: "Tokyo", latitude: 35.7, longitude: 139.7)))
        await store.waitForRefresh()
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(store.reading?.city, "Tokyo")
    }

    func testRetriesNetworkErrorsButDoesNotRetryInvalidKeys() async {
        let provider = StubProvider()
        provider.shouldFail = true
        let store = AQIStore(provider: provider, defaults: defaults, retryDelays: [0, 0], key: { "test" })
        store.refresh()
        await store.waitForRefresh()
        XCTAssertEqual(provider.calls, 3)
        provider.calls = 0
        provider.failure = AQIError.invalidKey
        store.refresh()
        await store.waitForRefresh()
        XCTAssertEqual(provider.calls, 1)
    }

    func testErrorsNeverShowRequestURLOrAPIKey() async {
        let provider = StubProvider()
        provider.shouldFail = true
        provider.failure = NSError(domain: NSURLErrorDomain, code: -1009,
                                   userInfo: [NSLocalizedDescriptionKey: "failed https://api.airvisual.com?key=secret"])
        let store = AQIStore(provider: provider, defaults: defaults, retryDelays: [], key: { "secret" })
        store.refresh()
        await store.waitForRefresh()
        XCTAssertFalse(store.errorMessage?.contains("secret") ?? true)
    }
}

private final class StubProvider: AQIProviding {
    var shouldFail = false
    var failure: Error = URLError(.notConnectedToInternet)
    var calls = 0
    func fetch(selection: LocationSelection, key: String) async throws -> AQIReading {
        calls += 1
        if shouldFail { throw failure }
        return AQIReading(value: 160, city: "Jakarta", country: "Indonesia", observedAt: Date(), fetchedAt: Date())
    }
}

private struct DelayedProvider: AQIProviding {
    func fetch(selection: LocationSelection, key: String) async throws -> AQIReading {
        let city: String
        if case .fixed = selection { city = "Tokyo" }
        else {
            // Deliberately ignore cancellation to emulate a late external response.
            await withCheckedContinuation { continuation in
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) { continuation.resume() }
            }
            city = "Jakarta"
        }
        return AQIReading(value: 100, city: city, country: "", observedAt: Date(), fetchedAt: Date())
    }
}
