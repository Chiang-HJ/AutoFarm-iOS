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
        let parsedNodes = parsePlainText(content: text)
        guard !parsedNodes.isEmpty else { return (false, 0) }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmedName.isEmpty ? "匯入路線 (\(parsedNodes.count)點)" : trimmedName
        saveRoute(name: finalName, nodes: parsedNodes)
        return (true, parsedNodes.count)
    }

    /// 從檔案 URL 匯入路線 (支援 GPX, CSV, TXT)
    public func importRouteFromFile(url: URL) -> (success: Bool, name: String, count: Int, error: String?) {
        let isSecured = url.startAccessingSecurityScopedResource()
        defer {
            if isSecured { url.stopAccessingSecurityScopedResource() }
        }

        guard let content = try? String(contentsOf: url, encoding: .utf8) ?? String(contentsOf: url, encoding: .ascii) else {
            return (false, "", 0, "無法讀取檔案內容 (請確認檔案編碼為 UTF-8 或純文字)")
        }

        let baseName = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension.lowercased()

        var parsedNodes: [RouteNode] = []

        if ext == "gpx" || content.contains("<gpx") || content.contains("<trkpt") || content.contains("<wpt") {
            parsedNodes = parseGPX(content: content)
        } else if ext == "csv" || content.contains(",") {
            parsedNodes = parseCSV(content: content)
            if parsedNodes.isEmpty {
                parsedNodes = parsePlainText(content: content)
            }
        } else {
            parsedNodes = parsePlainText(content: content)
        }

        guard !parsedNodes.isEmpty else {
            return (false, baseName, 0, "未能從檔案中解析出有效的經緯度座標點")
        }

        let finalName = baseName.isEmpty ? "匯入路線 (\(parsedNodes.count)點)" : baseName
        saveRoute(name: finalName, nodes: parsedNodes)
        return (true, finalName, parsedNodes.count, nil)
    }

    private func parseGPX(content: String) -> [RouteNode] {
        var nodes: [RouteNode] = []
        let p1 = #"lat\s*=\s*["']([-+]?[0-9]*\.?[0-9]+)["'][^>]*?lon\s*=\s*["']([-+]?[0-9]*\.?[0-9]+)["']"#
        let p2 = #"lon\s*=\s*["']([-+]?[0-9]*\.?[0-9]+)["'][^>]*?lat\s*=\s*["']([-+]?[0-9]*\.?[0-9]+)["']"#

        let nsContent = content as NSString

        if let reg1 = try? NSRegularExpression(pattern: p1, options: .caseInsensitive) {
            let matches = reg1.matches(in: content, range: NSRange(location: 0, length: nsContent.length))
            for m in matches {
                if m.numberOfRanges >= 3 {
                    let latStr = nsContent.substring(with: m.range(at: 1))
                    let lonStr = nsContent.substring(with: m.range(at: 2))
                    if let lat = Double(latStr), let lon = Double(lonStr) {
                        nodes.append(RouteNode(lat: lat, lng: lon, label: "GPX \(nodes.count + 1)"))
                    }
                }
            }
        }

        if nodes.isEmpty, let reg2 = try? NSRegularExpression(pattern: p2, options: .caseInsensitive) {
            let matches = reg2.matches(in: content, range: NSRange(location: 0, length: nsContent.length))
            for m in matches {
                if m.numberOfRanges >= 3 {
                    let lonStr = nsContent.substring(with: m.range(at: 1))
                    let latStr = nsContent.substring(with: m.range(at: 2))
                    if let lat = Double(latStr), let lon = Double(lonStr) {
                        nodes.append(RouteNode(lat: lat, lng: lon, label: "GPX \(nodes.count + 1)"))
                    }
                }
            }
        }

        return nodes
    }

    private func parseCSV(content: String) -> [RouteNode] {
        let lines = content.components(separatedBy: .newlines)
        guard !lines.isEmpty else { return [] }

        var latCol = -1
        var lngCol = -1
        var nameCol = -1

        var nodes: [RouteNode] = []
        var startIndex = 0

        let firstLine = lines[0].lowercased()
        let headers = firstLine.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\"", with: "") }
        for (i, h) in headers.enumerated() {
            if h == "lat" || h == "latitude" || h == "緯度" { latCol = i }
            if h == "lng" || h == "lon" || h == "longitude" || h == "經度" { lngCol = i }
            if h == "name" || h == "label" || h == "title" || h == "名稱" { nameCol = i }
        }

        if latCol != -1 && lngCol != -1 {
            startIndex = 1
        }

        for i in startIndex..<lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") { continue }
            let cols = line.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\"", with: "") }

            if latCol != -1 && lngCol != -1 {
                if cols.count > max(latCol, lngCol),
                   let lat = Double(cols[latCol]),
                   let lng = Double(cols[lngCol]) {
                    let label = (nameCol != -1 && cols.count > nameCol) ? cols[nameCol] : "點 \(nodes.count + 1)"
                    nodes.append(RouteNode(lat: lat, lng: lng, label: label))
                }
            } else {
                let nums = cols.compactMap { Double($0) }
                if nums.count >= 2 {
                    let lat = nums[0]
                    let lng = nums[1]
                    if abs(lat) <= 90 && abs(lng) <= 180 {
                        nodes.append(RouteNode(lat: lat, lng: lng, label: "CSV \(nodes.count + 1)"))
                    }
                }
            }
        }

        return nodes
    }

    private func parsePlainText(content: String) -> [RouteNode] {
        let lines = content.components(separatedBy: .newlines)
        var nodes: [RouteNode] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed.hasPrefix("//") { continue }

            let separators = CharacterSet(charactersIn: ", \t;")
            let parts = trimmed.components(separatedBy: separators).filter { !$0.isEmpty }

            if parts.count >= 2,
               let lat = Double(parts[0]),
               let lng = Double(parts[1]) {
                if abs(lat) <= 90 && abs(lng) <= 180 {
                    let label = parts.count >= 3 ? parts[2] : "航點 \(nodes.count + 1)"
                    nodes.append(RouteNode(lat: lat, lng: lng, label: label))
                }
            }
        }
        return nodes
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
