import Foundation
import Combine
import UIKit

public struct MushroomItem: Codable, Identifiable, Equatable {
    public var id: String { key }
    public var key: String
    public var name: String
    public var latitude: Double
    public var longitude: Double
    public var totalHp: Int64
    public var currentHp: Int64
    public var challengeType: Int
    public var challengeTypeName: String
    public var challengeCategory: String
    public var challengeLevel: Int
    public var challengerCount: Int
    public var maxChallengers: Int
    public var battlePower: Int64
    public var finishTimeMs: Int64?
    public var imageUrl: String?
    public var discoveredAt: Int64
    public var updatedAt: Int64

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.key = try container.decodeIfPresent(String.self, forKey: .key) ?? ""
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? "未知蘑菇"
        self.latitude = try container.decodeIfPresent(Double.self, forKey: .latitude) ?? 0.0
        self.longitude = try container.decodeIfPresent(Double.self, forKey: .longitude) ?? 0.0
        self.totalHp = try container.decodeIfPresent(Int64.self, forKey: .totalHp) ?? 0
        self.currentHp = try container.decodeIfPresent(Int64.self, forKey: .currentHp) ?? 0
        self.challengeType = try container.decodeIfPresent(Int.self, forKey: .challengeType) ?? 0
        self.challengeTypeName = try container.decodeIfPresent(String.self, forKey: .challengeTypeName) ?? "一般蘑菇"
        self.challengeCategory = try container.decodeIfPresent(String.self, forKey: .challengeCategory) ?? "一般"
        self.challengeLevel = try container.decodeIfPresent(Int.self, forKey: .challengeLevel) ?? 1
        self.challengerCount = try container.decodeIfPresent(Int.self, forKey: .challengerCount) ?? 0
        self.maxChallengers = try container.decodeIfPresent(Int.self, forKey: .maxChallengers) ?? 5
        self.battlePower = try container.decodeIfPresent(Int64.self, forKey: .battlePower) ?? 0
        self.finishTimeMs = try container.decodeIfPresent(Int64.self, forKey: .finishTimeMs)
        self.imageUrl = try container.decodeIfPresent(String.self, forKey: .imageUrl)
        self.discoveredAt = try container.decodeIfPresent(Int64.self, forKey: .discoveredAt) ?? Int64(Date().timeIntervalSince1970 * 1000)
        self.updatedAt = try container.decodeIfPresent(Int64.self, forKey: .updatedAt) ?? Int64(Date().timeIntervalSince1970 * 1000)
    }

    private enum CodingKeys: String, CodingKey {
        case key, name, latitude, longitude, totalHp, currentHp
        case challengeType, challengeTypeName, challengeCategory, challengeLevel
        case challengerCount, maxChallengers, battlePower, finishTimeMs
        case imageUrl, discoveredAt, updatedAt
    }

    /// 判斷蘑菇是否已經過期或已被擊破
    public func isExpired(nowMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) -> Bool {
        if challengerCount > 0 {
            if let ft = finishTimeMs, ft > 0, nowMs >= ft {
                return true
            }
            return false
        }
        // 野生無人打：超過 24 小時未刷新視為過期
        if nowMs - updatedAt > 24 * 3600 * 1000 {
            return true
        }
        return false
    }

    /// 計算即時動態剩餘血量
    public func getDynamicCurrentHp(nowMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) -> Int64 {
        if currentHp <= 0 { return 0 }
        if challengerCount == 0 || finishTimeMs == nil || finishTimeMs! <= 0 {
            return currentHp
        }
        let ft = finishTimeMs!
        if nowMs >= ft { return 0 }

        let remSec = Double(ft - nowMs) / 1000.0
        let power = getEffectiveBattlePower(nowMs: nowMs)
        if power > 0 {
            let dynHp = Int64(remSec * Double(power))
            return max(0, min(dynHp, totalHp))
        }

        let totalDurationMs = max(1000, Double(ft - updatedAt))
        let remainingMs = max(0, Double(ft - nowMs))
        let ratio = remainingMs / totalDurationMs
        return max(0, min(Int64(Double(currentHp) * ratio), totalHp))
    }

    /// 即時動態血量比例 (0.0 ~ 1.0)
    public func dynamicHpRatio(nowMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) -> Double {
        if totalHp <= 0 { return 0.0 }
        let dyn = Double(getDynamicCurrentHp(nowMs: nowMs))
        return max(0.0, min(1.0, dyn / Double(totalHp)))
    }

    /// 計算剩餘秒數
    public func remainingSeconds(nowMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) -> Int64 {
        guard let ft = finishTimeMs, ft > 0 else { return 0 }
        return max(0, (ft - nowMs) / 1000)
    }

    /// 取得有效戰力
    public func getEffectiveBattlePower(nowMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) -> Int64 {
        if battlePower > 0 { return battlePower }
        let remSec = remainingSeconds(nowMs: nowMs)
        if remSec > 0 && currentHp > 0 {
            return currentHp / remSec
        }
        return 0
    }
}

public final class MushroomRadarManager: ObservableObject {
    public static let shared = MushroomRadarManager()

    @Published public var activeMushrooms: [String: MushroomItem] = [:]
    @Published public var pinnedKeys: Set<String> = []
    @Published public var isLoading: Bool = false
    @Published public var lastSyncDate: Date? = nil

    private let pinnedStorageKey = "com.autofarm.radar.pinned_keys"
    private var timer: Timer? = nil
    private let databaseUrl = "https://pikmin-radar-7c6de-default-rtdb.asia-southeast1.firebasedatabase.app/mushrooms.json"

    private init() {
        loadPinnedKeys()
        fetchMushrooms()
    }

    // MARK: - 卡菇釘選持久化
    private func loadPinnedKeys() {
        if let array = UserDefaults.standard.array(forKey: pinnedStorageKey) as? [String] {
            self.pinnedKeys = Set(array)
        }
    }

    private func savePinnedKeys() {
        UserDefaults.standard.set(Array(pinnedKeys), forKey: pinnedStorageKey)
    }

    public func togglePin(key: String) {
        if pinnedKeys.contains(key) {
            pinnedKeys.remove(key)
        } else {
            pinnedKeys.insert(key)
        }
        savePinnedKeys()
    }

    public func isPinned(key: String) -> Bool {
        pinnedKeys.contains(key)
    }

    // MARK: - 從 Firebase Realtime Database 抓取最新蘑菇
    public func fetchMushrooms(completion: ((Int) -> Void)? = nil) {
        guard let url = URL(string: databaseUrl) else { return }
        DispatchQueue.main.async {
            self.isLoading = true
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10.0

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            DispatchQueue.main.async {
                self.isLoading = false
            }

            guard let data = data, error == nil else {
                DispatchQueue.main.async {
                    completion?(self.activeMushrooms.count)
                }
                return
            }

            do {
                let decoder = JSONDecoder()
                let map = try decoder.decode([String: MushroomItem].self, from: data)
                let now = Int64(Date().timeIntervalSince1970 * 1000)

                var validMap: [String: MushroomItem] = [:]
                for (k, item) in map {
                    if !item.isExpired(nowMs: now) {
                        validMap[k] = item
                    }
                }

                DispatchQueue.main.async {
                    self.activeMushrooms = validMap
                    self.lastSyncDate = Date()
                    completion?(validMap.count)
                }
            } catch {
                DispatchQueue.main.async {
                    completion?(self.activeMushrooms.count)
                }
            }
        }.resume()
    }

    // MARK: - 啟動與停止定時背景輪詢
    public func startPolling(interval: TimeInterval = 12.0) {
        stopPolling()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.fetchMushrooms()
        }
    }

    public func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - 卡菇下載與匯出格式化
    /// 嚴格規範格式：[蘑菇種類] [預計結束時間(YYYY/MM/DD HH:mm:ss 或 野生未開打)] [經緯度]
    public func exportPinnedMushroomsText() -> String {
        let pinnedItems = activeMushrooms.values.filter { pinnedKeys.contains($0.key) }
        guard !pinnedItems.isEmpty else { return "" }

        let df = DateFormatter()
        df.dateFormat = "yyyy/MM/dd HH:mm:ss"

        let lines = pinnedItems.map { m -> String in
            let timeStr: String
            if let ft = m.finishTimeMs, ft > 0 {
                let d = Date(timeIntervalSince1970: Double(ft) / 1000.0)
                timeStr = df.string(from: d)
            } else {
                timeStr = "野生未開打"
            }
            let latStr = String(format: "%.6f", m.latitude)
            let lngStr = String(format: "%.6f", m.longitude)
            return "\(m.challengeTypeName) \(timeStr) \(latStr),\(lngStr)"
        }

        return lines.joined(separator: "\n")
    }

    /// 產生下載檔案 URL
    public func exportPinnedMushroomsFile() -> URL? {
        let content = exportPinnedMushroomsText()
        guard !content.isEmpty else { return nil }

        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd_HHmmss"
        let filename = "卡菇清單_\(df.string(from: Date())).txt"

        let tempDir = FileManager.default.temporaryDirectory
        let fileUrl = tempDir.appendingPathComponent(filename)

        do {
            try content.write(to: fileUrl, atomically: true, encoding: .utf8)
            return fileUrl
        } catch {
            return nil
        }
    }
}
