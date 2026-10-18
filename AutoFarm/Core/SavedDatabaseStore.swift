import Foundation
import Combine

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
}

public struct TeleportHistoryItem: Identifiable, Codable, Equatable {
    public var id: UUID = UUID()
    public var latitude: Double
    public var longitude: Double
    public var label: String
    public var timestamp: Date = Date()

    public var formattedTime: String {
        let df = DateFormatter()
        df.dateFormat = "MM/dd HH:mm:ss"
        return df.string(from: timestamp)
    }

    public init(id: UUID = UUID(), latitude: Double, longitude: Double, label: String, timestamp: Date = Date()) {
        self.id = id
        self.latitude = latitude
        self.longitude = longitude
        self.label = label
        self.timestamp = timestamp
    }
}

public final class SavedDatabaseStore: ObservableObject {
    public static let shared = SavedDatabaseStore()

    @Published public var savedLocations: [SavedLocation] = []
    @Published public var savedRoutes: [SavedRoute] = []
    @Published public var teleportHistory: [TeleportHistoryItem] = []

    private let locationsKey = "com.autofarm.saved_locations"
    private let routesKey = "com.autofarm.saved_routes"
    private let historyKey = "com.autofarm.teleport_history"

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
        if savedLocations.isEmpty {
            initDefaultLocations()
        }
        if savedRoutes.isEmpty {
            initDefaultRoutes()
        }
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

    // MARK: - 瞬移歷史紀錄管理
    public func addTeleportHistory(lat: Double, lng: Double, label: String) {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalLabel = trimmed.isEmpty ? "瞬移點" : trimmed
        let item = TeleportHistoryItem(latitude: lat, longitude: lng, label: finalLabel)
        teleportHistory.insert(item, at: 0)
        if teleportHistory.count > 100 {
            teleportHistory.removeLast()
        }
        saveHistory()
    }

    public func clearTeleportHistory() {
        teleportHistory.removeAll()
        saveHistory()
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
        } else if ext == "csv" || ext == "txt" {
            nodes = parsePlainText(content: content)
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

        for (idx, rawLine) in lines.enumerated() {
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

    // MARK: - 本地持久化
    private func saveLocations() {
        if let data = try? JSONEncoder().encode(savedLocations) {
            UserDefaults.standard.set(data, forKey: locationsKey)
        }
    }

    private func saveRoutes() {
        if let data = try? JSONEncoder().encode(savedRoutes) {
            UserDefaults.standard.set(data, forKey: routesKey)
        }
    }

    private func saveHistory() {
        if let data = try? JSONEncoder().encode(teleportHistory) {
            UserDefaults.standard.set(data, forKey: historyKey)
        }
    }

    private func loadData() {
        if let data = UserDefaults.standard.data(forKey: locationsKey),
           let list = try? JSONDecoder().decode([SavedLocation].self, from: data) {
            self.savedLocations = list
        }
        if let data = UserDefaults.standard.data(forKey: routesKey),
           let list = try? JSONDecoder().decode([SavedRoute].self, from: data) {
            self.savedRoutes = list
        }
        if let data = UserDefaults.standard.data(forKey: historyKey),
           let list = try? JSONDecoder().decode([TeleportHistoryItem].self, from: data) {
            self.teleportHistory = list
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
}
