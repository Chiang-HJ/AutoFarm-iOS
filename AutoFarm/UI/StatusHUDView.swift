import SwiftUI

public struct StatusHUDView: View {
    @ObservedObject var session = AutoFarmSession.shared

    public init() {}

    private var loopTotalStr: String {
        session.routeLoopTarget == 0 ? "∞" : "\(session.routeLoopTarget)"
    }

    private var modeDescription: String {
        switch session.executionMode {
        case 0:
            let loopName = session.loopMode.displayName
            if session.routePoints.isEmpty {
                return "直線待命中"
            }
            return "直線(\(loopName)) \(session.currentRouteIndex + 1)/\(session.routePoints.count) (第 \(session.routeCurrentLoop + 1)/\(loopTotalStr) 圈)"
        case 1:
            if session.routePoints.isEmpty {
                return "種花待命中"
            }
            return "多點種花 \(session.currentRouteIndex + 1)/\(session.routePoints.count) (第 \(session.routeCurrentLoop + 1)/\(loopTotalStr) 圈)"
        case 2:
            if session.routePoints.isEmpty {
                return "跳收果實待命中"
            }
            if session.cooldownRemainingSec > 0 {
                return "跳收果實 \(session.currentRouteIndex + 1)/\(session.routePoints.count) (冷卻 \(session.cooldownRemainingSec)s)"
            }
            return "跳收果實 \(session.currentRouteIndex + 1)/\(session.routePoints.count) (第 \(session.routeCurrentLoop + 1)/\(loopTotalStr) 圈)"
        case 3:
            return "同心圓種花 \(session.currentRouteIndex + 1)/\(session.routePoints.count)"
        default:
            return "手動搖桿"
        }
    }

    public var body: some View {
        VStack(spacing: 6) {
            // Toast 浮動警示
            if let toast = session.toastMessage {
                Text(toast)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.85))
                    .cornerRadius(20)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.easeInOut, value: session.toastMessage)
            }

            // HUD 核心資訊條
            HStack(spacing: 12) {
                // 時速指示
                HStack(spacing: 4) {
                    Image(systemName: "speedometer")
                        .font(.system(size: 13))
                        .foregroundColor(.blue)
                    Text("\(String(format: "%.1f", session.speedKmh)) km/h")
                        .font(.system(size: 13, weight: .semibold))
                }

                Divider().frame(height: 14)

                // 模式與進度
                Text(modeDescription)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .foregroundColor(session.cooldownRemainingSec > 0 ? .orange : .primary)

                if session.cooldownRemainingSec > 0 {
                    Divider().frame(height: 14)
                    HStack(spacing: 2) {
                        Image(systemName: "timer")
                            .font(.system(size: 12))
                            .foregroundColor(.orange)
                        Text("\(session.cooldownRemainingSec)s")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.orange)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color(UIColor.secondarySystemBackground).opacity(0.92))
            .cornerRadius(18)
            .shadow(color: Color.black.opacity(0.12), radius: 5, x: 0, y: 2)
        }
    }
}
