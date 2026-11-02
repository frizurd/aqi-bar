import Foundation

public enum AQIBand: Int, CaseIterable, Sendable {
    case good, moderate, sensitive, unhealthy, veryUnhealthy, hazardous

    public init(value: Int) {
        switch value {
        case ...50: self = .good
        case ...100: self = .moderate
        case ...150: self = .sensitive
        case ...200: self = .unhealthy
        case ...300: self = .veryUnhealthy
        default: self = .hazardous
        }
    }

    public var title: String {
        ["Good", "Moderate", "Unhealthy for sensitive groups", "Unhealthy", "Very unhealthy", "Hazardous"][rawValue]
    }

    // Exact RGB palette from the original SketchyBar plugin.
    public var rgb: UInt32 {
        [0xa6da95, 0xeed49f, 0xf5a97f, 0xed8796, 0xc6a0f6, 0xff6685][rawValue]
    }

    public var range: String {
        ["0–50", "51–100", "101–150", "151–200", "201–300", "301+"][rawValue]
    }
}

public struct SavedLocation: Codable, Equatable, Sendable, Identifiable {
    public let name: String
    public let latitude: Double
    public let longitude: Double
    public var id: String { "\(latitude),\(longitude)" }

    public init(name: String, latitude: Double, longitude: Double) {
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
    }
}

public enum LocationSelection: Codable, Equatable, Sendable {
    case automatic
    case fixed(SavedLocation)

    public var title: String {
        switch self {
        case .automatic: return "Automatic (public IP)"
        case .fixed(let location): return location.name
        }
    }
}

public struct AQIReading: Codable, Equatable, Sendable {
    public let value: Int
    public let city: String
    public let country: String
    public let observedAt: Date?
    public let fetchedAt: Date
    public var band: AQIBand { AQIBand(value: value) }
    public var place: String { [city, country].filter { !$0.isEmpty }.joined(separator: ", ") }

    public init(value: Int, city: String, country: String, observedAt: Date?, fetchedAt: Date) {
        self.value = value
        self.city = city
        self.country = country
        self.observedAt = observedAt
        self.fetchedAt = fetchedAt
    }

    public func isOld(at date: Date) -> Bool {
        date.timeIntervalSince(fetchedAt) > 30 * 60 ||
        observedAt.map { date.timeIntervalSince($0) > 3 * 60 * 60 } == true
    }
}

public struct CachedReading: Codable, Sendable {
    public let selection: LocationSelection
    public let reading: AQIReading

    public init(selection: LocationSelection, reading: AQIReading) {
        self.selection = selection
        self.reading = reading
    }
}

public enum AQIError: LocalizedError, Equatable {
    case missingKey, invalidKey, rateLimited, unavailable, invalidResponse
    case http(Int)

    public var errorDescription: String? {
        switch self {
        case .missingKey: return "Add your IQAir API key in Settings."
        case .invalidKey: return "IQAir rejected the API key. Check it in Settings."
        case .rateLimited: return "IQAir’s request limit was reached. Try again later."
        case .unavailable: return "IQAir has no current reading for this location."
        case .invalidResponse: return "IQAir returned an unreadable response."
        case .http(let status): return "IQAir is temporarily unavailable (HTTP \(status))."
        }
    }
}
