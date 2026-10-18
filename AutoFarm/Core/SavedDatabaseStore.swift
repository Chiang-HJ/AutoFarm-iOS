import Foundation
import Combine

public struct SavedLocation: Identifiable, Codable, Equatable {
    public var id: UUID = UUID()
    public var name: String
    public var latitude: Double
    public var longitude: Double
    public var createdAt: Date = Date()

    public init(id: UUID = UUID(), name: String, latitude: Double, longitude: Double, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.createdAt = createdAt
    }
}

public struct SavedRoute: Identifiable, Codable, Equatable {
    public var id: UUID = UUID()
    public var name: String
    public var nodes: [RouteNode]
    public var createdAt: Date = Date()

    public init(id: UUID = UUID(), name: String, nodes: [RouteNode], createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.nodes = nodes
        self.createdAt = createdAt
    }
}

public final class SavedDatabaseStore: ObservableObject {
    public static let shared = SavedDatabaseStore()

    @Published public var savedLocations: [SavedLocation] = []
    @Published public var savedRoutes: [SavedRoute] = []

    private let locationsKey = "com.autofarm.saved_locations"
    private let routesKey = "com.autofarm.saved_routes"

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
    public func addLocation(name: String, latitude: Double, longitude: Double) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? "未命名座標 \(savedLocations.count + 1)" : trimmed
        let loc = SavedLocation(name: finalName, latitude: latitude, longitude: longitude)
        savedLocations.insert(loc, at: 0)
        saveLocations()
    }

    public func deleteLocation(id: UUID) {
        savedLocations.removeAll { $0.id == id }
        saveLocations()
    }

    // MARK: - 路徑庫管理
    public func saveRoute(name: String, nodes: [RouteNode]) {
        guard !nodes.isEmpty else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? "未命名路線 \(savedRoutes.count + 1)" : trimmed
        let r = SavedRoute(name: finalName, nodes: nodes)
        savedRoutes.insert(r, at: 0)
        saveRoutes()
    }

    public func deleteRoute(id: UUID) {
        savedRoutes.removeAll { $0.id == id }
        saveRoutes()
    }

    /// 從貼上的多行文字中解析並匯入座標點
    public func importRouteFromPastedText(name: String, text: String) -> (success: Bool, count: Int) {
        let lines = text.components(separatedBy: .newlines)
        var parsedNodes: [RouteNode] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed.hasPrefix("//") { continue }

            // 支援逗號或空格分隔: 25.033964, 121.564468 或 25.033964 121.564468
            let separators = CharacterSet(charactersIn: ", \t")
            let parts = trimmed.components(separatedBy: separators).filter { !$0.isEmpty }

            if parts.count >= 2,
               let lat = Double(parts[0]),
               let lng = Double(parts[1]) {
                let label = parts.count >= 3 ? parts[2] : "航點 \(parsedNodes.count + 1)"
                parsedNodes.append(RouteNode(lat: lat, lng: lng, label: label))
            }
        }

        guard !parsedNodes.isEmpty else { return (false, 0) }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmedName.isEmpty ? "匯入路線 (\(parsedNodes.count)點)" : trimmedName
        saveRoute(name: finalName, nodes: parsedNodes)
        return (true, parsedNodes.count)
    }

    // MARK: - 持久化儲存
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

    private func loadData() {
        if let data = UserDefaults.standard.data(forKey: locationsKey),
           let list = try? JSONDecoder().decode([SavedLocation].self, from: data) {
            self.savedLocations = list
        }
        if let data = UserDefaults.standard.data(forKey: routesKey),
           let list = try? JSONDecoder().decode([SavedRoute].self, from: data) {
            self.savedRoutes = list
        }
    }

    private func initDefaultLocations() {
        savedLocations = [
            SavedLocation(name: "台北101景觀台", latitude: 25.033964, longitude: 121.564468),
            SavedLocation(name: "大安森林公園大生態池", latitude: 25.029661, longitude: 121.535492),
            SavedLocation(name: "台北車站南門", latitude: 25.047781, longitude: 121.517042)
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
            SavedRoute(name: "大安森林公園花苞外環", nodes: daanPoints)
        ]
        saveRoutes()
    }
}
