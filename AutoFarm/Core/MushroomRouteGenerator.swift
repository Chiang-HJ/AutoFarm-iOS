import Foundation
import CoreLocation

public enum MushroomAreaBlock {
    case rect(p1: CLLocationCoordinate2D, p2: CLLocationCoordinate2D)
    case polygon(points: [CLLocationCoordinate2D])
}

public enum MushroomRouteGenerator {

    /**
     * 以中心點與半徑 (公尺) 生成覆蓋矩形網格路線
     */
    public static func generateRadiusRoute(
        centerLat: Double,
        centerLng: Double,
        radiusMeters: Double = 3000.0,
        spacingMeters: Double = 600.0
    ) -> [RouteNode] {
        let latDelta = radiusMeters / 111111.0
        let cosLat = max(cos(centerLat * .pi / 180.0), 0.01)
        let lngDelta = radiusMeters / (111111.0 * cosLat)

        let p1 = CLLocationCoordinate2D(latitude: centerLat - latDelta, longitude: centerLng - lngDelta)
        let p2 = CLLocationCoordinate2D(latitude: centerLat + latDelta, longitude: centerLng + lngDelta)

        return generateRectangleRoute(p1: p1, p2: p2, spacingMeters: spacingMeters)
    }

    /**
     * 生成矩形框選區域的 S 型 (boustrophedon) 網格巡航路徑
     */
    public static func generateRectangleRoute(
        p1: CLLocationCoordinate2D,
        p2: CLLocationCoordinate2D,
        spacingMeters: Double = 600.0
    ) -> [RouteNode] {
        let minLat = min(p1.latitude, p2.latitude)
        let maxLat = max(p1.latitude, p2.latitude)
        let minLng = min(p1.longitude, p2.longitude)
        let maxLng = max(p1.longitude, p2.longitude)

        return generateGrid(minLat: minLat, maxLat: maxLat, minLng: minLng, maxLng: maxLng, spacingMeters: spacingMeters, polygon: nil)
    }

    /**
     * 生成多邊形框選區域的 S 型網格巡航路徑
     */
    public static func generatePolygonRoute(
        polygon: [CLLocationCoordinate2D],
        spacingMeters: Double = 600.0
    ) -> [RouteNode] {
        guard polygon.count >= 3 else { return [] }

        let minLat = polygon.map { $0.latitude }.min() ?? 0.0
        let maxLat = polygon.map { $0.latitude }.max() ?? 0.0
        let minLng = polygon.map { $0.longitude }.min() ?? 0.0
        let maxLng = polygon.map { $0.longitude }.max() ?? 0.0

        return generateGrid(minLat: minLat, maxLat: maxLat, minLng: minLng, maxLng: maxLng, spacingMeters: spacingMeters, polygon: polygon)
    }

    /**
     * 組合多個區塊生成跨區掃菇路線，區塊銜接點標記為 isTeleport = true
     */
    public static func generateMultiBlockRoute(
        blocks: [MushroomAreaBlock],
        spacingMeters: Double = 600.0
    ) -> [RouteNode] {
        guard !blocks.isEmpty else { return [] }
        var combined: [RouteNode] = []

        for block in blocks {
            let blockPoints: [RouteNode]
            switch block {
            case .rect(let p1, let p2):
                blockPoints = generateRectangleRoute(p1: p1, p2: p2, spacingMeters: spacingMeters)
            case .polygon(let points):
                blockPoints = generatePolygonRoute(polygon: points, spacingMeters: spacingMeters)
            }
            if blockPoints.isEmpty { continue }

            if combined.isEmpty {
                combined.append(contentsOf: blockPoints)
            } else {
                // 跨區跳躍航點：標記為瞬移
                var firstNode = blockPoints.first!
                firstNode.isTeleport = true
                combined.append(firstNode)
                if blockPoints.count > 1 {
                    combined.append(contentsOf: blockPoints.dropFirst())
                }
            }
        }
        return combined
    }

    private static func generateGrid(
        minLat: Double,
        maxLat: Double,
        minLng: Double,
        maxLng: Double,
        spacingMeters: Double,
        polygon: [CLLocationCoordinate2D]?
    ) -> [RouteNode] {
        let midLat = (minLat + maxLat) / 2.0
        let latStep = spacingMeters / 111111.0
        let cosLat = max(cos(midLat * .pi / 180.0), 0.01)
        let lngStep = spacingMeters / (111111.0 * cosLat)

        var results: [RouteNode] = []
        var currLat = maxLat
        var leftToRight = true

        while currLat >= minLat - (latStep * 0.1) {
            var rowPoints: [RouteNode] = []

            if let poly = polygon, poly.count >= 3 {
                let spans = getPolygonSpans(lat: currLat, polygon: poly)
                for span in spans {
                    var currLng = span.0
                    let endLng = span.1
                    while currLng <= endLng + (lngStep * 0.1) {
                        rowPoints.append(RouteNode(lat: currLat, lng: currLng, waitTimeSec: 0, isTeleport: false))
                        currLng += lngStep
                    }
                    if rowPoints.isEmpty || rowPoints.last?.lng != endLng {
                        rowPoints.append(RouteNode(lat: currLat, lng: endLng, waitTimeSec: 0, isTeleport: false))
                    }
                }
            } else {
                var currLng = minLng
                while currLng <= maxLng + (lngStep * 0.1) {
                    rowPoints.append(RouteNode(lat: currLat, lng: currLng, waitTimeSec: 0, isTeleport: false))
                    currLng += lngStep
                }
            }

            if !leftToRight {
                rowPoints.reverse()
            }

            results.append(contentsOf: rowPoints)
            leftToRight = !leftToRight
            currLat -= latStep
        }

        return results
    }

    private static func getPolygonSpans(lat: Double, polygon: [CLLocationCoordinate2D]) -> [(Double, Double)] {
        var xs: [Double] = []
        let n = polygon.count
        for i in 0..<n {
            let a = polygon[i]
            let b = polygon[(i + 1) % n]
            if (a.latitude <= lat && b.latitude > lat) || (b.latitude <= lat && a.latitude > lat) {
                let t = (lat - a.latitude) / (b.latitude - a.latitude)
                xs.append(a.longitude + t * (b.longitude - a.longitude))
            }
        }
        xs.sort()
        var spans: [(Double, Double)] = []
        var i = 0
        while i + 1 < xs.count {
            spans.append((xs[i], xs[i + 1]))
            i += 2
        }
        return spans
    }
}
