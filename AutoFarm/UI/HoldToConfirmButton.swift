import SwiftUI
import UIKit

/// 長按蓄力確認按鈕 (Hold-to-Confirm)
/// 杜絕單擊誤觸終止巡航或誤刪帳號，長按進度環/條填滿後方觸發動作
public struct HoldToConfirmButton: View {
    let title: String
    let icon: String
    let color: Color
    let duration: Double
    let onConfirmed: () -> Void

    @State private var progress: Double = 0.0
    @State private var timer: Timer? = nil
    @State private var isHolding: Bool = false

    public init(
        title: String,
        icon: String,
        color: Color = .red,
        duration: Double = 0.8,
        onConfirmed: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.color = color
        self.duration = duration
        self.onConfirmed = onConfirmed
    }

    public var body: some View {
        ZStack {
            // 背景動態進度充填
            GeometryReader { geo in
                Rectangle()
                    .fill(color.opacity(0.35))
                    .frame(width: geo.size.width * CGFloat(progress))
                    .animation(.linear(duration: 0.04), value: progress)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                Text(isHolding ? "長按確認..." : title)
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundColor(color)
            .padding(.vertical, 7)
        }
        .frame(maxWidth: .infinity)
        .background(color.opacity(0.12))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isHolding ? color : Color.clear, lineWidth: 1.5)
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isHolding {
                        startHolding()
                    }
                }
                .onEnded { _ in
                    cancelHolding()
                }
        )
    }

    private func startHolding() {
        isHolding = true
        progress = 0.0
        let step = 0.04
        timer = Timer.scheduledTimer(withTimeInterval: step, repeats: true) { t in
            progress += step / duration
            if progress >= 1.0 {
                t.invalidate()
                timer = nil
                isHolding = false
                progress = 0.0
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                onConfirmed()
            }
        }
    }

    private func cancelHolding() {
        timer?.invalidate()
        timer = nil
        isHolding = false
        withAnimation(.easeOut(duration: 0.18)) {
            progress = 0.0
        }
    }
}
