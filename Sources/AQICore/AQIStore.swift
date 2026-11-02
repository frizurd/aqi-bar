import Foundation
import Combine

@MainActor
public final class AQIStore: ObservableObject {
    @Published public private(set) var selection: LocationSelection
    @Published public private(set) var reading: AQIReading?
    @Published public private(set) var isRefreshing = false
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var lastAttempt: Date?

    private let provider: AQIProviding
    private let defaults: UserDefaults
    private let key: () -> String
    private let retryDelays: [UInt64]
    private var task: Task<Void, Never>?
    private var generation = UUID()

    public init(provider: AQIProviding = IQAirClient(), defaults: UserDefaults = .standard,
                retryDelays: [UInt64] = [10, 20, 40], key: @escaping () -> String) {
        self.provider = provider
        self.defaults = defaults
        self.key = key
        self.retryDelays = retryDelays
        selection = defaults.data(forKey: "location").flatMap {
            try? JSONDecoder().decode(LocationSelection.self, from: $0)
        } ?? .automatic
        if let data = defaults.data(forKey: "reading"),
           let cache = try? JSONDecoder().decode(CachedReading.self, from: data),
           cache.selection == selection {
            reading = cache.reading
        }
    }

    public var isStale: Bool {
        reading != nil && (errorMessage != nil || reading?.isOld(at: Date()) == true)
    }

    public func select(_ location: LocationSelection) {
        guard location != selection else { refresh(); return }
        selection = location
        defaults.set(try? JSONEncoder().encode(location), forKey: "location")
        // Never show a different city's cached value after changing location.
        reading = nil
        defaults.removeObject(forKey: "reading")
        refresh()
    }

    public func refresh() {
        task?.cancel()
        let requestID = UUID()
        generation = requestID
        let requestedLocation = selection
        let apiKey = key()
        isRefreshing = true
        errorMessage = nil
        lastAttempt = Date()
        task = Task { [weak self] in
            guard let self else { return }
            for attempt in 0...retryDelays.count {
                do {
                    let fresh = try await provider.fetch(selection: requestedLocation, key: apiKey)
                    guard !Task.isCancelled, generation == requestID else { return }
                    reading = fresh
                    errorMessage = nil
                    defaults.set(try? JSONEncoder().encode(CachedReading(selection: requestedLocation, reading: fresh)),
                                 forKey: "reading")
                    isRefreshing = false
                    return
                } catch {
                    guard !Task.isCancelled, generation == requestID else { return }
                    // Avoid exposing URLSession errors, whose URLs may include the API key.
                    errorMessage = (error as? AQIError)?.errorDescription ?? "Couldn’t connect to IQAir. Check your internet connection."
                    let shouldRetry: Bool
                    if let apiError = error as? AQIError {
                        if case .http(let status) = apiError { shouldRetry = status >= 500 }
                        else { shouldRetry = false }
                    } else { shouldRetry = error is URLError }
                    guard shouldRetry, attempt < retryDelays.count else { break }
                    do { try await Task.sleep(nanoseconds: retryDelays[attempt] * 1_000_000_000) }
                    catch { return }
                }
            }
            isRefreshing = false
        }
    }

    public func waitForRefresh() async { await task?.value }
    public func cancel() { task?.cancel(); task = nil; generation = UUID(); isRefreshing = false }
}
