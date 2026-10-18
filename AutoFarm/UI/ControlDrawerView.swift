import SwiftUI
import UIKit

public struct ControlDrawerView: View {
    @ObservedObject var session = AutoFarmSession.shared

    @State private var selectedTab: Int = 0
    @State private var loopsInput: String = "0"
    @State private var fruitDistInput: String = "80"
    @State private var concentricRadiusInput: String = "30"
    @State private var concentricStepInput: String = "10"
    @State private var concentricMode: ConcentricMode = .multiRing

    var onOpenShare: () -> Void
    var onOpenSettings: () -> Void

    public init(onOpenShare: @escaping () -> Void, onOpenSettings: @escaping () -> Void) {
        self.onOpenShare = onOpenShare
        self.onOpenSettings = onOpenSettings
    }

    public var body: some View {
        VStack(spacing: 10) {
            // 頂部抓把 (Drawer Handle)
            Capsule()
                .fill(Color.gray.opacity(0.4))
                .frame(width: 36, height: 4)
                .padding(.top, 4)

            // 功能分頁切換列
            Picker("功能模組", selection: $selectedTab) {
                Text("直線巡航").tag(0)
                Text("繞圈種花").tag(1)
                Text("跳收果實").tag(2)
                Text("同心圓").tag(3)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            // 各分頁細部參數
            Group {
                switch selectedTab {
                case 0:
                    linearTabContent
                case 1:
                    flowerTabContent
                case 2:
                    fruitTabContent
                case 3:
                    concentricTabContent
                default:
                    EmptyView()
                }
            }
            .padding(.horizontal)

            Divider()

            // 核心控制操作列
            HStack(spacing: 8) {
                // 開始 / 暫停按鈕
                Button(action: {
                    if session.routePoints.isEmpty {
                        let basePoints: [RouteNode]
                        let name: String
                        if let first = SavedDatabaseStore.shared.savedRoutes.first {
                            name = first.name
                            basePoints = first.nodes
                        } else {
                            name = "預設巡航"
                            basePoints = [
                                RouteNode(lat: session.currentLat, lng: session.currentLng),
                                RouteNode(lat: session.currentLat + 0.002, lng: session.currentLng + 0.002)
                            ]
                        }
                        switch selectedTab {
                        case 1:
                            session.startFlowerRoute(name: name, basePoints: basePoints, loops: Int(loopsInput) ?? 0, settings: session.flowerSettings)
                        case 2:
                            session.startFruitRoute(name: name, basePoints: basePoints, loops: Int(loopsInput) ?? 0, walkDistance: Double(fruitDistInput) ?? 80.0)
                        case 3:
                            session.startConcentricFlower(centerLat: session.currentLat, centerLng: session.currentLng, radius: Double(concentricRadiusInput) ?? 30.0, step: Double(concentricStepInput) ?? 10.0, mode: concentricMode)
                        default:
                            session.startLinearRoute(name: name, basePoints: basePoints, loops: Int(loopsInput) ?? 0, mode: session.loopMode)
                        }
                    } else {
                        session.toggleRoutePause()
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: session.isRoutePaused ? "play.fill" : "pause.fill")
                        Text(session.isRoutePaused ? "開始/繼續" : "暫停")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(session.isRoutePaused ? Color.green : Color.orange)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }

                // 下一點按鈕
                Button(action: { session.nextRoutePoint() }) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 13))
                        .frame(width: 40, height: 38)
                        .background(Color(UIColor.secondarySystemBackground))
                        .foregroundColor(.primary)
                        .cornerRadius(10)
                }

                // 停止路線按鈕 (黃色警示：僅停止路線，維持當前定位)
                Button(action: { session.stopRoute() }) {
                    Text("停止路線")
                        .font(.system(size: 12, weight: .bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 10)
                        .background(Color.yellow.opacity(0.85))
                        .foregroundColor(.black)
                        .cornerRadius(10)
                }

                // 停止虛擬定位按鈕 (紅色：徹底回到現實世界 GPS)
                Button(action: { session.stopMocking() }) {
                    Text("恢復真GPS")
                        .font(.system(size: 12, weight: .bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 10)
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 6)
        }
        .background(Color(UIColor.systemBackground).opacity(0.96))
        .cornerRadius(20, corners: [.topLeft, .topRight])
        .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: -2)
    }

    // MARK: - Tab 1: 直線巡航
    private var linearTabContent: some View {
        VStack(spacing: 8) {
            HStack {
                Text("循環模式：")
                    .font(.system(size: 12, weight: .medium))
                Picker("循環模式", selection: $session.loopMode) {
                    ForEach(LoopMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            HStack {
                Text("目標輪數 (0=無限)：")
                    .font(.system(size: 12, weight: .medium))
                TextField("輪數", text: $loopsInput)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)
                Spacer()

                // 時速快速切換
                HStack(spacing: 4) {
                    speedBtn("步行", 3.6)
                    speedBtn("慢跑", 9.0)
                    speedBtn("單車", 18.0)
                }
            }
        }
    }

    // MARK: - Tab 2: 繞圈種花
    private var flowerTabContent: some View {
        VStack(spacing: 6) {
            HStack {
                Toggle("花點間瞬移", isOn: $session.flowerSettings.flowerTeleport)
                    .font(.system(size: 12))
                Spacer()
                Toggle("啟用第二圈", isOn: $session.flowerSettings.enableCircle2)
                    .font(.system(size: 12))
            }

            HStack {
                Toggle("微擾防封", isOn: $session.flowerSettings.flowerJitter)
                    .font(.system(size: 12))
                Spacer()
                Toggle("正反轉交替", isOn: $session.flowerSettings.flowerAlternate)
                    .font(.system(size: 12))
            }

            HStack {
                Text("第一圈半徑: 28m / 留7s")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
                Text("第二圈半徑: 24m / 留7s")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Tab 3: 跳收果實
    private var fruitTabContent: some View {
        VStack(spacing: 6) {
            HStack {
                Text("直徑行走距離 (m)：")
                    .font(.system(size: 12, weight: .medium))
                TextField("80", text: $fruitDistInput)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)
                Spacer()
            }
            Text("• 依花心劃半徑 40m 圓，走由南向北 80m 直徑。\n• 走完瞬間瞬移下一點，並自動套用寶可夢短距冷卻 (上限7秒)。")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Tab 4: 同心圓種花
    private var concentricTabContent: some View {
        VStack(spacing: 6) {
            HStack {
                Text("模式：")
                    .font(.system(size: 12, weight: .medium))
                Picker("同心圓模式", selection: $concentricMode) {
                    ForEach(ConcentricMode.allCases, id: \.self) { m in
                        Text(m.displayName).tag(m)
                    }
                }
                .pickerStyle(.segmented)
            }

            HStack {
                Text("總半徑(m)：")
                    .font(.system(size: 12, weight: .medium))
                TextField("30", text: $concentricRadiusInput)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)

                Text("環間距(m)：")
                    .font(.system(size: 12, weight: .medium))
                TextField("10", text: $concentricStepInput)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 50)

                Button("生成") {
                    let r = Double(concentricRadiusInput) ?? 30.0
                    let s = Double(concentricStepInput) ?? 10.0
                    session.startConcentricFlower(
                        centerLat: session.currentLat,
                        centerLng: session.currentLng,
                        radius: r,
                        step: s,
                        mode: concentricMode
                    )
                }
                .buttonStyle(.borderedProminent)
                .font(.system(size: 12, weight: .bold))
            }
        }
    }

    private func speedBtn(_ label: String, _ speed: Double) -> some View {
        Button(action: { session.speedKmh = speed }) {
            Text(label)
                .font(.system(size: 11))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(session.speedKmh == speed ? Color.blue : Color(UIColor.tertiarySystemBackground))
                .foregroundColor(session.speedKmh == speed ? .white : .primary)
                .cornerRadius(6)
        }
    }
}

// Corner radius helper
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}
