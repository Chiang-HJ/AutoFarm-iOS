import Foundation

public final class FruitHarvestEngine {

    /// 根據果實中心點與直徑行走距離產生跳收果實路線
    public static func prepareFruitNodes(basePoints: [RouteNode], walkDistanceMeters: Double = 80.0) -> [RouteNode] {
        return EngineMath.generateFruitRouteNodes(basePoints: basePoints, distanceMeters: walkDistanceMeters)
    }

    /// 當一輪結束重頭開始時，計算最後一點到第 1 點南端之循環冷卻秒數
    public static func calculateLoopCooldown(lastCoord: (lat: Double, lng: Double), firstCoord: (lat: Double, lng: Double)) -> Int {
        let dist = EngineMath.getDistance(lat1: lastCoord.lat, lon1: lastCoord.lng, lat2: firstCoord.lat, lon2: firstCoord.lng)
        return EngineMath.calculateCooldownSeconds(distanceMeters: dist)
    }
}
