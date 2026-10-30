import Foundation
import UIKit
import zlib

public enum GpxFormat: String, CaseIterable, Identifiable {
    case joystick = "JOYSTICK"
    case anyTo = "ANYTO"
    case itools = "ITOOLS"
    case flashman = "FLASHMAN"
    case fakegps = "FAKEGPS"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .joystick: return "JoyStick (TRK 軌跡)"
        case .anyTo: return "AnyTo / iAnyGo (TRK)"
        case .itools: return "魅影版 / iTools (WPT)"
        case .flashman: return "ARflash / Flashman (WPT)"
        case .fakegps: return "Fake GPS (WPT)"
        }
    }

    public var suffix: String {
        switch self {
        case .joystick: return "_JoyStick"
        case .anyTo: return "_AnyTo"
        case .itools: return "_iTools"
        case .flashman: return "_Flashman"
        case .fakegps: return "_FakeGPS"
        }
    }

    public var isTrack: Bool {
        switch self {
        case .joystick, .anyTo: return true
        case .itools, .flashman, .fakegps: return false
        }
    }
}

public struct GofileUploadResponse {
    public let downloadPage: String
    public let parentFolder: String
    public let guestToken: String?

    public init(downloadPage: String, parentFolder: String, guestToken: String?) {
        self.downloadPage = downloadPage
        self.parentFolder = parentFolder
        self.guestToken = guestToken
    }
}

// MARK: - 純 Swift 輕量標準 ZIP 壓縮產生器 (零第三方依賴)
public struct ZipEntryItem {
    public let name: String
    public let data: Data

    public init(name: String, data: Data) {
        self.name = name
        self.data = data
    }
}

public final class SimpleZipWriter {
    public static func createZip(entries: [ZipEntryItem]) -> Data {
        var body = Data()
        var centralDirectory = Data()

        // 2026-10-18 12:00:00 DOS 時間
        let dosTime: UInt16 = (12 << 11) | (0 << 5) | (0 >> 1)
        let dosDate: UInt16 = ((2026 - 1980) << 9) | (10 << 5) | 18

        for entry in entries {
            let offset = UInt32(body.count)
            let nameBytes = entry.name.data(using: .utf8) ?? Data()
            let nameLength = UInt16(nameBytes.count)
            let uncompSize = UInt32(entry.data.count)

            let crc: UInt32 = entry.data.withUnsafeBytes { rawBuffer in
                guard let base = rawBuffer.baseAddress?.assumingMemoryBound(to: Bytef.self) else { return 0 }
                return UInt32(crc32(0, base, uInt(entry.data.count)))
            }

            // 1. Local File Header
            var local = Data()
            local.append(contentsOf: [0x50, 0x4b, 0x03, 0x04]) // PK\x03\x04
            local.append(contentsOf: withUnsafeBytes(of: UInt16(20).littleEndian) { Array($0) })
            local.append(contentsOf: withUnsafeBytes(of: UInt16(0).littleEndian) { Array($0) })
            local.append(contentsOf: withUnsafeBytes(of: UInt16(0).littleEndian) { Array($0) }) // Store
            local.append(contentsOf: withUnsafeBytes(of: dosTime.littleEndian) { Array($0) })
            local.append(contentsOf: withUnsafeBytes(of: dosDate.littleEndian) { Array($0) })
            local.append(contentsOf: withUnsafeBytes(of: crc.littleEndian) { Array($0) })
            local.append(contentsOf: withUnsafeBytes(of: uncompSize.littleEndian) { Array($0) })
            local.append(contentsOf: withUnsafeBytes(of: uncompSize.littleEndian) { Array($0) })
            local.append(contentsOf: withUnsafeBytes(of: nameLength.littleEndian) { Array($0) })
            local.append(contentsOf: withUnsafeBytes(of: UInt16(0).littleEndian) { Array($0) })
            local.append(nameBytes)

            body.append(local)
            body.append(entry.data)

            // 2. Central Directory Header
            var cd = Data()
            cd.append(contentsOf: [0x50, 0x4b, 0x01, 0x02]) // PK\x01\x02
            cd.append(contentsOf: withUnsafeBytes(of: UInt16(20).littleEndian) { Array($0) })
            cd.append(contentsOf: withUnsafeBytes(of: UInt16(20).littleEndian) { Array($0) })
            cd.append(contentsOf: withUnsafeBytes(of: UInt16(0).littleEndian) { Array($0) })
            cd.append(contentsOf: withUnsafeBytes(of: UInt16(0).littleEndian) { Array($0) })
            cd.append(contentsOf: withUnsafeBytes(of: dosTime.littleEndian) { Array($0) })
            cd.append(contentsOf: withUnsafeBytes(of: dosDate.littleEndian) { Array($0) })
            cd.append(contentsOf: withUnsafeBytes(of: crc.littleEndian) { Array($0) })
            cd.append(contentsOf: withUnsafeBytes(of: uncompSize.littleEndian) { Array($0) })
            cd.append(contentsOf: withUnsafeBytes(of: uncompSize.littleEndian) { Array($0) })
            cd.append(contentsOf: withUnsafeBytes(of: nameLength.littleEndian) { Array($0) })
            cd.append(contentsOf: withUnsafeBytes(of: UInt16(0).littleEndian) { Array($0) })
            cd.append(contentsOf: withUnsafeBytes(of: UInt16(0).littleEndian) { Array($0) })
            cd.append(contentsOf: withUnsafeBytes(of: UInt16(0).littleEndian) { Array($0) })
            cd.append(contentsOf: withUnsafeBytes(of: UInt16(0).littleEndian) { Array($0) })
            cd.append(contentsOf: withUnsafeBytes(of: UInt32(0).littleEndian) { Array($0) })
            cd.append(contentsOf: withUnsafeBytes(of: offset.littleEndian) { Array($0) })
            cd.append(nameBytes)

            centralDirectory.append(cd)
        }

        let cdOffset = UInt32(body.count)
        let cdSize = UInt32(centralDirectory.count)
        let entryCount = UInt16(entries.count)

        // 3. End of Central Directory (EOCD)
        var eocd = Data()
        eocd.append(contentsOf: [0x50, 0x4b, 0x05, 0x06]) // PK\x05\x06
        eocd.append(contentsOf: withUnsafeBytes(of: UInt16(0).littleEndian) { Array($0) })
        eocd.append(contentsOf: withUnsafeBytes(of: UInt16(0).littleEndian) { Array($0) })
        eocd.append(contentsOf: withUnsafeBytes(of: entryCount.littleEndian) { Array($0) })
        eocd.append(contentsOf: withUnsafeBytes(of: entryCount.littleEndian) { Array($0) })
        eocd.append(contentsOf: withUnsafeBytes(of: cdSize.littleEndian) { Array($0) })
        eocd.append(contentsOf: withUnsafeBytes(of: cdOffset.littleEndian) { Array($0) })
        eocd.append(contentsOf: withUnsafeBytes(of: UInt16(0).littleEndian) { Array($0) })

        var res = Data()
        res.append(body)
        res.append(centralDirectory)
        res.append(eocd)
        return res
    }
}

public final class RouteShareManager {

    // MARK: - GPX XML 產生器
    public static func generateGpx(points: [RouteNode], format: GpxFormat, routeName: String) -> String {
        let cleanName = escapeXml(routeName)
        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="AutoFarm-iOS" xmlns="http://www.topografix.com/GPX/1/1">
          <metadata>
            <name>\(cleanName)\(format.suffix)</name>
          </metadata>

        """

        let sdf = DateFormatter()
        sdf.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        sdf.timeZone = TimeZone(secondsFromGMT: 0)
        let baseTime = Date()

        if format.isTrack {
            xml += """
              <trk>
                <name>\(cleanName) (\(format.id))</name>
                <trkseg>

            """
            for (i, pt) in points.enumerated() {
                let timeStr = sdf.string(from: baseTime.addingTimeInterval(Double(i) * 3.0))
                xml += """
                      <trkpt lat="\(String(format: "%.7f", pt.lat))" lon="\(String(format: "%.7f", pt.lng))">
                        <time>\(timeStr)</time>
                      </trkpt>

                """
            }
            xml += """
                </trkseg>
              </trk>
            </gpx>
            """
        } else {
            for (i, pt) in points.enumerated() {
                let nodeName = pt.label != nil && !pt.label!.isEmpty ? escapeXml(pt.label!) : "P\(i + 1)"
                xml += "  <wpt lat=\"\(String(format: "%.7f", pt.lat))\" lon=\"\(String(format: "%.7f", pt.lng))\"><name>\(nodeName)</name></wpt>\n"
            }
            xml += "</gpx>"
        }
        return xml
    }

    // MARK: - 全格式 ZIP 懶人包產生
    public static func generateAllFormatsZip(points: [RouteNode], routeName: String, originalJson: String = "") -> Data {
        var entries: [ZipEntryItem] = []

        for fmt in GpxFormat.allCases {
            let gpxText = generateGpx(points: points, format: fmt, routeName: routeName)
            if let data = gpxText.data(using: .utf8) {
                entries.append(ZipEntryItem(name: "\(routeName)\(fmt.suffix).gpx", data: data))
            }
        }

        // 附帶 AutoFarm 原生 route.json 格式
        let jsonContent: String
        if !originalJson.isEmpty {
            jsonContent = originalJson
        } else {
            let simpleNodes = points.map { ["lat": $0.lat, "lng": $0.lng, "label": $0.label ?? ""] }
            if let jd = try? JSONSerialization.data(withJSONObject: simpleNodes, options: .prettyPrinted),
               let js = String(data: jd, encoding: .utf8) {
                jsonContent = js
            } else {
                jsonContent = "[]"
            }
        }
        if let jData = jsonContent.data(using: .utf8) {
            entries.append(ZipEntryItem(name: "\(routeName).route.json", data: jData))
        }

        return SimpleZipWriter.createZip(entries: entries)
    }

    // MARK: - 系統原生檔案分享面板
    public static func shareFile(fileURL: URL, from viewController: UIViewController? = nil) {
        let activityVC = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
        let presenter = viewController ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?
            .rootViewController

        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = presenter?.view
            popover.sourceRect = CGRect(x: UIScreen.main.bounds.midX, y: UIScreen.main.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        presenter?.present(activityVC, animated: true)
    }

    public static func shareItems(_ items: [Any], from viewController: UIViewController? = nil) {
        let activityVC = UIActivityViewController(activityItems: items, applicationActivities: nil)
        let presenter = viewController ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?
            .rootViewController

        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = presenter?.view
            popover.sourceRect = CGRect(x: UIScreen.main.bounds.midX, y: UIScreen.main.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        presenter?.present(activityVC, animated: true)
    }

    public static func shareZipFile(data: Data, routeName: String) {
        let cleanName = routeName.replacingOccurrences(of: ".zip", with: "")
        let fileName = "\(cleanName)_全格式懶人包.zip"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try data.write(to: tempURL)
            shareFile(fileURL: tempURL)
        } catch {
            print("Failed to save zip file: \(error)")
        }
    }

    // MARK: - Gofile 雲端上傳 (支援 Account Token、FolderId 與訪客上傳)
    public static func uploadToGofile(
        fileName: String,
        fileData: Data,
        token: String? = nil,
        folderId: String? = nil,
        onProgress: ((String) -> Void)? = nil
    ) async throws -> GofileUploadResponse {
        onProgress?("正在連線 Gofile 伺服器...")

        let boundary = "Boundary\(Int(Date().timeIntervalSince1970 * 1000))\(Int.random(in: 1000...9999))"
        guard let url = URL(string: "https://upload.gofile.io/uploadFile") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 45.0
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")

        let cleanToken = token?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let cleanToken = cleanToken, !cleanToken.isEmpty {
            request.setValue("Bearer \(cleanToken)", forHTTPHeaderField: "Authorization")
        }

        onProgress?("正在上傳 \(fileName)...")

        var body = Data()
        if let cleanToken = cleanToken, !cleanToken.isEmpty {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"token\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(cleanToken)\r\n".data(using: .utf8)!)
        }

        let cleanFolderId = folderId?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let cleanFolderId = cleanFolderId, !cleanFolderId.isEmpty {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"folderId\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(cleanFolderId)\r\n".data(using: .utf8)!)
        }

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        let (data, response) = try await URLSession.shared.upload(for: request, from: body)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "Gofile", code: -1, userInfo: [NSLocalizedDescriptionKey: "伺服器無回應"])
        }

        guard let respStr = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "Gofile", code: -2, userInfo: [NSLocalizedDescriptionKey: "無法解析回應資料"])
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            if respStr.contains("error-token") || respStr.contains("error-query") {
                throw NSError(domain: "Gofile", code: -3, userInfo: [NSLocalizedDescriptionKey: "Gofile Token 無效或過期，請確認 Token 或留空匿名上傳"])
            }
            throw NSError(domain: "Gofile", code: -4, userInfo: [NSLocalizedDescriptionKey: "伺服器回應異常 (\(httpResponse.statusCode)): \(respStr.prefix(100))"])
        }

        let status = json["status"] as? String ?? ""
        if status == "ok", let dataObj = json["data"] as? [String: Any] {
            let downloadPage = dataObj["downloadPage"] as? String ?? ""
            let parentFolder = dataObj["parentFolder"] as? String ?? ""
            let guestToken = dataObj["guestToken"] as? String
            return GofileUploadResponse(downloadPage: downloadPage, parentFolder: parentFolder, guestToken: guestToken)
        } else if status == "error-auth" || status == "error-token" {
            throw NSError(domain: "Gofile", code: -5, userInfo: [NSLocalizedDescriptionKey: "Token 無效，請確認 Gofile Token 正確性，或留空以訪客身份上傳"])
        } else {
            throw NSError(domain: "Gofile", code: -6, userInfo: [NSLocalizedDescriptionKey: "Gofile 回報錯誤: \(status)"])
        }
    }

    // MARK: - 幾何線段垂足碰撞公式
    public static func getSegmentDistance(latA: Double, lonA: Double, latB: Double, lonB: Double, latC: Double, lonC: Double) -> Double {
        let r = 6378137.0
        let latMid = ((latA + latB) / 2.0) * .pi / 180.0
        let dxB = (lonB - lonA) * .pi / 180.0 * cos(latMid) * r
        let dyB = (latB - latA) * .pi / 180.0 * r
        let dxC = (lonC - lonA) * .pi / 180.0 * cos(latMid) * r
        let dyC = (latC - latA) * .pi / 180.0 * r
        let l2 = dxB * dxB + dyB * dyB
        if l2 == 0.0 { return EngineMath.getDistance(lat1: latA, lon1: lonA, lat2: latC, lon2: lonC) }
        let t = max(0.0, min(1.0, (dxC * dxB + dyC * dyB) / l2))
        return hypot(dxC - t * dxB, dyC - t * dyB)
    }

    // MARK: - 圖論節點與資料結構 (100% 移植自 Android RouteShareUtils)
    final class InternalNode {
        let lat: Double
        let lon: Double
        var penalty: Int
        var id: Int
        var circleIdx: Int

        init(lat: Double, lon: Double, penalty: Int = 0, id: Int = 0, circleIdx: Int = 0) {
            self.lat = lat
            self.lon = lon
            self.penalty = penalty
            self.id = id
            self.circleIdx = circleIdx
        }
    }

    struct Edge {
        let to: Int
        let weight: Double
        let edgeV: Int
    }

    struct HeapNode: Comparable {
        let id: Int
        let d: Double

        static func < (lhs: HeapNode, rhs: HeapNode) -> Bool {
            return lhs.d < rhs.d
        }
    }

    final class BinaryMinHeap<T: Comparable> {
        private var elements: [T] = []

        var isEmpty: Bool { elements.isEmpty }
        var count: Int { elements.count }

        func push(_ item: T) {
            elements.append(item)
            siftUp(elements.count - 1)
        }

        func pop() -> T? {
            guard !elements.isEmpty else { return nil }
            if elements.count == 1 { return elements.removeLast() }
            let root = elements[0]
            elements[0] = elements.removeLast()
            siftDown(0)
            return root
        }

        private func siftUp(_ index: Int) {
            var child = index
            while child > 0 {
                let parent = (child - 1) / 2
                if elements[child] < elements[parent] {
                    elements.swapAt(child, parent)
                    child = parent
                } else {
                    break
                }
            }
        }

        private func siftDown(_ index: Int) {
            var parent = index
            let count = elements.count
            while true {
                let left = 2 * parent + 1
                let right = 2 * parent + 2
                var candidate = parent

                if left < count && elements[left] < elements[candidate] {
                    candidate = left
                }
                if right < count && elements[right] < elements[candidate] {
                    candidate = right
                }
                if candidate != parent {
                    elements.swapAt(parent, candidate)
                    parent = candidate
                } else {
                    break
                }
            }
        }
    }

    final class SpatialGrid {
        let cellSize: Double
        var cells: [String: [InternalNode]] = [:]
        var allPoints: [InternalNode] = []

        init(cellSize: Double = 0.001) {
            self.cellSize = cellSize
        }

        func insert(_ p: InternalNode) {
            allPoints.append(p)
            let x = Int(floor(p.lat / cellSize))
            let y = Int(floor(p.lon / cellSize))
            let key = "\(x),\(y)"
            cells[key, default: []].append(p)
        }

        func getPointsInBounds(minLat: Double, maxLat: Double, minLon: Double, maxLon: Double) -> [InternalNode] {
            let minX = Int(floor(minLat / cellSize))
            let maxX = Int(floor(maxLat / cellSize))
            let minY = Int(floor(minLon / cellSize))
            let maxY = Int(floor(maxLon / cellSize))
            let area = (maxX - minX + 1) * (maxY - minY + 1)

            if area > 100 || area < 0 {
                return allPoints.filter { $0.lat >= minLat && $0.lat <= maxLat && $0.lon >= minLon && $0.lon <= maxLon }
            }

            var result: [InternalNode] = []
            for x in minX...maxX {
                for y in minY...maxY {
                    if let bucket = cells["\(x),\(y)"] {
                        result.append(contentsOf: bucket)
                    }
                }
            }
            return result
        }
    }

    // MARK: - 2-opt 最短巡迴拓撲排序
    private static func reorderPoints(points: [RouteNode]) -> [RouteNode] {
        let n = points.count
        guard n > 2 else { return points }

        var visited = Array(repeating: false, count: n)
        var path: [RouteNode] = []
        var currentIdx = 0
        visited[0] = true
        path.append(points[0])

        for _ in 1..<n {
            var minDist = Double.infinity
            var bestIdx = -1
            let cur = points[currentIdx]

            for i in 0..<n {
                if !visited[i] {
                    let d = EngineMath.getDistance(lat1: cur.lat, lon1: cur.lng, lat2: points[i].lat, lon2: points[i].lng)
                    if d < minDist {
                        minDist = d
                        bestIdx = i
                    }
                }
            }

            if bestIdx != -1 {
                visited[bestIdx] = true
                path.append(points[bestIdx])
                currentIdx = bestIdx
            }
        }

        var improved = true
        var iterations = 0
        let maxIters = n > 300 ? 2 : 5
        while improved && iterations < maxIters {
            improved = false
            iterations += 1
            for i in 0..<(n - 2) {
                let windowEnd = min(n - 1, i + 50)
                if (i + 2) >= windowEnd { continue }
                for j in (i + 2)..<windowEnd {
                    let d1 = EngineMath.getDistance(lat1: path[i].lat, lon1: path[i].lng, lat2: path[i + 1].lat, lon2: path[i + 1].lng)
                    let d2 = EngineMath.getDistance(lat1: path[j].lat, lon1: path[j].lng, lat2: path[j + 1].lat, lon2: path[j + 1].lng)
                    let d3 = EngineMath.getDistance(lat1: path[i].lat, lon1: path[i].lng, lat2: path[j].lat, lon2: path[j].lng)
                    let d4 = EngineMath.getDistance(lat1: path[i + 1].lat, lon1: path[i + 1].lng, lat2: path[j + 1].lat, lon2: path[j + 1].lng)

                    if d1 + d2 > d3 + d4 {
                        var start = i + 1
                        var end = j
                        while start < end {
                            let temp = path[start]
                            path[start] = path[end]
                            path[end] = temp
                            start += 1
                            end -= 1
                        }
                        improved = true
                    }
                }
            }
        }
        return path
    }

    private static func generateSmartPoints(
        pts: [InternalNode],
        allowViolation: Bool,
        grid: SpatialGrid,
        onProgress: ((Float, String) -> Void)? = nil
    ) -> [RouteNode] {
        let n = pts.count
        guard n > 0 else { return [] }

        var allNodes: [InternalNode] = []
        var circleNodes: [[InternalNode]] = Array(repeating: [], count: n)
        var nodeId = 0

        // 1. 空間採樣圓周點 (每 15 度採樣一個候選點，共 24 個方位)
        for i in 0..<n {
            let center = pts[i]
            let cosLat = cos(center.lat * .pi / 180.0)
            let lonOffset = cosLat > 1e-6 ? 0.001 / cosLat : 180.0

            for a in stride(from: 0, to: 360, by: 15) {
                var testDist = 60.0 + Double.random(in: 0.0...10.0)
                var pt: (lat: Double, lng: Double) = (0.0, 0.0)
                var isSafe = true

                while testDist > 50.0 {
                    let dest = EngineMath.moveLocation(lat: center.lat, lng: center.lon, distanceMeters: testDist, bearingDegrees: Double(a))
                    pt = (dest.lat, dest.lng)
                    isSafe = true
                    let nearbyPoints = grid.getPointsInBounds(
                        minLat: pt.lat - 0.001,
                        maxLat: pt.lat + 0.001,
                        minLon: pt.lng - abs(lonOffset),
                        maxLon: pt.lng + abs(lonOffset)
                    )
                    for p2 in nearbyPoints {
                        if EngineMath.getDistance(lat1: pt.lat, lon1: pt.lng, lat2: p2.lat, lon2: p2.lon) < 50.0 {
                            isSafe = false
                            break
                        }
                    }
                    if isSafe { break }
                    testDist -= 1.0
                }

                if isSafe || allowViolation {
                    let node = InternalNode(lat: pt.lat, lon: pt.lng, penalty: isSafe ? 0 : 1, id: nodeId, circleIdx: i)
                    nodeId += 1
                    allNodes.append(node)
                    circleNodes[i].append(node)
                }
            }

            if allowViolation && circleNodes[i].isEmpty {
                let node = InternalNode(lat: center.lat, lon: center.lon, penalty: 2, id: nodeId, circleIdx: i)
                nodeId += 1
                allNodes.append(node)
                circleNodes[i].append(node)
            }
        }

        onProgress?(0.15, "建立避障路徑圖 (15%)...")

        // 2. 建立避障圖論邊緣 (Adjacency List)
        var adj: [[Edge]] = Array(repeating: [], count: allNodes.count)

        for c1 in 0..<n {
            if c1 % 3 == 0 || c1 == n - 1 {
                let p = 0.15 + (Float(c1) / Float(n)) * 0.65
                onProgress?(p, "建立避障路徑圖 (\(Int(p * 100))%)...")
            }

            let maxLayer = min(n - 1, c1 + 8)
            for u in circleNodes[c1] {
                for c2 in c1...maxLayer {
                    for v in circleNodes[c2] {
                        if c1 == c2 && u.id >= v.id { continue }
                        let maxLatRad = max(abs(u.lat), abs(v.lat)) * .pi / 180.0
                        let cosVal = max(1e-6, cos(maxLatRad))
                        let dynLonOffset = 0.0007 / cosVal
                        let minLat = min(u.lat, v.lat) - 0.0007
                        let maxLat = max(u.lat, v.lat) + 0.0007
                        let minLon = min(u.lon, v.lon) - abs(dynLonOffset)
                        let maxLon = max(u.lon, v.lon) + abs(dynLonOffset)

                        var edgeViolations = 0
                        let candidateObstacles = grid.getPointsInBounds(minLat: minLat, maxLat: maxLat, minLon: minLon, maxLon: maxLon)
                        for p in candidateObstacles {
                            if getSegmentDistance(latA: u.lat, lonA: u.lon, latB: v.lat, lonB: v.lon, latC: p.lat, lonC: p.lon) < 50.0 {
                                edgeViolations += 1
                                if edgeViolations >= 3 { break }
                            }
                        }

                        if edgeViolations == 0 || allowViolation {
                            let d = EngineMath.getDistance(lat1: u.lat, lon1: u.lon, lat2: v.lat, lon2: v.lon)
                            let weightU = d + Double(u.penalty + v.penalty + edgeViolations) * 100000.0
                            adj[u.id].append(Edge(to: v.id, weight: weightU, edgeV: edgeViolations))
                            adj[v.id].append(Edge(to: u.id, weight: weightU, edgeV: edgeViolations))
                        }
                    }
                }
            }
        }

        onProgress?(0.80, "搜尋最佳平滑繞路 (80%)...")

        // 3. 分層 Dijkstra 最短路徑搜尋
        var globalPath: [RouteNode] = []
        var startCircleIdx = -1
        for i in 0..<n {
            if !circleNodes[i].isEmpty {
                startCircleIdx = i
                break
            }
        }
        guard startCircleIdx != -1 else { return [] }

        var currId = circleNodes[startCircleIdx][0].id
        globalPath.append(RouteNode(lat: allNodes[currId].lat, lng: allNodes[currId].lon))
        var lastReachedLayer = startCircleIdx

        var dist = Array(repeating: Double.infinity, count: allNodes.count)
        var prev = Array(repeating: -1, count: allNodes.count)

        for targetLayer in (startCircleIdx + 1)..<n {
            if circleNodes[targetLayer].isEmpty { continue }
            dist = Array(repeating: Double.infinity, count: allNodes.count)
            prev = Array(repeating: -1, count: allNodes.count)
            dist[currId] = 0.0

            let pq = BinaryMinHeap<HeapNode>()
            pq.push(HeapNode(id: currId, d: 0.0))
            var foundTargetId = -1

            while let top = pq.pop() {
                if allNodes[top.id].circleIdx == targetLayer {
                    foundTargetId = top.id
                    break
                }
                if top.d > dist[top.id] { continue }

                for edge in adj[top.id] {
                    let vNode = allNodes[edge.to]
                    if vNode.circleIdx < allNodes[currId].circleIdx - 3 || vNode.circleIdx > targetLayer + 4 { continue }
                    let newDist = top.d + edge.weight
                    if newDist < dist[edge.to] {
                        dist[edge.to] = newDist
                        prev[edge.to] = top.id
                        pq.push(HeapNode(id: edge.to, d: newDist))
                    }
                }
            }

            if foundTargetId != -1 {
                var pathSegment: [RouteNode] = []
                var step = foundTargetId
                var safeSteps = allNodes.count
                while step != currId && safeSteps > 0 {
                    safeSteps -= 1
                    pathSegment.append(RouteNode(lat: allNodes[step].lat, lng: allNodes[step].lon))
                    if prev[step] < 0 || prev[step] >= allNodes.count { break }
                    step = prev[step]
                }
                pathSegment.reverse()
                globalPath.append(contentsOf: pathSegment)
                currId = foundTargetId
                lastReachedLayer = targetLayer
            } else {
                break
            }

            let p = 0.80 + (Float(targetLayer - startCircleIdx) / Float(n - startCircleIdx)) * 0.15
            onProgress?(p, "搜尋最佳平滑繞路 (\(Int(p * 100))%)...")
        }

        var lastHasNodesLayer = n - 1
        while lastHasNodesLayer >= 0 && circleNodes[lastHasNodesLayer].isEmpty {
            lastHasNodesLayer -= 1
        }

        if lastReachedLayer == lastHasNodesLayer {
            return globalPath
        }
        return []
    }

    // MARK: - gpxshare 核心收果繞路演算法 (100% 對齊安卓版 processSmartRoute，50m 核心禁區避障)
    public static func processSmartRoute(
        points: [RouteNode],
        minStep: Double = 100.0,
        maxStep: Double = 150.0,
        densify: Bool = true,
        attemptReorder: Bool = true,
        onProgress: ((Float, String) -> Void)? = nil
    ) -> [RouteNode] {
        onProgress?(0.05, "初始化空間幾何座標...")
        var pts: [InternalNode] = []
        let grid = SpatialGrid()

        for p in points {
            if p.lat.isNaN || p.lng.isNaN || p.lat.isInfinite || p.lng.isInfinite { continue }
            if p.lat < -90.0 || p.lat > 90.0 || p.lng < -180.0 || p.lng > 180.0 { continue }

            if let lastPt = pts.last {
                if EngineMath.getDistance(lat1: lastPt.lat, lon1: lastPt.lon, lat2: p.lat, lon2: p.lng) < 2.0 {
                    continue
                }
            }
            let node = InternalNode(lat: p.lat, lon: p.lng)
            pts.append(node)
            grid.insert(node)
        }

        guard !pts.isEmpty else {
            onProgress?(1.0, "路線為空")
            return []
        }

        // 嘗試 1：常規嚴格避障計算
        var resultPath = generateSmartPoints(pts: pts, allowViolation: false, grid: grid, onProgress: onProgress)

        // 嘗試 2：若找不到路徑且允許重新排序，則重新排序後再算一次
        if resultPath.isEmpty && attemptReorder {
            onProgress?(0.2, "重新規劃節點拓撲排序...")
            let reorderedNodes = reorderPoints(points: points)
            var reorderedInternal: [InternalNode] = []
            let reorderedGrid = SpatialGrid()
            for p in reorderedNodes {
                let node = InternalNode(lat: p.lat, lon: p.lng)
                reorderedInternal.append(node)
                reorderedGrid.insert(node)
            }
            resultPath = generateSmartPoints(pts: reorderedInternal, allowViolation: false, grid: reorderedGrid, onProgress: onProgress)
        }

        // 嘗試 3：若仍無解，開啟最小穿透容許 (allowViolation = true)
        if resultPath.isEmpty {
            onProgress?(0.4, "計算進入最少禁區之平滑路線...")
            resultPath = generateSmartPoints(pts: pts, allowViolation: true, grid: grid, onProgress: onProgress)
        }

        // 嘗試 4：若仍無解，重新排序後開啟最小穿透容許
        if resultPath.isEmpty && attemptReorder {
            let reorderedNodes = reorderPoints(points: points)
            var reorderedInternal: [InternalNode] = []
            let reorderedGrid = SpatialGrid()
            for p in reorderedNodes {
                let node = InternalNode(lat: p.lat, lon: p.lng)
                reorderedInternal.append(node)
                reorderedGrid.insert(node)
            }
            resultPath = generateSmartPoints(pts: reorderedInternal, allowViolation: true, grid: reorderedGrid, onProgress: onProgress)
        }

        if resultPath.isEmpty {
            resultPath = points
        }

        if densify && !resultPath.isEmpty {
            onProgress?(0.96, "正在套用隨機碎步插點...")
            resultPath = EngineMath.densifyRoute(points: resultPath, minStep: minStep, maxStep: maxStep)
        }

        onProgress?(1.0, "計算完成")
        return resultPath
    }

    private static func escapeXml(_ str: String) -> String {
        return str
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
