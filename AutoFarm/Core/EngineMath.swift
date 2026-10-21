import Foundation
import CoreLocation

public enum EngineMath {
    public static let earthRadiusMeters = 6378137.0

    /// 計算兩經緯度點的地球大圓距離 (公尺)
    public static func getDistance(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let dLat = (lat2 - lat1) * .pi / 180.0
        let dLon = (lon2 - lon1) * .pi / 180.0
        let rLat1 = lat1 * .pi / 180.0
        let rLat2 = lat2 * .pi / 180.0

        let a = sin(dLat / 2.0) * sin(dLat / 2.0) +
                cos(rLat1) * cos(rLat2) * sin(dLon / 2.0) * sin(dLon / 2.0)
        let c = 2.0 * atan2(sqrt(a), sqrt(1.0 - a))
        return earthRadiusMeters * c
    }

    /// haversineDistance 別名，完全等同於 getDistance
    public static func haversineDistance(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        return getDistance(lat1: lat1, lon1: lon1, lat2: lat2, lon2: lon2)
    }

    /// 計算起始點指向終點之方位角 (度數 0 ~ 360)
    public static func getBearing(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let rLat1 = lat1 * .pi / 180.0
        let rLat2 = lat2 * .pi / 180.0
        let dLon = (lon2 - lon1) * .pi / 180.0

        let y = sin(dLon) * cos(rLat2)
        let x = cos(rLat1) * sin(rLat2) - sin(rLat1) * cos(rLat2) * cos(dLon)
        let bearingRad = atan2(y, x)
        return (bearingRad * 180.0 / .pi + 360.0).truncatingRemainder(dividingBy: 360.0)
    }

    /// 給定起點座標、距離(公尺)與方位角(度數)，推算目標經緯度
    public static func moveLocation(lat: Double, lng: Double, distanceMeters: Double, bearingDegrees: Double) -> (lat: Double, lng: Double) {
        let distRatio = distanceMeters / earthRadiusMeters
        let bearingRad = bearingDegrees * .pi / 180.0
        let rLat = lat * .pi / 180.0
        let rLng = lng * .pi / 180.0

        let targetLatRad = asin(sin(rLat) * cos(distRatio) + cos(rLat) * sin(distRatio) * cos(bearingRad))
        let targetLngRad = rLng + atan2(
            sin(bearingRad) * sin(distRatio) * cos(rLat),
            cos(distRatio) - sin(rLat) * sin(targetLatRad)
        )

        return (
            lat: targetLatRad * 180.0 / .pi,
            lng: targetLngRad * 180.0 / .pi
        )
    }

    /// 寶可夢短距離瞬移冷卻時間表 (秒)，上限 7 秒
    public static func calculateCooldownSeconds(distanceMeters: Double) -> Int {
        switch distanceMeters {
        case ...20.0:
            return 0
        case ...50.0:
            return 1
        case ...100.0:
            return 2
        case ...150.0:
            return 3
        case ...200.0:
            return 4
        case ...250.0:
            return 5
        case ...300.0:
            return 6
        default:
            return 7 // 最大等待 7 秒
        }
    }

    /// 生成「跳收果實」路線節點
    /// 根據路線點位劃半徑 40m 圓，走由南向北直徑 (80m)
    /// 直徑走完瞬間跳至下一點的南端起點，並自動套用距離冷卻 (最多 7 秒)
    public static func generateFruitRouteNodes(basePoints: [RouteNode], distanceMeters: Double = 80.0) -> [RouteNode] {
        guard !basePoints.isEmpty else { return [] }
        let total = basePoints.count
        var result: [RouteNode] = []
        var prevNorth: (lat: Double, lng: Double)? = nil
        let radius = max(distanceMeters / 2.0, 1.0)

        for (i, center) in basePoints.enumerated() {
            // 南端點 (方位角 180 度)
            let south = moveLocation(lat: center.lat, lng: center.lng, distanceMeters: radius, bearingDegrees: 180.0)
            // 北端點 (方位角 0 度)
            let north = moveLocation(lat: center.lat, lng: center.lng, distanceMeters: radius, bearingDegrees: 0.0)

            let cdSec: Int
            if let pNorth = prevNorth {
                let dist = getDistance(lat1: pNorth.lat, lon1: pNorth.lng, lat2: south.lat, lon2: south.lng)
                cdSec = calculateCooldownSeconds(distanceMeters: dist)
            } else {
                cdSec = 0
            }

            // 南端起點：第 1 點直接開始，第 2 點起為瞬移點並帶有冷卻時間
            result.append(
                RouteNode(
                    lat: south.lat,
                    lng: south.lng,
                    waitTimeSec: cdSec,
                    isTeleport: (i > 0),
                    fruitIndex: i + 1,
                    totalFruits: total
                )
            )

            // 北端終點：由南向北行走直徑
            result.append(
                RouteNode(
                    lat: north.lat,
                    lng: north.lng,
                    waitTimeSec: 0,
                    isTeleport: false,
                    fruitIndex: i + 1,
                    totalFruits: total
                )
            )

            prevNorth = north
        }
        return result
    }

    /// 模擬真人碎步插點 (在長距離直線中插入隨機步伐，防止被系統偵測直飛)
    public static func densifyRoute(points: [RouteNode], minStep: Double = 100.0, maxStep: Double = 150.0) -> [RouteNode] {
        guard points.count >= 2 else { return points }
        let safeMin = minStep <= 0 ? 1.0 : minStep
        let safeMax = maxStep < safeMin ? safeMin : maxStep

        var densePoints: [RouteNode] = []
        densePoints.append(points[0])

        for i in 0..<(points.count - 1) {
            let p1 = points[i]
            let p2 = points[i + 1]
            let totalDist = getDistance(lat1: p1.lat, lon1: p1.lng, lat2: p2.lat, lon2: p2.lng)

            if totalDist.isNaN || totalDist.isInfinite {
                densePoints.append(p2)
                continue
            }

            if totalDist > safeMax {
                let bearing = getBearing(lat1: p1.lat, lon1: p1.lng, lat2: p2.lat, lon2: p2.lng)
                let stepRange = safeMax - safeMin
                var currentDist = Double.random(in: 0...1) * stepRange + safeMin
                var safetyLimit = 50000

                while currentDist < totalDist && safetyLimit > 0 {
                    safetyLimit -= 1
                    let dest = moveLocation(lat: p1.lat, lng: p1.lng, distanceMeters: currentDist, bearingDegrees: bearing)
                    densePoints.append(RouteNode(lat: dest.lat, lng: dest.lng))
                    currentDist += Double.random(in: 0...1) * stepRange + safeMin
                }
            }
            densePoints.append(p2)
        }
        return densePoints
    }

    /// 計算算術平均幾何中心點 (方案 A)
    public static func calculateAverageCenter(points: [RouteNode]) -> (lat: Double, lng: Double)? {
        guard !points.isEmpty else { return nil }
        let avgLat = points.map { $0.lat }.reduce(0, +) / Double(points.count)
        let avgLng = points.map { $0.lng }.reduce(0, +) / Double(points.count)
        return (lat: avgLat, lng: avgLng)
    }
}
