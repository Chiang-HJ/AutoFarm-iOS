import SwiftUI
import UIKit

public struct VirtualJoystickView: View {
    @ObservedObject var session = AutoFarmSession.shared

    @State private var dragOffset: CGSize = .zero
    private let outerRadius: CGFloat = 65.0
    private let thumbRadius: CGFloat = 28.0

    public init() {}

    public var body: some View {
        VStack(spacing: 6) {
            ZStack {
                // 外圈底盤
                Circle()
                    .fill(Color(UIColor.systemBackground).opacity(0.85))
                    .frame(width: outerRadius * 2, height: outerRadius * 2)
                    .overlay(
                        Circle().stroke(session.isJoystickLocked ? Color.orange : Color.blue.opacity(0.6), lineWidth: 2)
                    )
                    .shadow(color: Color.black.opacity(0.2), radius: 6, x: 0, y: 3)

                // 中心十字引導線
                Path { p in
                    p.move(to: CGPoint(x: outerRadius, y: 15))
                    p.addLine(to: CGPoint(x: outerRadius, y: outerRadius * 2 - 15))
                    p.move(to: CGPoint(x: 15, y: outerRadius))
                    p.addLine(to: CGPoint(x: outerRadius * 2 - 15, y: outerRadius))
                }
                .stroke(Color.gray.opacity(0.25), lineWidth: 1)

                // 搖桿推盤
                Circle()
                    .fill(
                        LinearGradient(
                            colors: session.isJoystickLocked ? [Color.orange, Color.red] : [Color.blue, Color.cyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: thumbRadius * 2, height: thumbRadius * 2)
                    .offset(dragOffset)
                    .shadow(color: Color.black.opacity(0.3), radius: 3, x: 0, y: 2)
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
                                // 轉換為北為 0 度之地理方位角
                                var geoBearing = (angleRad * 180.0 / .pi) + 90.0
                                if geoBearing < 0 { geoBearing += 360.0 }

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
            }

            // 方向鎖定按鈕
            Button(action: {
                session.isJoystickLocked.toggle()
                if !session.isJoystickLocked {
                    withAnimation(.spring()) {
                        self.dragOffset = .zero
                    }
                    session.joystickIntensity = 0.0
                }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: session.isJoystickLocked ? "lock.fill" : "lock.open")
                        .font(.system(size: 11))
                    Text(session.isJoystickLocked ? "已鎖定" : "方向鎖定")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(session.isJoystickLocked ? .white : .primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(session.isJoystickLocked ? Color.orange : Color(UIColor.secondarySystemBackground))
                .cornerRadius(12)
            }
        }
    }
}
