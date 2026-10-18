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
        fruitWalkDistance: Double = 80.0
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
    }
}

public final class RouteProgressStore {
    private static let userDefaultsKey = "AutoFarm_RouteProgressStore"

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

    public static func hasProgress(for routeName: String) -> Bool {
        return getProgress(for: routeName) != nil
    }

    public static func listAllSavedProgress() -> [RouteProgress] {
        return Array(getAllProgressDict().values).sorted { $0.savedTimestamp > $1.savedTimestamp }
    }

    private static func getAllProgressDict() -> [String: RouteProgress] {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else { return [:] }
        return (try? JSONDecoder().decode([String: RouteProgress].self, from: data)) ?? [:]
    }

    private static func saveAllProgressDict(_ dict: [String: RouteProgress]) {
        if let data = try? JSONEncoder().encode(dict) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }
}
