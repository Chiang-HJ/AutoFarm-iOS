import Foundation
import Combine
import CoreLocation

public struct SavedLocation: Identifiable, Codable, Equatable {
    public var id: UUID = UUID()
    public var name: String
    public var latitude: Double
    public var longitude: Double
    public var isPinned: Bool = false
    public var tag: String = ""
    public var createdAt: Date = Date()

    public init(
        id: UUID = UUID(),
        name: String,
        latitude: Double,
        longitude: Double,
        isPinned: Bool = false,
        tag: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.isPinned = isPinned
        self.tag = tag
        self.createdAt = createdAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? "自訂座標"
        self.latitude = try container.decodeIfPresent(Double.self, forKey: .latitude) ?? 25.033964
        self.longitude = try container.decodeIfPresent(Double.self, forKey: .longitude) ?? 121.564468
        self.isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        self.tag = try container.decodeIfPresent(String.self, forKey: .tag) ?? ""
        self.createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }
}

public struct SavedRoute: Identifiable, Codable, Equatable {
    public var id: UUID = UUID()
    public var name: String
    public var nodes: [RouteNode]
    public var isPinned: Bool = false
    public var tag: String = ""
    public var createdAt: Date = Date()

    public init(
        id: UUID = UUID(),
        name: String,
        nodes: [RouteNode],
        isPinned: Bool = false,
        tag: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.nodes = nodes
        self.isPinned = isPinned
        self.tag = tag
        self.createdAt = createdAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? "自訂路線"
        self.nodes = try container.decodeIfPresent([RouteNode].self, forKey: .nodes) ?? []
        self.isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        self.tag = try container.decodeIfPresent(String.self, forKey: .tag) ?? ""
        self.createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }
}

public enum HistoryActionType: String, Codable {
    case teleport = "單點瞬移"
    case linearRoute = "直線巡航"
    case flowerRoute = "繞圈種花"
    case fruitRoute = "跳收果實"
    case concentricRoute = "同心圓種花"
}

public struct LocationHistoryItem: Identifiable, Codable, Equatable {
    public var id: UUID = UUID()
    public var type: HistoryActionType
    public var title: String
    public var latitude: Double
    public var longitude: Double
    public var routeNodes: [RouteNode]?
    public var loops: Int = 0
    public var loopMode: LoopMode = .closedLoop
    public var flowerSettings: MultiFlowerSettings?
    public var fruitWalkDistance: Double = 80.0
    public var concentricRadius: Double = 30.0
    public var concentricStep: Double = 10.0
    public var concentricMode: ConcentricMode = .multiRing
    public var timestamp: Date = Date()

    public var formattedTime: String {
        let df = DateFormatter()
        df.dateFormat = "MM/dd HH:mm:ss"
        return df.string(from: timestamp)
    }

    public init(
        id: UUID = UUID(),
        type: HistoryActionType,
        title: String,
        latitude: Double,
        longitude: Double,
        routeNodes: [RouteNode]? = nil,
        loops: Int = 0,
        loopMode: LoopMode = .closedLoop,
        flowerSettings: MultiFlowerSettings? = nil,
        fruitWalkDistance: Double = 80.0,
        concentricRadius: Double = 30.0,
        concentricStep: Double = 10.0,
        concentricMode: ConcentricMode = .multiRing,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.latitude = latitude
        self.longitude = longitude
        self.routeNodes = routeNodes
        self.loops = loops
        self.loopMode = loopMode
        self.flowerSettings = flowerSettings
        self.fruitWalkDistance = fruitWalkDistance
        self.concentricRadius = concentricRadius
        self.concentricStep = concentricStep
        self.concentricMode = concentricMode
        self.timestamp = timestamp
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.type = try container.decodeIfPresent(HistoryActionType.self, forKey: .type) ?? .teleport
        self.title = try container.decodeIfPresent(String.self, forKey: .title) ?? "歷史定位"
        self.latitude = try container.decodeIfPresent(Double.self, forKey: .latitude) ?? 25.033964
        self.longitude = try container.decodeIfPresent(Double.self, forKey: .longitude) ?? 121.564468
        self.routeNodes = try container.decodeIfPresent([RouteNode].self, forKey: .routeNodes)
        self.loops = try container.decodeIfPresent(Int.self, forKey: .loops) ?? 0
        self.loopMode = try container.decodeIfPresent(LoopMode.self, forKey: .loopMode) ?? .closedLoop
        self.flowerSettings = try container.decodeIfPresent(MultiFlowerSettings.self, forKey: .flowerSettings)
        self.fruitWalkDistance = try container.decodeIfPresent(Double.self, forKey: .fruitWalkDistance) ?? 80.0
        self.concentricRadius = try container.decodeIfPresent(Double.self, forKey: .concentricRadius) ?? 30.0
        self.concentricStep = try container.decodeIfPresent(Double.self, forKey: .concentricStep) ?? 10.0
        self.concentricMode = try container.decodeIfPresent(ConcentricMode.self, forKey: .concentricMode) ?? .multiRing
        self.timestamp = try container.decodeIfPresent(Date.self, forKey: .timestamp) ?? Date()
    }
}

public final class SavedDatabaseStore: ObservableObject {
    public static let shared = SavedDatabaseStore()

    @Published public var savedLocations: [SavedLocation] = []
    @Published public var savedRoutes: [SavedRoute] = []
    @Published public var locationHistory: [LocationHistoryItem] = []
    public var teleportHistory: [LocationHistoryItem] { locationHistory }

    private let locationsKey = "com.autofarm.saved_locations"
    private let routesKey = "com.autofarm.saved_routes"
    private let historyKey = "com.autofarm.location_history_v2"
    private let legacyHistoryKey = "com.autofarm.teleport_history"
    private let hasEverInitializedKey = "com.autofarm.has_initialized_defaults_v2"

    public var sortedLocations: [SavedLocation] {
        savedLocations.sorted {
            if $0.isPinned != $1.isPinned {
                return $0.isPinned && !$1.isPinned
            }
            return $0.createdAt > $1.createdAt
        }
    }

    public var sortedRoutes: [SavedRoute] {
        savedRoutes.sorted {
            if $0.isPinned != $1.isPinned {
                return $0.isPinned && !$1.isPinned
            }
            return $0.createdAt > $1.createdAt
        }
    }

    private init() {
        loadData()
    }

    // MARK: - 座標庫管理
    public func addLocation(name: String, latitude: Double, longitude: Double, tag: String = "") {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? "未命名座標 \(savedLocations.count + 1)" : trimmed
        let loc = SavedLocation(name: finalName, latitude: latitude, longitude: longitude, tag: tag)
        savedLocations.insert(loc, at: 0)
        saveLocations()
    }

    public func deleteLocation(id: UUID) {
        savedLocations.removeAll { $0.id == id }
        saveLocations()
    }

    public func togglePinLocation(id: UUID) {
        if let idx = savedLocations.firstIndex(where: { $0.id == id }) {
            savedLocations[idx].isPinned.toggle()
            saveLocations()
        }
    }

    public func updateLocationTag(id: UUID, tag: String) {
        if let idx = savedLocations.firstIndex(where: { $0.id == id }) {
            savedLocations[idx].tag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            saveLocations()
        }
    }

    // MARK: - 路徑庫管理
    public func saveRoute(name: String, nodes: [RouteNode], tag: String = "") {
        guard !nodes.isEmpty else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? "未命名路線 \(savedRoutes.count + 1)" : trimmed
        let r = SavedRoute(name: finalName, nodes: nodes, tag: tag)
        savedRoutes.insert(r, at: 0)
        saveRoutes()
    }

    public func deleteRoute(id: UUID) {
        savedRoutes.removeAll { $0.id == id }
        saveRoutes()
    }

    public func togglePinRoute(id: UUID) {
        if let idx = savedRoutes.firstIndex(where: { $0.id == id }) {
            savedRoutes[idx].isPinned.toggle()
            saveRoutes()
        }
    }

    public func updateRouteTag(id: UUID, tag: String) {
        if let idx = savedRoutes.firstIndex(where: { $0.id == id }) {
            savedRoutes[idx].tag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            saveRoutes()
        }
    }

    // MARK: - 全方位定位與巡航歷史紀錄管理
    public func addTeleportHistory(lat: Double, lng: Double, label: String) {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalLabel = trimmed.isEmpty ? "單點瞬移" : trimmed
        let item = LocationHistoryItem(
            type: .teleport,
            title: finalLabel,
            latitude: lat,
            longitude: lng
        )
        insertHistoryItem(item)
    }

    public func addLinearRouteHistory(name: String, basePoints: [RouteNode], loops: Int, mode: LoopMode) {
        let startCoord = basePoints.first.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) } ?? CLLocationCoordinate2D()
        let item = LocationHistoryItem(
            type: .linearRoute,
            title: name,
            latitude: startCoord.latitude,
            longitude: startCoord.longitude,
            routeNodes: basePoints,
            loops: loops,
            loopMode: mode
        )
        insertHistoryItem(item)
    }

    public func addFlowerRouteHistory(name: String, basePoints: [RouteNode], loops: Int, settings: MultiFlowerSettings) {
        let startCoord = basePoints.first.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) } ?? CLLocationCoordinate2D()
        let item = LocationHistoryItem(
            type: .flowerRoute,
            title: name,
            latitude: startCoord.latitude,
            longitude: startCoord.longitude,
            routeNodes: basePoints,
            loops: loops,
            flowerSettings: settings
        )
        insertHistoryItem(item)
    }

    public func addFruitRouteHistory(name: String, basePoints: [RouteNode], loops: Int, walkDistance: Double) {
        let startCoord = basePoints.first.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) } ?? CLLocationCoordinate2D()
        let item = LocationHistoryItem(
            type: .fruitRoute,
            title: name,
            latitude: startCoord.latitude,
            longitude: startCoord.longitude,
            routeNodes: basePoints,
            loops: loops,
            fruitWalkDistance: walkDistance
        )
        insertHistoryItem(item)
    }

    public func addConcentricRouteHistory(centerLat: Double, centerLng: Double, radius: Double, step: Double, mode: ConcentricMode) {
        let item = LocationHistoryItem(
            type: .concentricRoute,
            title: "同心圓種花 (\(Int(radius))m)",
            latitude: centerLat,
            longitude: centerLng,
            concentricRadius: radius,
            concentricStep: step,
            concentricMode: mode
        )
        insertHistoryItem(item)
    }

    private func insertHistoryItem(_ item: LocationHistoryItem) {
        locationHistory.insert(item, at: 0)
        if locationHistory.count > 150 {
            locationHistory.removeLast()
        }
        saveHistory()
    }

    public func clearHistory() {
        locationHistory.removeAll()
        saveHistory()
    }

    public func clearTeleportHistory() {
        clearHistory()
    }

    /// 從貼上的多行文字中解析並匯入座標點
    public func importRouteFromPastedText(name: String, text: String, tag: String = "") -> (success: Bool, count: Int) {
        let parsedNodes = parsePlainText(content: text)
        guard !parsedNodes.isEmpty else { return (false, 0) }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmedName.isEmpty ? "匯入路線 (\(parsedNodes.count)點)" : trimmedName
        saveRoute(name: finalName, nodes: parsedNodes, tag: tag)
        return (true, parsedNodes.count)
    }

    /// 從檔案 URL 匯入路線 (支援 GPX, CSV, TXT)
    public func importRouteFromFile(url: URL, tag: String = "") -> (success: Bool, name: String, count: Int, error: String?) {
        let isSecured = url.startAccessingSecurityScopedResource()
        defer {
            if isSecured { url.stopAccessingSecurityScopedResource() }
        }

        guard let content = try? String(contentsOf: url, encoding: .utf8) ?? String(contentsOf: url, encoding: .ascii) else {
            return (false, "", 0, "無法讀取檔案內容")
        }

        let ext = url.pathExtension.lowercased()
        let fileName = url.deletingPathExtension().lastPathComponent
        var nodes: [RouteNode] = []

        if ext == "gpx" {
            nodes = parseGPX(content: content)
        } else {
            nodes = parsePlainText(content: content)
        }

        guard !nodes.isEmpty else {
            return (false, fileName, 0, "檔案內未包含有效座標")
        }

        saveRoute(name: fileName, nodes: nodes, tag: tag)
        return (true, fileName, nodes.count, nil)
    }

    // MARK: - 內部解析工具
    private func parsePlainText(content: String) -> [RouteNode] {
        var results: [RouteNode] = []
        let lines = content.components(separatedBy: .newlines)

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix("//") { continue }

            if let (lat, lng) = extractLatLng(from: line) {
                results.append(RouteNode(lat: lat, lng: lng, label: "點位 \(results.count + 1)"))
            }
        }
        return results
    }

    private func extractLatLng(from line: String) -> (Double, Double)? {
        let clean = line.replacingOccurrences(of: "\t", with: ",")
            .replacingOccurrences(of: ";", with: ",")
            .replacingOccurrences(of: " ", with: ",")

        let parts = clean.split(separator: ",").filter { !$0.isEmpty }
        if parts.count >= 2,
           let lat = Double(parts[0]),
           let lng = Double(parts[1]) {
            if lat >= -90.0 && lat <= 90.0 && lng >= -180.0 && lng <= 180.0 {
                return (lat, lng)
            } else if lat >= -180.0 && lat <= 180.0 && lng >= -90.0 && lng <= 90.0 {
                // 自動校正顛倒經緯度
                return (lng, lat)
            }
        }
        return nil
    }

    private func parseGPX(content: String) -> [RouteNode] {
        var results: [RouteNode] = []
        let trkptRegex = try? NSRegularExpression(pattern: "<(trkpt|wpt)\\s+lat=[\"']([^\"']+)[\"']\\s+lon=[\"']([^\"']+)[\"']", options: .caseInsensitive)

        if let matches = trkptRegex?.matches(in: content, range: NSRange(content.startIndex..., in: content)) {
            for match in matches {
                if match.numberOfRanges >= 4,
                   let latRange = Range(match.range(at: 2), in: content),
                   let lonRange = Range(match.range(at: 3), in: content),
                   let lat = Double(content[latRange]),
                   let lon = Double(content[lonRange]) {
                    results.append(RouteNode(lat: lat, lng: lon, label: "航點 \(results.count + 1)"))
                }
            }
        }
        return results
    }

    // MARK: - 本地持久化 (支援容錯載入與雙重檔案備份)
    private func saveLocations() {
        if let data = try? JSONEncoder().encode(savedLocations) {
            UserDefaults.standard.set(data, forKey: locationsKey)
            backupToFile(data: data, fileName: "locations_backup.json")
        }
    }

    private func saveRoutes() {
        if let data = try? JSONEncoder().encode(savedRoutes) {
            UserDefaults.standard.set(data, forKey: routesKey)
            backupToFile(data: data, fileName: "routes_backup.json")
        }
    }

    private func saveHistory() {
        if let data = try? JSONEncoder().encode(locationHistory) {
            UserDefaults.standard.set(data, forKey: historyKey)
            backupToFile(data: data, fileName: "history_backup.json")
        }
    }

    private func loadData() {
        // 1. 載入座標 (優先嘗試 UserDefaults，失敗嘗試檔案備份)
        if let data = UserDefaults.standard.data(forKey: locationsKey) ?? readBackupFile(fileName: "locations_backup.json"),
           let list = try? JSONDecoder().decode([SavedLocation].self, from: data) {
            self.savedLocations = list
        }

        // 2. 載入路線
        if let data = UserDefaults.standard.data(forKey: routesKey) ?? readBackupFile(fileName: "routes_backup.json"),
           let list = try? JSONDecoder().decode([SavedRoute].self, from: data) {
            self.savedRoutes = list
        }

        // 3. 載入歷史紀錄 (支援升級相容)
        if let data = UserDefaults.standard.data(forKey: historyKey) ?? readBackupFile(fileName: "history_backup.json"),
           let list = try? JSONDecoder().decode([LocationHistoryItem].self, from: data) {
            self.locationHistory = list
        } else if let legacyData = UserDefaults.standard.data(forKey: legacyHistoryKey),
                  let legacyList = try? JSONDecoder().decode([SavedLocation].self, from: legacyData) {
            self.locationHistory = legacyList.map {
                LocationHistoryItem(type: .teleport, title: $0.name, latitude: $0.latitude, longitude: $0.longitude, timestamp: $0.createdAt)
            }
        }

        // 4. 首次安裝保護邏輯：僅當設備「從未初始化過」才填入範例，升級絕不覆蓋
        let hasInitialized = UserDefaults.standard.bool(forKey: hasEverInitializedKey)
        if !hasInitialized {
            if savedLocations.isEmpty {
                initDefaultLocations()
            }
            if savedRoutes.isEmpty {
                initDefaultRoutes()
            }
            UserDefaults.standard.set(true, forKey: hasEverInitializedKey)
        }
    }

    private func initDefaultLocations() {
        savedLocations = [
            SavedLocation(name: "台北101景觀台", latitude: 25.033964, longitude: 121.564468, isPinned: true, tag: "信義區"),
            SavedLocation(name: "大安森林公園大生態池", latitude: 25.029661, longitude: 121.535492, isPinned: true, tag: "花苞區"),
            SavedLocation(name: "台北車站南門", latitude: 25.047781, longitude: 121.517042, isPinned: false, tag: "補給點")
        ]
        saveLocations()
    }

    private func initDefaultRoutes() {
        let daanPoints = [
            RouteNode(lat: 25.032540, lng: 121.535080, label: "大安1"),
            RouteNode(lat: 25.032120, lng: 121.537220, label: "大安2"),
            RouteNode(lat: 25.028450, lng: 121.537380, label: "大安3"),
            RouteNode(lat: 25.028210, lng: 121.534890, label: "大安4")
        ]
        savedRoutes = [
            SavedRoute(name: "大安森林公園花苞外環", nodes: daanPoints, isPinned: true, tag: "大安區")
        ]
        saveRoutes()
    }

    // MARK: - 檔案安全備份
    private func getBackupDirectory() -> URL? {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let dir = appSupport.appendingPathComponent("DatabaseBackup", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func backupToFile(data: Data, fileName: String) {
        guard let dir = getBackupDirectory() else { return }
        let fileURL = dir.appendingPathComponent(fileName)
        try? data.write(to: fileURL, options: .atomic)
    }

    private func readBackupFile(fileName: String) -> Data? {
        guard let dir = getBackupDirectory() else { return nil }
        let fileURL = dir.appendingPathComponent(fileName)
        return try? Data(contentsOf: fileURL)
    }
}
