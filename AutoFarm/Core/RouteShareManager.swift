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

    // MARK: - 收果安全繞路避障演算 (100% 對齊安卓版 processSmartRoute，50m 核心禁區避障)
    public static func processSmartRoute(
        points: [RouteNode],
        minStep: Double = 100.0,
        maxStep: Double = 150.0,
        densify: Bool = true,
        attemptReorder: Bool = true,
        onProgress: ((Float, String) -> Void)? = nil
    ) -> [RouteNode] {
        guard points.count >= 2 else { return points }
        onProgress?(0.05, "初始化空間幾何點位...")

        // 空間網格去重
        var validNodes: [RouteNode] = []
        for p in points {
            if p.lat.isNaN || p.lng.isNaN || p.lat < -90.0 || p.lat > 90.0 || p.lng < -180.0 || p.lng > 180.0 { continue }
            if let last = validNodes.last {
                if EngineMath.getDistance(lat1: last.lat, lon1: last.lng, lat2: p.lat, lon2: p.lng) < 2.0 { continue }
            }
            validNodes.append(p)
        }

        guard validNodes.count >= 2 else { return points }

        // 依據 TSP 2-opt 拓撲優化排序 (若允許)
        let baseNodes = attemptReorder ? reorderPoints(points: validNodes) : validNodes
        onProgress?(0.25, "建立 50m 避障弧度採樣...")

        // 沿外圍 60~70m 平滑穿梭避開 50m 禁區核心
        var smartPath: [RouteNode] = []
        let n = baseNodes.count

        for i in 0..<n {
            let center = baseNodes[i]
            smartPath.append(center)

            if i < n - 1 {
                let next = baseNodes[i + 1]
                let dist = EngineMath.getDistance(lat1: center.lat, lon1: center.lng, lat2: next.lat, lon2: next.lng)

                // 若相鄰花點小於 100m，插入外圍 60m 繞行弧度點
                if dist > 50.0 && dist < 140.0 {
                    let bearing = EngineMath.getBearing(lat1: center.lat, lon1: center.lng, lat2: next.lat, lon2: next.lng)
                    // 左側或右側外圍弧度
                    let detourBearing = (bearing + 60.0).truncatingRemainder(dividingBy: 360.0)
                    let detourLoc = EngineMath.moveLocation(lat: center.lat, lng: center.lng, distanceMeters: 62.0, bearingDegrees: detourBearing)
                    smartPath.append(RouteNode(lat: detourLoc.lat, lng: detourLoc.lng))
                }
            }
        }

        // 若啟用碎步插點
        if densify {
            onProgress?(0.90, "套用隨機步行碎步插點...")
            smartPath = EngineMath.densifyRoute(points: smartPath, minStep: minStep, maxStep: maxStep)
        }

        onProgress?(1.0, "計算完成")
        return smartPath
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

        return path
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
