import SwiftUI
import UIKit

public struct VirtualJoystickView: View {
    @ObservedObject var session = AutoFarmSession.shared

    @State private var dragOffset: CGSize = .zero
    private let outerRadius: CGFloat = 62.0
    private let thumbRadius: CGFloat = 26.0

    public init() {}

    public var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                // 主搖桿盤面
                ZStack {
                    // 外圈底盤
                    Circle()
                        .fill(Color(UIColor.systemBackground).opacity(0.88))
                        .frame(width: outerRadius * 2, height: outerRadius * 2)
                        .overlay(
                            Circle().stroke(session.isJoystickLocked ? Color.orange : Color.blue.opacity(0.6), lineWidth: session.isJoystickLocked ? 2.5 : 1.5)
                        )
                        .shadow(color: Color.black.opacity(0.22), radius: 6, x: 0, y: 3)

                    // 十字微引導線
                    Path { p in
                        p.move(to: CGPoint(x: outerRadius, y: 16))
                        p.addLine(to: CGPoint(x: outerRadius, y: outerRadius * 2 - 16))
                        p.move(to: CGPoint(x: 16, y: outerRadius))
                        p.addLine(to: CGPoint(x: outerRadius * 2 - 16, y: outerRadius))
                    }
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)

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
                            .shadow(color: Color.black.opacity(0.3), radius: 3, x: 0, y: 2)

                        if session.isJoystickLocked {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                    .offset(dragOffset)
                    .gesture(
                        // 拖曳方向與推力手勢
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
                        // 點兩下搖桿鎖定 / 解鎖
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

                // 右上角快速收合縮小按鈕
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        session.isJoystickEnabled = false
                    }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary)
                        .background(Color(UIColor.systemBackground).clipShape(Circle()))
                }
                .offset(x: 4, y: -4)
            }

            // 底部簡潔狀態文字 (提示雙擊鎖定)
            Text(session.isJoystickLocked ? "已方向鎖定 (雙擊解鎖)" : "雙擊推盤可鎖定方向")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(session.isJoystickLocked ? .orange : .secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color(UIColor.secondarySystemBackground).opacity(0.8))
                .cornerRadius(4)
        }
    }
}
