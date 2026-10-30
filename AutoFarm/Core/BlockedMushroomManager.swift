import Foundation
import Combine

public struct BlockedMushroomItem: Identifiable, Codable, Equatable {
    public var id: UUID = UUID()
    public var groupName: String = "主帳號"
    public var mushroomType: String = "活動蘑菇"
    public var landmark: String = ""
    public var lat: Double = 0.0
    public var lng: Double = 0.0
    public var capturedTimestamp: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    public var remainingMillisAtCapture: Int64 = 0
    public var targetFinishTimestamp: Int64 = 0
    public var note: String = ""

    public init(
        id: UUID = UUID(),
        groupName: String = "主帳號",
        mushroomType: String = "活動蘑菇",
        landmark: String = "",
        lat: Double = 0.0,
        lng: Double = 0.0,
        capturedTimestamp: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        remainingMillisAtCapture: Int64 = 0,
        targetFinishTimestamp: Int64? = nil,
        note: String = ""
    ) {
        self.id = id
        self.groupName = groupName
        self.mushroomType = mushroomType
        self.landmark = landmark
        self.lat = lat
        self.lng = lng
        self.capturedTimestamp = capturedTimestamp
        self.remainingMillisAtCapture = remainingMillisAtCapture
        self.targetFinishTimestamp = targetFinishTimestamp ?? (capturedTimestamp + remainingMillisAtCapture)
        self.note = note
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.groupName = try container.decodeIfPresent(String.self, forKey: .groupName) ?? "主帳號"
        self.mushroomType = try container.decodeIfPresent(String.self, forKey: .mushroomType) ?? "活動蘑菇"
        self.landmark = try container.decodeIfPresent(String.self, forKey: .landmark) ?? ""
        self.lat = try container.decodeIfPresent(Double.self, forKey: .lat) ?? 0.0
        self.lng = try container.decodeIfPresent(Double.self, forKey: .lng) ?? 0.0
        self.capturedTimestamp = try container.decodeIfPresent(Int64.self, forKey: .capturedTimestamp) ?? Int64(Date().timeIntervalSince1970 * 1000)
        self.remainingMillisAtCapture = try container.decodeIfPresent(Int64.self, forKey: .remainingMillisAtCapture) ?? 0
        self.targetFinishTimestamp = try container.decodeIfPresent(Int64.self, forKey: .targetFinishTimestamp) ?? (self.capturedTimestamp + self.remainingMillisAtCapture)
        self.note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
    }

    public func getRemainingSeconds() -> Int64 {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let diff = targetFinishTimestamp - now
        return diff > 0 ? diff / 1000 : 0
    }

    public func isFinished() -> Bool {
        return getRemainingSeconds() <= 0
    }

    public func formatRemaining() -> String {
        let sec = getRemainingSeconds()
        if sec <= 0 { return "已結束" }
        let days = sec / 86400
        let hours = (sec % 86400) / 3600
        let mins = (sec % 3600) / 60
        let s = sec % 60

        var parts: [String] = []
        if days > 0 { parts.append("\(days)日") }
        if days > 0 || hours > 0 { parts.append("\(hours)小時") }
        parts.append("\(mins)分")
        parts.append("\(s)秒")
        return parts.joined(separator: " ")
    }

    public func formatFinishTime() -> String {
        guard targetFinishTimestamp > 0 else { return "--:--" }
        let date = Date(timeIntervalSince1970: Double(targetFinishTimestamp) / 1000.0)
        let df = DateFormatter()
        df.dateFormat = "MM/dd HH:mm:ss"
        return df.string(from: date)
    }

    public func formatCaptureTime() -> String {
        guard capturedTimestamp > 0 else { return "--:--" }
        let date = Date(timeIntervalSince1970: Double(capturedTimestamp) / 1000.0)
        let df = DateFormatter()
        df.dateFormat = "MM/dd HH:mm:ss"
        return df.string(from: date)
    }
}

public final class BlockedMushroomManager: ObservableObject {
    public static let shared = BlockedMushroomManager()

    @Published public var groups: [String] = ["主帳號", "小號1"]
    @Published public var items: [BlockedMushroomItem] = []

    private let groupsKey = "com.autofarm.blocked_mushroom_groups"
    private let itemsKey = "com.autofarm.blocked_mushroom_items"

    private init() {
        loadData()
    }

    // MARK: - 資料載入與持久化
    public func loadData() {
        if let gData = UserDefaults.standard.data(forKey: groupsKey),
           let list = try? JSONDecoder().decode([String].self, from: gData), !list.isEmpty {
            self.groups = list
        } else {
            self.groups = ["主帳號", "小號1"]
        }

        if let iData = UserDefaults.standard.data(forKey: itemsKey),
           let list = try? JSONDecoder().decode([BlockedMushroomItem].self, from: iData) {
            self.items = list
        }
    }

    public func saveData() {
        if let gData = try? JSONEncoder().encode(groups) {
            UserDefaults.standard.set(gData, forKey: groupsKey)
        }
        if let iData = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(iData, forKey: itemsKey)
        }
    }

    // MARK: - 分組管理
    @discardableResult
    public func addGroup(name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !groups.contains(trimmed) else { return false }
        groups.append(trimmed)
        saveData()
        return true
    }

    @discardableResult
    public func renameGroup(oldName: String, newName: String) -> Bool {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !groups.contains(trimmed), let idx = groups.firstIndex(of: oldName) else { return false }
        groups[idx] = trimmed
        for i in 0..<items.count {
            if items[i].groupName == oldName {
                items[i].groupName = trimmed
            }
        }
        saveData()
        return true
    }

    @discardableResult
    public func deleteGroup(name: String) -> Bool {
        guard groups.count > 1, let idx = groups.firstIndex(of: name) else { return false }
        groups.remove(at: idx)
        items.removeAll { $0.groupName == name }
        saveData()
        return true
    }

    // MARK: - 卡菇紀錄管理
    public func addItem(_ item: BlockedMushroomItem) {
        items.insert(item, at: 0)
        saveData()
    }

    public func updateItem(_ item: BlockedMushroomItem) {
        if let idx = items.firstIndex(where: { $0.id == item.id }) {
            items[idx] = item
            saveData()
        }
    }

    public func deleteItem(id: UUID) {
        items.removeAll { $0.id == id }
        saveData()
    }

    public func clearFinished(for groupName: String) {
        items.removeAll { $0.groupName == groupName && $0.isFinished() }
        saveData()
    }

    public func getItems(for groupName: String) -> [BlockedMushroomItem] {
        return items.filter { $0.groupName == groupName }
    }
}
