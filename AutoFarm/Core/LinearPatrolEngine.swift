import Foundation

public enum LoopMode: Int, Codable, CaseIterable {
    case teleportToStart = 0 // 跳回起點
    case closedLoop = 1       // 閉合路線

    public var displayName: String {
        switch self {
        case .teleportToStart: return "跳回起點"
        case .closedLoop: return "閉合路線"
        }
    }
}

public final class LinearPatrolEngine {
    public static func prepareRouteNodes(basePoints: [RouteNode], mode: LoopMode) -> [RouteNode] {
        guard !basePoints.isEmpty else { return [] }
        var result = basePoints

        if mode == .closedLoop && result.count > 1 {
            let first = result.first!
            let last = result.last!
            // 若首尾點不同，則尾端自動追加起點以形成完整封閉路徑
            if first.lat != last.lat || first.lng != last.lng {
                result.append(RouteNode(lat: first.lat, lng: first.lng, waitTimeSec: 0, isTeleport: false, label: "返回起點"))
            }
        }
        return result
    }
}
