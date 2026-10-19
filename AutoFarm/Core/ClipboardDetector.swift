import Foundation
import UIKit
import Combine
import CoreLocation

public struct DetectedClipboardItem: Identifiable, Equatable {
    public let id = UUID()
    public let lat: Double
    public let lng: Double
    public let label: String?
    public let rawText: String
    public let timestamp: Date = Date()
}

public final class ClipboardDetector: ObservableObject {
    public static let shared = ClipboardDetector()

    @Published public var activeItem: DetectedClipboardItem? = nil
    @Published public var isDetectionEnabled: Bool = true

    private var lastHandledText: String? = nil
    private var lastIgnoredText: String? = nil

    private init() {
        self.isDetectionEnabled = UserDefaults.standard.object(forKey: "AutoFarm_ClipboardDetection") as? Bool ?? true
    }

    public func setEnabled(_ enabled: Bool) {
        self.isDetectionEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "AutoFarm_ClipboardDetection")
        if !enabled {
            self.activeItem = nil
        }
    }

    /// 在 App 啟動或由背景返回前景時主動觸發檢測
    public func checkClipboardOnForeground() {
        guard isDetectionEnabled else { return }
        guard UIPasteboard.general.hasStrings else { return }
        guard let text = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return }

        // 避免重複提示同一個字串
        if text == lastHandledText || text == lastIgnoredText {
            return
        }

        if let item = parseClipboardText(text) {
            DispatchQueue.main.async {
                self.activeItem = item
            }
        }
    }

    /// 手動忽略目前偵測到的項目
    public func dismiss() {
        if let current = activeItem {
            lastIgnoredText = current.rawText
        }
        self.activeItem = nil
    }

    /// 標記為已處理（例如點擊瞬移、儲存）
    public func markHandled() {
        if let current = activeItem {
            lastHandledText = current.rawText
        }
        self.activeItem = nil
    }

    /// 解析剪貼簿內容：支援純數字經緯度、Google Maps 連結、Apple Maps 連結與標籤
    public func parseClipboardText(_ text: String) -> DetectedClipboardItem? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var candidateLat: Double? = nil
        var candidateLng: Double? = nil
        var candidateLabel: String? = nil

        // 1. 萃取方括號或括弧內的標籤 (例如：[大安公園] 25.033, 121.564)
        let bracketPattern = "[【\\[\\(]([^】\\]\\)]+)[】\\]\\)]"
        if let bracketRegex = try? NSRegularExpression(pattern: bracketPattern) {
            let ns = trimmed as NSString
            if let match = bracketRegex.firstMatch(in: trimmed, range: NSRange(location: 0, length: ns.length)) {
                candidateLabel = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // 2. 檢測 Google Maps / Apple Maps 網址參數
        if trimmed.contains("google.com/maps") || trimmed.contains("maps.app.goo.gl") || trimmed.contains("goo.gl/maps") || trimmed.contains("maps.apple.com") {
            let queryPattern = "[?&](?:q|query|ll|center|daddr)=([^&#]+)"
            if let queryRegex = try? NSRegularExpression(pattern: queryPattern, options: .caseInsensitive) {
                let ns = trimmed as NSString
                if let match = queryRegex.firstMatch(in: trimmed, range: NSRange(location: 0, length: ns.length)) {
                    let paramVal = ns.substring(with: match.range(at: 1))
                    if let decoded = paramVal.removingPercentEncoding {
                        if let coords = extractLatLng(from: decoded) {
                            candidateLat = coords.lat
                            candidateLng = coords.lng
                        }
                    }
                }
            }

            // 檢查路徑 @lat,lng 格式 (例如 google.com/maps/@25.033964,121.564468,17z)
            if candidateLat == nil {
                let atPattern = "@(-?\\d{1,3}\\.\\d+),(-?\\d{1,3}\\.\\d+)"
                if let atRegex = try? NSRegularExpression(pattern: atPattern) {
                    let ns = trimmed as NSString
                    if let match = atRegex.firstMatch(in: trimmed, range: NSRange(location: 0, length: ns.length)) {
                        let s1 = ns.substring(with: match.range(at: 1))
                        let s2 = ns.substring(with: match.range(at: 2))
                        if let v1 = Double(s1), let v2 = Double(s2) {
                            let norm = normalizeLatLng(first: v1, second: v2)
                            candidateLat = norm.lat
                            candidateLng = norm.lng
                        }
                    }
                }
            }
        }

        // 3. 一般文字正規表達式比對 (支援換行、中文前綴、逗號或空格分隔)
        if candidateLat == nil || candidateLng == nil {
            if let coords = extractLatLng(from: trimmed) {
                candidateLat = coords.lat
                candidateLng = coords.lng
            }
        }

        guard let lat = candidateLat, let lng = candidateLng else { return nil }

        // 清理標籤
        let finalLabel = candidateLabel ?? cleanLabelText(trimmed)

        return DetectedClipboardItem(
            lat: lat,
            lng: lng,
            label: finalLabel.isEmpty ? nil : finalLabel,
            rawText: trimmed
        )
    }

    private func extractLatLng(from text: String) -> (lat: Double, lng: Double)? {
        let pattern = "(-?\\d{1,3}\\.\\d{2,})[^0-9.-]+?(-?\\d{1,3}\\.\\d{2,})"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }

        if match.numberOfRanges >= 3 {
            let s1 = ns.substring(with: match.range(at: 1))
            let s2 = ns.substring(with: match.range(at: 2))
            if let v1 = Double(s1), let v2 = Double(s2) {
                return normalizeLatLng(first: v1, second: v2)
            }
        }
        return nil
    }

    private func normalizeLatLng(first: Double, second: Double) -> (lat: Double, lng: Double) {
        if abs(first) > 90.0 && abs(second) <= 90.0 {
            return (second, first)
        }
        if first > 70.0 && first <= 180.0 && second >= -90.0 && second <= 50.0 {
            return (second, first)
        }
        return (first, second)
    }

    private func cleanLabelText(_ text: String) -> String {
        let firstLine = text.components(separatedBy: .newlines).first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? ""
        var cleaned = firstLine
        let prefixes = ["座標:", "座標：", "位置:", "位置：", "地點:", "地點：", "經緯度:", "經緯度：", "coords:", "location:", "gps:", "http://", "https://"]
        for p in prefixes {
            if let range = cleaned.range(of: p, options: .caseInsensitive) {
                cleaned = String(cleaned[range.upperBound...])
            }
        }
        cleaned = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: " ,:：-|、\t"))
        if let idx = cleaned.range(of: " ")?.lowerBound {
            let candidate = String(cleaned[..<idx]).trimmingCharacters(in: .whitespaces)
            if Double(candidate) == nil && !candidate.contains(".") {
                return candidate
            }
        }
        return ""
    }
}
