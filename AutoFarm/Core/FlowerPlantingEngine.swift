import Foundation
import CoreLocation

public enum ConcentricMode: String, Codable, CaseIterable {
    case multiRing = "MULTI_RING"
    case spiral = "SPIRAL"

    public var displayName: String {
        switch self {
        case .multiRing: return "階梯多環"
        case .spiral: return "連續螺旋"
        }
    }
}

public struct FlowerCircleConfig: Codable, Equatable {
    public var radius: Double = 28.0
    public var loops: Double = 1.0
    public var waitBeforeSec: Int = 1
    public var waitAfterSec: Int = 7

    public init(radius: Double = 28.0, loops: Double = 1.0, waitBeforeSec: Int = 1, waitAfterSec: Int = 7) {
        self.radius = radius
        self.loops = loops
        self.waitBeforeSec = waitBeforeSec
        self.waitAfterSec = waitAfterSec
    }
}

public typealias FlowerCircleParam = FlowerCircleConfig

public struct MultiFlowerSettings: Codable, Equatable {
    public var flowerTeleport: Bool = true
    public var enableCircle2: Bool = true
    public var flowerJitter: Bool = true
    public var flowerAlternate: Bool = true
    public var circle1: FlowerCircleConfig = FlowerCircleConfig(radius: 28.0, loops: 1.0, waitBeforeSec: 1, waitAfterSec: 7)
    public var circle2: FlowerCircleConfig = FlowerCircleConfig(radius: 24.0, loops: 1.0, waitBeforeSec: 1, waitAfterSec: 7)

    public init(
        flowerTeleport: Bool = true,
        enableCircle2: Bool = true,
        flowerJitter: Bool = true,
        flowerAlternate: Bool = true,
        circle1: FlowerCircleConfig = FlowerCircleConfig(radius: 28.0, loops: 1.0, waitBeforeSec: 1, waitAfterSec: 7),
        circle2: FlowerCircleConfig = FlowerCircleConfig(radius: 24.0, loops: 1.0, waitBeforeSec: 1, waitAfterSec: 7)
    ) {
        self.flowerTeleport = flowerTeleport
        self.enableCircle2 = enableCircle2
        self.flowerJitter = flowerJitter
        self.flowerAlternate = flowerAlternate
        self.circle1 = circle1
        self.circle2 = circle2
    }
}

public final class FlowerPlantingEngine {

    /// 根據路線中的基準花苞點位生成多花點雙圈種花軌跡
    public static func generateMultiFlowerNodes(
        basePoints: [RouteNode],
        settings: MultiFlowerSettings
    ) -> [RouteNode] {
        guard !basePoints.isEmpty else { return [] }
        var routeNodes: [RouteNode] = []
        let passes = settings.enableCircle2 ? 2 : 1

        for pass in 1...passes {
            let radius = (pass == 1) ? settings.circle1.radius : settings.circle2.radius
            let loopCnt = (pass == 1) ? settings.circle1.loops : settings.circle2.loops
            let waitBefore = (pass == 1) ? settings.circle1.waitBeforeSec : settings.circle2.waitBeforeSec
            let waitAfter = (pass == 1) ? settings.circle1.waitAfterSec : settings.circle2.waitAfterSec

            // 第一圈順時針，若開啟交替則第二圈逆時針
            let clockwise = (settings.flowerAlternate && pass == 2) ? false : true

            for (flowerIdx, center) in basePoints.enumerated() {
                let totalPoints = Int(36.0 * loopCnt)

                for ptIdx in 0...totalPoints {
                    let angleDeg = clockwise ? (Double(ptIdx) * 10.0) : (360.0 - (Double(ptIdx) * 10.0))
                    let r = settings.flowerJitter ? (radius + Double.random(in: -0.5...0.5)) : radius
                    let dest = EngineMath.moveLocation(lat: center.lat, lng: center.lng, distanceMeters: r, bearingDegrees: angleDeg)

                    let isTeleportPoint = (ptIdx == 0 && settings.flowerTeleport)
                    let waitTime = (ptIdx == 0) ? waitBefore : ((ptIdx == totalPoints) ? waitAfter : 0)

                    routeNodes.append(
                        RouteNode(
                            lat: dest.lat,
                            lng: dest.lng,
                            waitTimeSec: waitTime,
                            isTeleport: isTeleportPoint,
                            label: "花苞 #\(flowerIdx + 1)",
                            flowerIndex: flowerIdx + 1,
                            totalFlowers: basePoints.count,
                            lapIndex: pass,
                            totalLaps: passes
                        )
                    )
                }
            }
        }
        return routeNodes
    }

    /// 產生單花苞同心圓/連續螺旋散步路線 (完全對齊 ConcentricFlowerGenerator)
    public static func generateConcentricRoute(
        centerLat: Double,
        centerLng: Double,
        targetRadiusM: Double = 30.0,
        stepWidthM: Double = 10.0,
        mode: ConcentricMode = .multiRing,
        pointsPerRing: Int = 16
    ) -> [RouteNode] {
        let radius = max(min(targetRadiusM, 500.0), 5.0)
        let step = max(min(stepWidthM, 50.0), 2.0)
        var nodes: [RouteNode] = []
        let earthRadius = 6371000.0
        let centerLatRad = centerLat * .pi / 180.0

        let numRings = max(Int(ceil(radius / step)), 1)

        switch mode {
        case .multiRing:
            // 階梯式同心多環：從第 1 圈 (內圈) 逐步往外擴展至最大半徑
            for ring in 1...numRings {
                let ringRadius = min(Double(ring) * step, radius)
                for i in 0..<pointsPerRing {
                    let angle = 2.0 * .pi * Double(i) / Double(pointsPerRing)
                    let dLat = (ringRadius * cos(angle)) / earthRadius
                    let dLng = (ringRadius * sin(angle)) / (earthRadius * cos(centerLatRad))
                    let pLat = centerLat + (dLat * 180.0 / .pi)
                    let pLng = centerLng + (dLng * 180.0 / .pi)

                    nodes.append(
                        RouteNode(
                            lat: pLat,
                            lng: pLng,
                            waitTimeSec: 0,
                            isTeleport: false,
                            label: "第 \(ring) 環",
                            flowerIndex: 1,
                            totalFlowers: 1,
                            lapIndex: ring,
                            totalLaps: numRings
                        )
                    )
                }
            }

        case .spiral:
            // 阿基米德連續螺旋：半徑隨角度線性遞增，由最內圈平滑擴展至最外圈
            let innerRadius = min(step, radius)
            let totalSteps = numRings * pointsPerRing
            let totalAngle = 2.0 * .pi * Double(numRings)

            for i in 0..<totalSteps {
                let progress = Double(i) / Double(totalSteps)
                let currentRadius = innerRadius + progress * (radius - innerRadius)
                let angle = progress * totalAngle
                let currentRing = min(Int(progress * Double(numRings)) + 1, numRings)

                let dLat = (currentRadius * cos(angle)) / earthRadius
                let dLng = (currentRadius * sin(angle)) / (earthRadius * cos(centerLatRad))
                let pLat = centerLat + (dLat * 180.0 / .pi)
                let pLng = centerLng + (dLng * 180.0 / .pi)

                nodes.append(
                    RouteNode(
                        lat: pLat,
                        lng: pLng,
                        waitTimeSec: 0,
                        isTeleport: false,
                        label: "螺旋進度 \(Int(progress * 100))%",
                        flowerIndex: 1,
                        totalFlowers: 1,
                        lapIndex: currentRing,
                        totalLaps: numRings
                    )
                )
            }
        }
        return nodes
    }
}
