import Foundation

public struct RouteNode: Codable, Identifiable, Equatable {
    public var id: UUID = UUID()
    public var lat: Double
    public var lng: Double
    public var waitTimeSec: Int = 0
    public var isTeleport: Bool = false
    public var label: String? = nil
    public var flowerIndex: Int? = nil
    public var totalFlowers: Int? = nil
    public var lapIndex: Int? = nil
    public var totalLaps: Int? = nil
    public var fruitIndex: Int? = nil
    public var totalFruits: Int? = nil

    public init(
        lat: Double,
        lng: Double,
        waitTimeSec: Int = 0,
        isTeleport: Bool = false,
        label: String? = nil,
        flowerIndex: Int? = nil,
        totalFlowers: Int? = nil,
        lapIndex: Int? = nil,
        totalLaps: Int? = nil,
        fruitIndex: Int? = nil,
        totalFruits: Int? = nil
    ) {
        self.lat = lat
        self.lng = lng
        self.waitTimeSec = waitTimeSec
        self.isTeleport = isTeleport
        self.label = label
        self.flowerIndex = flowerIndex
        self.totalFlowers = totalFlowers
        self.lapIndex = lapIndex
        self.totalLaps = totalLaps
        self.fruitIndex = fruitIndex
        self.totalFruits = totalFruits
    }

    private enum CodingKeys: String, CodingKey {
        case lat, lng, waitTimeSec, isTeleport, label
        case flowerIndex, totalFlowers, lapIndex, totalLaps
        case fruitIndex, totalFruits
        // Compatibility keys with Android route.json format
        case first, second
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let latVal = try? container.decode(Double.self, forKey: .lat) {
            self.lat = latVal
        } else if let firstVal = try? container.decode(Double.self, forKey: .first) {
            self.lat = firstVal
        } else {
            self.lat = 0.0
        }

        if let lngVal = try? container.decode(Double.self, forKey: .lng) {
            self.lng = lngVal
        } else if let secondVal = try? container.decode(Double.self, forKey: .second) {
            self.lng = secondVal
        } else {
            self.lng = 0.0
        }

        self.waitTimeSec = (try? container.decode(Int.self, forKey: .waitTimeSec)) ?? 0
        self.isTeleport = (try? container.decode(Bool.self, forKey: .isTeleport)) ?? false
        self.label = try? container.decode(String.self, forKey: .label)
        self.flowerIndex = try? container.decode(Int.self, forKey: .flowerIndex)
        self.totalFlowers = try? container.decode(Int.self, forKey: .totalFlowers)
        self.lapIndex = try? container.decode(Int.self, forKey: .lapIndex)
        self.totalLaps = try? container.decode(Int.self, forKey: .totalLaps)
        self.fruitIndex = try? container.decode(Int.self, forKey: .fruitIndex)
        self.totalFruits = try? container.decode(Int.self, forKey: .totalFruits)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(lat, forKey: .lat)
        try container.encode(lng, forKey: .lng)
        try container.encode(waitTimeSec, forKey: .waitTimeSec)
        try container.encode(isTeleport, forKey: .isTeleport)
        try container.encodeIfPresent(label, forKey: .label)
        try container.encodeIfPresent(flowerIndex, forKey: .flowerIndex)
        try container.encodeIfPresent(totalFlowers, forKey: .totalFlowers)
        try container.encodeIfPresent(lapIndex, forKey: .lapIndex)
        try container.encodeIfPresent(totalLaps, forKey: .totalLaps)
        try container.encodeIfPresent(fruitIndex, forKey: .fruitIndex)
        try container.encodeIfPresent(totalFruits, forKey: .totalFruits)
    }
}
