import Foundation
import UIKit

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

public final class RouteShareManager {

    /// 產生單一格式 GPX XML 字串
    public static func generateGpx(points: [RouteNode], format: GpxFormat, routeName: String) -> String {
        let cleanName = escapeXml(routeName)
        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="AutoFarm-iOS" xmlns="http://www.topografix.com/GPX/1/1">
          <metadata>
            <name>\(cleanName)\(format.suffix)</name>
          </metadata>

        """

        if format.isTrack {
            xml += """
              <trk>
                <name>\(cleanName)</name>
                <trkseg>

            """
            for pt in points {
                xml += "      <trkpt lat=\"\(String(format: "%.6f", pt.lat))\" lon=\"\(String(format: "%.6f", pt.lng))\"></trkpt>\n"
            }
            xml += """
                </trkseg>
              </trk>
            </gpx>
            """
        } else {
            for (i, pt) in points.enumerated() {
                let nodeName = pt.label != nil ? escapeXml(pt.label!) : "Point \(i + 1)"
                xml += "  <wpt lat=\"\(String(format: "%.6f", pt.lat))\" lon=\"\(String(format: "%.6f", pt.lng))\"><name>\(nodeName)</name></wpt>\n"
            }
            xml += "</gpx>"
        }
        return xml
    }

    /// 呼叫系統原生分享 (UIActivityViewController)
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

    /// 上傳至 Gofile 雲端並獲取公開分享短網址
    public static func uploadToGofile(
        fileName: String,
        fileData: Data,
        token: String? = nil
    ) async throws -> String {
        let boundary = "Boundary\(Int(Date().timeIntervalSince1970 * 1000))\(Int.random(in: 1000...9999))"
        guard let url = URL(string: "https://upload.gofile.io/uploadFile") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        if let token = token, !token.trimmingCharacters(in: .whitespaces).isEmpty {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"token\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(token.trimmingCharacters(in: .whitespaces))\r\n".data(using: .utf8)!)
        }

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        let (data, response) = try await URLSession.shared.upload(for: request, from: body)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw NSError(domain: "GofileUpload", code: -1, userInfo: [NSLocalizedDescriptionKey: "Gofile 伺服器回應異常"])
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = json["status"] as? String, status == "ok",
              let dataObj = json["data"] as? [String: Any],
              let downloadPage = dataObj["downloadPage"] as? String else {
            throw NSError(domain: "GofileUpload", code: -2, userInfo: [NSLocalizedDescriptionKey: "Gofile 回傳格式無效"])
        }

        return downloadPage
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
