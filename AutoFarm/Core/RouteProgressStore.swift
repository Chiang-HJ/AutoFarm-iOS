import Foundation

public struct RouteProgress: Codable, Identifiable {
    public var id: String { routeName }
    public var routeName: String
    public var currentLoop: Int // 0-based
    public var loopTarget: Int  // 0 = 無限
    public var currentRouteIndex: Int
    public var totalPoints: Int
    public var savedTimestamp: Int64
    public var routePoints: [RouteNode]
    public var basePoints: [RouteNode]?
    public var executionMode: Int // 0: 直線, 1: 種花, 2: 果實
    public var fruitWalkDistance: Double
    public var interruptedLat: Double?
    public var interruptedLng: Double?

    public var formattedTime: String {
        let date = Date(timeIntervalSince1970: Double(savedTimestamp) / 1000.0)
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"
        return formatter.string(from: date)
    }

    public init(
        routeName: String,
        currentLoop: Int,
        loopTarget: Int,
        currentRouteIndex: Int,
        totalPoints: Int,
        savedTimestamp: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        routePoints: [RouteNode],
        basePoints: [RouteNode]? = nil,
        executionMode: Int = 0,
        fruitWalkDistance: Double = 80.0,
        interruptedLat: Double? = nil,
        interruptedLng: Double? = nil
    ) {
        self.routeName = routeName
        self.currentLoop = currentLoop
        self.loopTarget = loopTarget
        self.currentRouteIndex = currentRouteIndex
        self.totalPoints = totalPoints
        self.savedTimestamp = savedTimestamp
        self.routePoints = routePoints
        self.basePoints = basePoints
        self.executionMode = executionMode
        self.fruitWalkDistance = fruitWalkDistance
        self.interruptedLat = interruptedLat
        self.interruptedLng = interruptedLng
    }
}

public final class RouteProgressStore {
    private static let userDefaultsKey = "AutoFarm_RouteProgressStore"
    private static let backupFileName = "route_progress_backup.json"

    private static var backupFileUrl: URL? {
        guard let docDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        return docDir.appendingPathComponent(backupFileName)
    }

    public static func saveProgress(_ progress: RouteProgress) {
        var all = getAllProgressDict()
        all[progress.routeName] = progress
        saveAllProgressDict(all)
    }

    public static func getProgress(for routeName: String) -> RouteProgress? {
        let all = getAllProgressDict()
        return all[routeName]
    }

    public static func clearProgress(for routeName: String) {
        var all = getAllProgressDict()
        all.removeValue(forKey: routeName)
        saveAllProgressDict(all)
    }

    public static func clearAll() {
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
        UserDefaults.standard.synchronize()
        if let url = backupFileUrl {
            try? FileManager.default.removeItem(at: url)
        }
    }

    public static func hasProgress(for routeName: String) -> Bool {
        return getProgress(for: routeName) != nil
    }

    public static func listAllSavedProgress() -> [RouteProgress] {
        return Array(getAllProgressDict().values).sorted { $0.savedTimestamp > $1.savedTimestamp }
    }

    private static func getAllProgressDict() -> [String: RouteProgress] {
        // 1. 優先從 UserDefaults 讀取
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let dict = try? JSONDecoder().decode([String: RouteProgress].self, from: data),
           !dict.isEmpty {
            return dict
        }
        // 2. 備援：若 UserDefaults 遺失或意外退出，從本機沙盒檔案讀取
        if let url = backupFileUrl,
           let fileData = try? Data(contentsOf: url),
           let dict = try? JSONDecoder().decode([String: RouteProgress].self, from: fileData),
           !dict.isEmpty {
            return dict
        }
        return [:]
    }

    private static func saveAllProgressDict(_ dict: [String: RouteProgress]) {
        if dict.isEmpty {
            UserDefaults.standard.removeObject(forKey: userDefaultsKey)
            UserDefaults.standard.synchronize()
            if let url = backupFileUrl {
                try? FileManager.default.removeItem(at: url)
            }
            return
        }

        guard let data = try? JSONEncoder().encode(dict) else { return }
        UserDefaults.standard.set(data, forKey: userDefaultsKey)
        UserDefaults.standard.synchronize()

        // 磁碟原子寫入雙重保險
        if let url = backupFileUrl {
            try? data.write(to: url, options: .atomic)
        }
    }
}
