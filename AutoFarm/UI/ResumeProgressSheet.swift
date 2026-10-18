import SwiftUI

public struct ResumeProgressSheet: View {
    let progress: RouteProgress
    var onResume: () -> Void
    var onRestart: () -> Void
    var onDismiss: () -> Void

    public init(progress: RouteProgress, onResume: @escaping () -> Void, onRestart: @escaping () -> Void, onDismiss: @escaping () -> Void) {
        self.progress = progress
        self.onResume = onResume
        self.onRestart = onRestart
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "pin.fill")
                    .foregroundColor(.blue)
                Text("偵測到未完成進度")
                    .font(.headline)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("路線名稱：\(progress.routeName)")
                    .font(.subheadline)
                    .fontWeight(.medium)

                let loopStr = progress.loopTarget == 0 ? "第 \(progress.currentLoop + 1) 圈 / ∞" : "第 \(progress.currentLoop + 1) / \(progress.loopTarget) 圈"
                Text("暫存進度：\(loopStr)，第 \(progress.currentRouteIndex + 1) / \(progress.totalPoints) 點")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                if !progress.formattedTime.isEmpty {
                    Text("暫存時間：\(progress.formattedTime)")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(12)

            Text("是否要接續上次中斷點繼續運行？")
                .font(.subheadline)
                .fontWeight(.bold)

            HStack(spacing: 12) {
                Button(action: onRestart) {
                    Text("重新開始")
                        .font(.system(size: 14, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color(UIColor.systemGray5))
                        .foregroundColor(.primary)
                        .cornerRadius(10)
                }

                Button(action: onResume) {
                    Text("接續上次進度")
                        .font(.system(size: 14, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
            }
        }
        .padding(20)
        .background(Color(UIColor.systemBackground))
        .cornerRadius(18)
        .shadow(radius: 12)
        .frame(maxWidth: 320)
    }
}
