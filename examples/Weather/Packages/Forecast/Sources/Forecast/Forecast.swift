import Foundation

public struct Day: Identifiable, Sendable {
    public let id = UUID()
    public let name: String
    public let symbol: String
    public let high: Int
    public let low: Int
}

public enum Forecast {
    public static let week: [Day] = [
        Day(name: "Mon", symbol: "sun.max.fill", high: 21, low: 12),
        Day(name: "Tue", symbol: "cloud.sun.fill", high: 19, low: 11),
        Day(name: "Wed", symbol: "cloud.rain.fill", high: 15, low: 10),
        Day(name: "Thu", symbol: "cloud.bolt.rain.fill", high: 14, low: 9),
        Day(name: "Fri", symbol: "sun.max.fill", high: 22, low: 13),
    ]
}
