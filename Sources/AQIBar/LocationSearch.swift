import AQICore
import MapKit
import Combine

@MainActor
final class LocationSearch: ObservableObject {
    @Published var query = ""
    @Published private(set) var results: [SavedLocation] = []
    @Published private(set) var isSearching = false
    @Published private(set) var error: String?
    private var task: Task<Void, Never>?
    private var search: MKLocalSearch?
    private var generation = UUID()

    init(demoQuery: String = "", demoResults: [SavedLocation] = []) {
        query = demoQuery
        results = demoResults
    }

    func find() {
        let input = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }
        task?.cancel()
        search?.cancel()
        let requestID = UUID()
        generation = requestID
        results = []
        error = nil
        isSearching = true
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = input
        request.resultTypes = .address
        let search = MKLocalSearch(request: request)
        self.search = search
        task = Task {
            do {
                let response = try await search.start()
                guard !Task.isCancelled, generation == requestID else { return }
                var seen = Set<String>()
                results = response.mapItems.compactMap { item in
                    let placemark = item.placemark
                    let parts = [item.name, placemark.administrativeArea, placemark.country].compactMap { $0 }
                    var unique = [String]()
                    for part in parts where !unique.contains(part) { unique.append(part) }
                    let location = SavedLocation(name: unique.joined(separator: ", "),
                                                 latitude: placemark.coordinate.latitude,
                                                 longitude: placemark.coordinate.longitude)
                    guard seen.insert(location.id).inserted else { return nil }
                    return location
                }
                if results.isEmpty { error = "No locations found. Try adding the country." }
            } catch {
                guard !Task.isCancelled, generation == requestID else { return }
                self.error = "Couldn’t search locations. Check your connection and try a city and country."
            }
            isSearching = false
        }
    }

    func clear() {
        task?.cancel()
        search?.cancel()
        generation = UUID()
        isSearching = false
        results = []
        error = nil
    }
}
