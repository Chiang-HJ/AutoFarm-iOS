import UIKit
import Vision

public struct MushroomOcrResult {
    public var mushroomName: String
    public var days: Int
    public var hours: Int
    public var minutes: Int
    public var seconds: Int
    public var totalMillis: Int64
    public var landmark: String
    public var rawText: String

    public init(
        mushroomName: String = "活動蘑菇",
        days: Int = 0,
        hours: Int = 0,
        minutes: Int = 0,
        seconds: Int = 0,
        totalMillis: Int64 = 0,
        landmark: String = "",
        rawText: String = ""
    ) {
        self.mushroomName = mushroomName
        self.days = days
        self.hours = hours
        self.minutes = minutes
        self.seconds = seconds
        self.totalMillis = totalMillis
        self.landmark = landmark
        self.rawText = rawText
    }
}

public struct OcrRecognizedLine {
    public let text: String
    public let boundingBox: CGRect // normalized [0, 1], lower-left origin in Vision
}

public enum MushroomOcrEngine {

    /// 使用 Apple Vision 框架對圖片進行繁體中文高精度 OCR 辨識
    public static func recognize(image: UIImage, completion: @escaping (MushroomOcrResult) -> Void) {
        guard let cgImage = image.cgImage else {
            completion(MushroomOcrResult())
            return
        }

        let request = VNRecognizeTextRequest { request, error in
            guard error == nil, let observations = request.results as? [VNRecognizedTextObservation] else {
                completion(MushroomOcrResult())
                return
            }

            var recognizedLines: [OcrRecognizedLine] = []
            var fullTextList: [String] = []

            for obs in observations {
                guard let candidate = obs.topCandidates(1).first else { continue }
                recognizedLines.append(OcrRecognizedLine(text: candidate.string, boundingBox: obs.boundingBox))
                fullTextList.append(candidate.string)
            }

            let rawText = fullTextList.joined(separator: "\n")

            // 1. 辨識蘑菇種類名稱
            let mushroomName = parseMushroomName(lines: recognizedLines, rawText: rawText)

            // 2. 辨識剩餘時間
            let timeRes = parseRemainingTime(lines: recognizedLines, rawText: rawText)

            // 3. 辨識頂部地標 (畫面高度 8% ~ 32% 處)
            let landmark = parseLandmark(lines: recognizedLines)

            let result = MushroomOcrResult(
                mushroomName: mushroomName,
                days: timeRes.days,
                hours: timeRes.hours,
                minutes: timeRes.minutes,
                seconds: timeRes.seconds,
                totalMillis: timeRes.totalMillis,
                landmark: landmark,
                rawText: rawText
            )

            completion(result)
        }

        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hant", "zh-Hans", "en-US"]
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
            } catch {
                completion(MushroomOcrResult())
            }
        }
    }

    // MARK: - 蘑菇種類解析 (1:1 對齊安卓 MushroomOcrEngine)
    private static func parseMushroomName(lines: [OcrRecognizedLine], rawText: String) -> String {
        // 先尋找明確帶有「蘑菇」或「菇」的文字行
        for line in lines {
            let t = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.contains("蘑菇") || t.contains("菇") {
                let normalized = normalizeMushroomText(t)
                if !normalized.isEmpty {
                    return normalized
                }
            }
        }

        // 若無直接包含「蘑菇」，檢查全文中是否有相關組合
        let knownElements = ["萬聖節", "活動", "水晶", "火", "水", "電", "毒", "冰", "藍", "紅", "黃", "灰", "白", "粉", "紫"]
        let knownSizes = ["巨大", "大", "一般", "小"]

        for size in knownSizes {
            for elem in knownElements {
                if rawText.contains(size) && rawText.contains(elem) {
                    return normalizeMushroomText("\(size)\(elem)")
                }
            }
        }

        for elem in knownElements {
            if rawText.contains(elem) {
                return normalizeMushroomText(elem)
            }
        }

        return "活動蘑菇"
    }

    private static func normalizeMushroomText(_ text: String) -> String {
        // 清除標點符號與特殊符號
        var clean = text.replacingOccurrences(of: "[^\\u4e00-\\u9fa5a-zA-Z0-9]", with: "", options: .regularExpression)
        if clean.hasSuffix("的") {
            clean = String(clean.dropLast())
        }

        let isHalloween = clean.contains("萬聖節")
        let isGiant = clean.contains("巨大")
        let isLarge = !isGiant && clean.contains("大")
        let isNormal = clean.contains("一般")
        let isSmall = clean.contains("小")

        if isHalloween || clean.contains("活動") {
            let sizePrefix: String
            if isGiant { sizePrefix = "巨大" }
            else if isLarge { sizePrefix = "大" }
            else if isSmall { sizePrefix = "小" }
            else if isNormal { sizePrefix = "一般" }
            else { sizePrefix = "" }

            return isHalloween ? "\(sizePrefix)活動蘑菇 (萬聖節)" : "\(sizePrefix)活動蘑菇"
        }

        // 確保以「蘑菇」結尾
        if !clean.hasSuffix("蘑菇") {
            if clean.hasSuffix("菇") {
                clean += "蘑"
            } else {
                clean += "蘑菇"
            }
        }
        return clean
    }

    // MARK: - 剩餘時間解析 (1:1 對齊安卓時間正規表達式)
    private struct RemainingTimeResult {
        var days: Int = 0
        var hours: Int = 0
        var minutes: Int = 0
        var seconds: Int = 0
        var totalMillis: Int64 = 0
    }

    private static func parseRemainingTime(lines: [OcrRecognizedLine], rawText: String) -> RemainingTimeResult {
        var candidates: [String] = []

        // 優先搜尋含有「剩下」或「剩餘」的行
        for line in lines {
            let t = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.contains("剩下") || t.contains("剩餘") {
                candidates.append(t)
            }
        }

        // 搜尋包含時間單位的行
        for line in lines {
            let t = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.contains("小時") || t.contains("日") || t.contains("天") || t.contains("分") {
                if !candidates.contains(t) {
                    candidates.append(t)
                }
            }
        }

        candidates.append(rawText)

        for candidate in candidates {
            let parsed = extractTimeFromText(candidate)
            if parsed.totalMillis > 0 {
                return parsed
            }
        }

        return RemainingTimeResult()
    }

    private static func extractTimeFromText(_ text: String) -> RemainingTimeResult {
        var days = 0
        var hours = 0
        var minutes = 0
        var seconds = 0

        // 搜尋 日/天
        if let match = firstMatch(pattern: "(\\d+)\\s*[日天]", in: text) {
            days = Int(match) ?? 0
        }

        // 搜尋 小時/時
        if let match = firstMatch(pattern: "(\\d+)\\s*(?:小時|時)", in: text) {
            hours = Int(match) ?? 0
        }

        // 搜尋 分/分鐘
        if let match = firstMatch(pattern: "(\\d+)\\s*分(?:鐘)?", in: text) {
            minutes = Int(match) ?? 0
        }

        // 搜尋 秒
        if let match = firstMatch(pattern: "(\\d+)\\s*秒", in: text) {
            seconds = Int(match) ?? 0
        }

        let totalSec = Int64(days) * 86400 + Int64(hours) * 3600 + Int64(minutes) * 60 + Int64(seconds)
        let totalMillis = totalSec * 1000

        return RemainingTimeResult(days: days, hours: hours, minutes: minutes, seconds: seconds, totalMillis: totalMillis)
    }

    private static func firstMatch(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let ns = text as NSString
        let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: ns.length))
        if let m = match, m.numberOfRanges >= 2 {
            return ns.substring(with: m.range(at: 1))
        }
        return nil
    }

    // MARK: - 頂部地標解析 (畫面高度 8% ~ 32% 處)
    private static func parseLandmark(lines: [OcrRecognizedLine]) -> String {
        // Vision 座標系：原點在左下角 (0,0)，頂部 y 接近 1.0
        // 畫面頂部 8% ~ 32% 在 Vision 中對應 y 約在 0.68 ~ 0.92
        let topLines = lines.filter { line in
            let centerY = line.boundingBox.midY
            return centerY >= 0.65 && centerY <= 0.95
        }

        let ignoreWords = [
            "蘑菇", "剩下", "剩餘", "挑戰", "戰鬥", "加入", "邀請", "隊伍",
            "等級", "力量", "返回", "關閉", "時間", "總分", "戰力"
        ]

        for line in topLines {
            let t = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.count >= 2 && !ignoreWords.contains(where: { t.contains($0) }) {
                // 排除純數字或時間
                if !t.allSatisfy({ $0.isNumber || $0 == ":" || $0.isWhitespace }) {
                    return t
                }
            }
        }

        return ""
    }
}
