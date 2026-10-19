import Foundation
import UIKit
import Combine
import CoreLocation

public struct MushroomScanRecord: Identifiable, Codable, Equatable {
    public var id: UUID = UUID()
    public var typeName: String
    public var score: Int
    public var lat: Double
    public var lng: Double
    public var landmark: String = ""
    public var timestamp: Date = Date()
    public var cropBase64: String? = nil

    public init(
        id: UUID = UUID(),
        typeName: String,
        score: Int,
        lat: Double,
        lng: Double,
        landmark: String = "",
        timestamp: Date = Date(),
        cropBase64: String? = nil
    ) {
        self.id = id
        self.typeName = typeName
        self.score = score
        self.lat = lat
        self.lng = lng
        self.landmark = landmark
        self.timestamp = timestamp
        self.cropBase64 = cropBase64
    }

    public var formattedTime: String {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss"
        return df.string(from: timestamp)
    }
}

public final class MushroomLogManager: ObservableObject {
    public static let shared = MushroomLogManager()

    @Published public var records: [MushroomScanRecord] = []
    @Published public var unreadCount: Int = 0

    private let storageKey = "com.autofarm.mushroom_scan_records_v1"

    private init() {
        loadRecords()
    }

    public func addRecord(
        typeName: String,
        score: Int,
        lat: Double,
        lng: Double,
        landmark: String = "",
        cropImage: UIImage? = nil
    ) -> MushroomScanRecord? {
        // 5分鐘與100米內去重
        let fiveMinAgo = Date().addingTimeInterval(-300)
        let isDuplicate = records.contains { rec in
            rec.timestamp > fiveMinAgo &&
            rec.typeName == typeName &&
            EngineMath.getDistance(lat1: rec.lat, lon1: rec.lng, lat2: lat, lon2: lng) < 100.0
        }

        if isDuplicate {
            return nil
        }

        var base64: String? = nil
        if let crop = cropImage, let data = crop.jpegData(compressionQuality: 0.7) {
            base64 = data.base64EncodedString()
        }

        let record = MushroomScanRecord(
            typeName: typeName,
            score: score,
            lat: lat,
            lng: lng,
            landmark: landmark,
            timestamp: Date(),
            cropBase64: base64
        )

        DispatchQueue.main.async {
            self.records.insert(record, at: 0)
            if self.records.count > 200 {
                self.records.removeLast()
            }
            self.unreadCount += 1
            self.saveRecords()
        }

        return record
    }

    public func deleteRecord(id: UUID) {
        records.removeAll { $0.id == id }
        saveRecords()
    }

    public func clearAll() {
        records.removeAll()
        unreadCount = 0
        saveRecords()
    }

    public func markAllRead() {
        unreadCount = 0
    }

    private func saveRecords() {
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func loadRecords() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let list = try? JSONDecoder().decode([MushroomScanRecord].self, from: data) {
            self.records = list
        }
    }
}
