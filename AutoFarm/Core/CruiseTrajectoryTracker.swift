import Foundation
import CoreLocation

public struct TrajectoryPoint: Codable {
    public let timestamp: Int64
    public let lat: Double
    public let lng: Double
    public let speedKmh: Double
    public let distanceDeltaMeters: Double
    public let cumulativeDistMeters: Double
}

public final class CruiseTrajectoryTracker {
    public static let shared = CruiseTrajectoryTracker()

    private let maxHistoryMs: Int64 = 45_000 // 保留 45 秒航跡
    private let defaultBackDistanceMeters: Double = 1513.0

    // 巡航速度 (km/h) 對應回推秒數對照表 (完全對齊安卓端校準數值)
    private let speedDelayTable: [(Double, Double)] = [
        (10.0, 0.5),
        (20.0, 0.8),
        (50.0, 1.8),
        (100.0, 3.8),
        (200.0, 7.0),
        (300.0, 10.5),
        (400.0, 13.6),
        (450.0, 12.1),
        (500.0, 10.9),
        (550.0, 9.9),
        (600.0, 9.1),
        (650.0, 8.4),
        (700.0, 7.8),
        (750.0, 7.3),
        (800.0, 6.8)
    ]

    public var customDelaySeconds: Double? = nil
    private var history: [TrajectoryPoint] = []
    private var totalDistanceTraveled: Double = 0.0
    private let queue = DispatchQueue(label: "com.autofarm.trajectory_tracker")

    private init() {}

    public func clear() {
        queue.sync {
            history.removeAll()
            totalDistanceTraveled = 0.0
        }
    }

    /// 根據巡航速度 (km/h) 查表取得精確回推秒數（支援區間線性插值）
    public func getLookupDelaySeconds(speedKmh: Double) -> Double {
        if let custom = customDelaySeconds {
            return min(max(custom, 0.0), 30.0)
        }
        let safeSpeed = max(speedKmh, 5.0)
        if safeSpeed <= speedDelayTable.first!.0 {
            return speedDelayTable.first!.1
        }
        if safeSpeed >= speedDelayTable.last!.0 {
            let n = speedDelayTable.count
            let (sN1, tN1) = speedDelayTable[n - 2]
            let (sN, tN) = speedDelayTable[n - 1]
            let slope = (tN - tN1) / (sN - sN1)
            return min(max(tN + (safeSpeed - sN) * slope, 1.0), 30.0)
        }
        for i in 0..<(speedDelayTable.count - 1) {
            let (sp1, t1) = speedDelayTable[i]
            let (sp2, t2) = speedDelayTable[i + 1]
            if safeSpeed >= sp1 && safeSpeed <= sp2 {
                let frac = (safeSpeed - sp1) / (sp2 - sp1)
                return t1 + frac * (t2 - t1)
            }
        }
        return 6.8
    }

    /// 記錄目前航跡點
    public func record(lat: Double, lng: Double, speedKmh: Double) {
        queue.sync {
            let now = Int64(Date().timeIntervalSince1970 * 1000)
            let last = history.last

            let dist: Double
            if let last = last {
                dist = EngineMath.getDistance(lat1: last.lat, lon1: last.lng, lat2: lat, lon2: lng)
            } else {
                dist = 0.0
            }

            // 若單次跳躍超過 500 公尺（瞬移），清空舊軌跡重新計算，避免回推落入瞬移半空中
            if dist > 500.0 {
                history.removeAll()
                totalDistanceTraveled = 0.0
            } else {
                totalDistanceTraveled += dist
            }

            let pt = TrajectoryPoint(
                timestamp: now,
                lat: lat,
                lng: lng,
                speedKmh: speedKmh,
                distanceDeltaMeters: dist,
                cumulativeDistMeters: totalDistanceTraveled
            )
            history.append(pt)

            // 修剪過期航跡
            let cutoff = now - maxHistoryMs
            while let first = history.first, first.timestamp < cutoff {
                history.removeFirst()
            }
        }
    }

    /// 依速度與延遲回推蘑菇生成時的真實經緯度
    public func getBackCalculatedLocation(
        currentLat: Double,
        currentLng: Double,
        currentSpeedKmh: Double = 800.0
    ) -> (lat: Double, lng: Double) {
        return queue.sync {
            guard !history.isEmpty else {
                return (currentLat, currentLng)
            }

            let now = Int64(Date().timeIntervalSince1970 * 1000)
            let delaySec = getLookupDelaySeconds(speedKmh: currentSpeedKmh)
            let targetTimestamp = now - Int64(delaySec * 1000.0)

            for i in stride(from: history.count - 1, through: 0, by: -1) {
                let pt = history[i]
                if pt.timestamp <= targetTimestamp {
                    let nextPt = (i + 1 < history.count) ? history[i + 1] : pt
                    let dt = max(Double(nextPt.timestamp - pt.timestamp), 1.0)
                    let frac = min(max(Double(targetTimestamp - pt.timestamp) / dt, 0.0), 1.0)
                    let interpLat = pt.lat + (nextPt.lat - pt.lat) * frac
                    let interpLng = pt.lng + (nextPt.lng - pt.lng) * frac
                    return (interpLat, interpLng)
                }
            }

            if let first = history.first {
                return (first.lat, first.lng)
            }
            return (currentLat, currentLng)
        }
    }
}
