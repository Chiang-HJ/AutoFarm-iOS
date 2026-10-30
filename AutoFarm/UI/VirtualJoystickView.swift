import SwiftUI
import UIKit

public struct VirtualJoystickView: View {
    @ObservedObject var session = AutoFarmSession.shared

    @State private var dragOffset: CGSize = .zero
    private let outerRadius: CGFloat = 55.0
    private let thumbRadius: CGFloat = 24.0

    public init() {}

    public var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                // 主搖桿圓盤
                ZStack {
                    // 外圈底盤
                    Circle()
                        .fill(Color(UIColor.systemBackground).opacity(0.92))
                        .frame(width: outerRadius * 2, height: outerRadius * 2)
                        .overlay(
                            Circle().stroke(session.isJoystickLocked ? Color.orange : Color.blue.opacity(0.7), lineWidth: session.isJoystickLocked ? 3.0 : 1.5)
                        )
                        .shadow(color: Color.black.opacity(0.25), radius: 6, x: 0, y: 3)

                    // 十字引導線
                    Path { p in
                        p.move(to: CGPoint(x: outerRadius, y: 14))
                        p.addLine(to: CGPoint(x: outerRadius, y: outerRadius * 2 - 14))
                        p.move(to: CGPoint(x: 14, y: outerRadius))
                        p.addLine(to: CGPoint(x: outerRadius * 2 - 14, y: outerRadius))
                    }
                    .stroke(Color.gray.opacity(0.25), lineWidth: 1)

                    // 搖桿推盤 (支援拖曳 + 點兩下鎖定)
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: session.isJoystickLocked ? [Color.orange, Color.red] : [Color.blue, Color.cyan],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: thumbRadius * 2, height: thumbRadius * 2)
                            .shadow(color: Color.black.opacity(0.35), radius: 3, x: 0, y: 2)

                        if session.isJoystickLocked {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                    .offset(dragOffset)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let dx = value.translation.width
                                let dy = value.translation.height
                                let distance = sqrt(dx * dx + dy * dy)
                                let maxDist = outerRadius - thumbRadius

                                let clampedDist = min(distance, maxDist)
                                let angleRad = atan2(dy, dx)

                                self.dragOffset = CGSize(
                                    width: cos(angleRad) * clampedDist,
                                    height: sin(angleRad) * clampedDist
                                )

                                let intensity = Double(clampedDist / maxDist)
                                var geoBearing = (angleRad * 180.0 / .pi) + 90.0
                                if geoBearing < 0 { geoBearing += 360.0 }

                                if intensity > 0 && !session.hasTestedHandshake {
                                    session.ensureHandshakeVerified(actionName: "虛擬方向盤") {}
                                }

                                session.joystickAngle = geoBearing
                                session.joystickIntensity = intensity
                            }
                            .onEnded { _ in
                                if !session.isJoystickLocked {
                                    withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) {
                                        self.dragOffset = .zero
                                    }
                                    session.joystickIntensity = 0.0
                                }
                            }
                    )
                    .simultaneousGesture(
                        TapGesture(count: 2)
                            .onEnded {
                                session.isJoystickLocked.toggle()
                                if !session.isJoystickLocked {
                                    withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) {
                                        self.dragOffset = .zero
                                    }
                                    session.joystickIntensity = 0.0
                                }
                            }
                    )
                }

                // 顯眼關閉按鈕 (釘在右上角，點擊縮小)
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        session.isJoystickEnabled = false
                    }
                }) {
                    ZStack {
                        Circle()
                            .fill(Color(UIColor.secondarySystemBackground))
                            .frame(width: 24, height: 24)
                            .shadow(color: Color.black.opacity(0.2), radius: 2, x: 0, y: 1)
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.primary)
                    }
                }
                .offset(x: 4, y: -4)
            }
            .frame(width: outerRadius * 2 + 10, height: outerRadius * 2 + 10)

            // 緊貼下方的微型提示標籤 (保證緊密依附在搖桿正下方)
            Text(session.isJoystickLocked ? "已鎖定 (雙擊解鎖)" : "雙擊推盤可鎖定方向")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(session.isJoystickLocked ? .white : .secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(session.isJoystickLocked ? Color.orange : Color(UIColor.secondarySystemBackground).opacity(0.85))
                .cornerRadius(4)
        }
        .frame(width: 130)
    }
}
