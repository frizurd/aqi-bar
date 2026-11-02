import Foundation

public protocol AQIProviding {
    func fetch(selection: LocationSelection, key: String) async throws -> AQIReading
}

public struct IQAirClient: AQIProviding {
    public typealias Transport = (URLRequest) async throws -> (Data, URLResponse)
    private let transport: Transport

    public init(transport: @escaping Transport = { try await URLSession.shared.data(for: $0) }) {
        self.transport = transport
    }

    public func fetch(selection: LocationSelection, key: String) async throws -> AQIReading {
        let request = try Self.request(selection: selection, key: key)
        let (data, response) = try await transport(request)
        guard let response = response as? HTTPURLResponse else { throw AQIError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else {
            if response.statusCode == 429 { throw AQIError.rateLimited }
            if [401, 403].contains(response.statusCode) { throw AQIError.invalidKey }
            throw AQIError.http(response.statusCode)
        }
        return try Self.parse(data)
    }

    public static func request(selection: LocationSelection, key: String) throws -> URLRequest {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw AQIError.missingKey }
        var url = URLComponents(string: "https://api.airvisual.com/v2/nearest_city")!
        var query = [URLQueryItem(name: "key", value: key)]
        if case .fixed(let location) = selection {
            guard location.latitude.isFinite, location.longitude.isFinite,
                  (-90...90).contains(location.latitude), (-180...180).contains(location.longitude) else {
                throw AQIError.invalidResponse
            }
            query += [URLQueryItem(name: "lat", value: String(location.latitude)),
                      URLQueryItem(name: "lon", value: String(location.longitude))]
        }
        url.queryItems = query
        var request = URLRequest(url: url.url!)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        return request
    }

    public static func parse(_ data: Data, now: Date = Date()) throws -> AQIReading {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = object["data"] as? [String: Any] else { throw AQIError.invalidResponse }
        guard object["status"] as? String == "success" else {
            switch payload["message"] as? String {
            case "incorrect_api_key", "invalid_api_key", "api_key_expired": throw AQIError.invalidKey
            case "call_limit_reached", "too_many_requests": throw AQIError.rateLimited
            default: throw AQIError.unavailable
            }
        }
        guard let current = payload["current"] as? [String: Any],
              let pollution = current["pollution"] as? [String: Any],
              let number = pollution["aqius"] as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite, number.doubleValue >= 0,
              number.doubleValue < Double(Int.max),
              let city = payload["city"] as? String, !city.isEmpty else { throw AQIError.invalidResponse }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = pollution["ts"] as? String ?? ""
        var observedAt = formatter.date(from: timestamp)
        if observedAt == nil {
            formatter.formatOptions = [.withInternetDateTime]
            observedAt = formatter.date(from: timestamp)
        }
        return AQIReading(value: Int(number.doubleValue.rounded()), city: city,
                          country: payload["country"] as? String ?? "",
                          observedAt: observedAt, fetchedAt: now)
    }
}
