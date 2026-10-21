import Foundation
import SwiftUI

public final class CertificateCountdownManager: ObservableObject {
    public static let shared = CertificateCountdownManager()

    @Published public var remainingDays: Int = 7
    @Published public var remainingHours: Int = 0
    @Published public var expirationDate: Date? = nil
    @Published public var displayString: String = "計算中..."
    @Published public var statusColor: Color = .green
    @Published public var isNearExpiration: Bool = false

    private var timer: Timer?

    private init() {
        refresh()
        // 每 15 分鐘重新計算一次倒數
        timer = Timer.scheduledTimer(withTimeInterval: 900, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    public func refresh() {
        let expDate = detectExpirationDate()
        self.expirationDate = expDate

        let now = Date()
        let diffSec = max(0, Int(expDate.timeIntervalSince(now)))

        let days = diffSec / 86400
        let hours = (diffSec % 86400) / 3600

        self.remainingDays = days
        self.remainingHours = hours

        if diffSec <= 0 {
            self.displayString = "簽名已到期 (請刷新)"
            self.statusColor = .red
            self.isNearExpiration = true
        } else if days >= 1 {
            self.displayString = "\(days) 天 \(hours) 小時"
            if days <= 2 {
                self.statusColor = .orange
                self.isNearExpiration = true
            } else {
                self.statusColor = .green
                self.isNearExpiration = false
            }
        } else {
            let minutes = (diffSec % 3600) / 60
            self.displayString = "\(hours) 小時 \(minutes) 分"
            self.statusColor = .red
            self.isNearExpiration = true
        }
    }

    private func detectExpirationDate() -> Date {
        // 1. 嘗試解析 embedded.mobileprovision 中的 ExpirationDate
        if let provPath = Bundle.main.path(forResource: "embedded", ofType: "mobileprovision"),
           let data = try? Data(contentsOf: URL(fileURLWithPath: provPath)),
           let content = String(data: data, encoding: .isoLatin1) {
            
            if let startRange = content.range(of: "<key>ExpirationDate</key>"),
               let dateStart = content.range(of: "<date>", range: startRange.upperBound..<content.endIndex),
               let dateEnd = content.range(of: "</date>", range: dateStart.upperBound..<content.endIndex) {
                
                let dateStr = String(content[dateStart.upperBound..<dateEnd.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                
                let isoFormatter = ISO8601DateFormatter()
                if let d = isoFormatter.date(from: dateStr) {
                    return d
                }
            }
        }

        // 2. 備用方案：以 App Bundle 建立/安裝時間 + 7 天作為免費開發者憑證基準
        if let attrs = try? FileManager.default.attributesOfItem(atPath: Bundle.main.bundlePath),
           let createDate = attrs[.creationDate] as? Date {
            return createDate.addingTimeInterval(7 * 86400)
        }

        // 預設 7 天
        return Date().addingTimeInterval(7 * 86400)
    }
}
