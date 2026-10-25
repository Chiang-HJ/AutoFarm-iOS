import SwiftUI
import CoreLocation

// MARK: - 頂部果實成熟提醒橫幅 (Banner)
public struct FruitNoticeBannerView: View {
    @ObservedObject var station = FlowerStationManager.shared
    @Binding var isSheetPresented: Bool

    public init(isSheetPresented: Binding<Bool>) {
        self._isSheetPresented = isSheetPresented
    }

    public var body: some View {
        if !station.matureFlowers.isEmpty {
            Button(action: { isSheetPresented = true }) {
                HStack(spacing: 8) {
                    Image(systemName: "bell.badge.fill")
                        .foregroundColor(.yellow)
                        .font(.system(size: 15))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("📣 目前有 \(station.matureFlowers.count) 處花田果實成熟待收！")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)

                        Text("（\(flowersSummary())）・點擊查看智慧推薦路線")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.85))
                            .lineLimit(1)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    LinearGradient(
                        colors: [Color(red: 0.85, green: 0.35, blue: 0.1), Color(red: 0.95, green: 0.55, blue: 0.15)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(12)
                .shadow(color: Color.black.opacity(0.2), radius: 5, x: 0, y: 2)
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private func flowersSummary() -> String {
        let names = station.matureFlowers.prefix(4).map { $0.name }
        if station.matureFlowers.count > 4 {
            return "\(names.joined(separator: "、")) 等 \(station.matureFlowers.count) 處"
        }
        return names.joined(separator: "、")
    }
}

// MARK: - 果實成熟與智慧路線推薦聚合選單 (Sheet)
public struct FruitNoticeSheet: View {
    @ObservedObject var station = FlowerStationManager.shared
    @ObservedObject var session = AutoFarmSession.shared
    @Environment(\.dismiss) var dismiss

    public init() {}

    public var body: some View {
        NavigationView {
            List {
                Section(header: Text("花田果實成熟列表 (共 \(station.matureFlowers.count) 處)")) {
                    if station.matureFlowers.isEmpty {
                        Text("目前暫無成熟大果實花田")
                            .foregroundColor(.secondary)
                            .font(.system(size: 14))
                    } else {
                        ForEach(station.matureFlowers) { flower in
                            FruitFlowerCard(flower: flower) {
                                dismiss()
                            }
                        }
                    }
                }
            }
            .listStyle(InsetGroupedListStyle())
            .navigationTitle("花田果實成熟通知")
            .navigationBarItems(
                leading: Button(action: { station.fetchFlowerPoints() }) {
                    Image(systemName: "arrow.clockwise")
                },
                trailing: Button("完成") { dismiss() }
            )
        }
    }
}

// MARK: - 單一成熟花田卡片與路線決策
private struct FruitFlowerCard: View {
    let flower: FlowerStationPoint
    let onActionFinished: () -> Void

    @ObservedObject var session = AutoFarmSession.shared
    @ObservedObject var station = FlowerStationManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 花苞標題與倒數
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("🌸 觀測站 「\(flower.name)」")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.primary)

                        Text("可拿果實")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.15))
                            .foregroundColor(.green)
                            .cornerRadius(4)
                    }

                    Text("大果實已生成，剩餘 \(flower.remainingFormatted)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.orange)

                    if !flower.planter.isEmpty {
                        Text("種花者：\(flower.planter)")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()
            }

            Divider()

            // 智慧比對推薦路線
            let matches = station.findMatchingRoutes(for: flower)

            if matches.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("⚠️ 本地資料庫暫無此花田之專屬路線檔案")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)

                    if let coord = flower.coordinate {
                        Button(action: {
                            let singleNode = [RouteNode(lat: coord.latitude, lng: coord.longitude)]
                            session.startFruitRoute(
                                name: "跳收 \(flower.name)",
                                basePoints: singleNode,
                                loops: 0,
                                walkDistance: 80.0
                            )
                            session.showToast("🟢 已為【\(flower.name)】自動生成 80m 跳收果實路線並出發！")
                            onActionFinished()
                        }) {
                            HStack {
                                Image(systemName: "bolt.circle.fill")
                                    .foregroundColor(.orange)
                                Text("✨ 以此花田為中心自動生成 80m 跳收路線並出發")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.orange)
                                Spacer()
                            }
                            .padding(10)
                            .background(Color.orange.opacity(0.12))
                            .cornerRadius(8)
                        }

                        Button(action: {
                            session.teleport(to: coord)
                            session.showToast("已瞬移至【\(flower.name)】座標")
                            onActionFinished()
                        }) {
                            HStack {
                                Image(systemName: "location.fill")
                                Text("📍 單點瞬移至該花苞座標 (\(String(format: "%.4f", coord.latitude)), \(String(format: "%.4f", coord.longitude)))")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .foregroundColor(.blue)
                        }
                    }
                }
            } else {
                Text("📋 智慧匹配路線決策：")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.secondary)

                VStack(spacing: 8) {
                    ForEach(matches) { match in
                        if match.isHarvestRecommended {
                            // 推薦：收果實路線 (自動 80m 跳收)
                            Button(action: {
                                session.startFruitRoute(
                                    name: match.route.name,
                                    basePoints: match.route.nodes,
                                    loops: 0,
                                    walkDistance: 80.0
                                )
                                session.showToast("🟢 已啟動【\(match.route.name)】80m 跳收果實模式！")
                                onActionFinished()
                            }) {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                    Text("🟢 【推薦】\(match.route.name)（自動切換為 80m 跳收果實模式）")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundColor(.green)
                                    Spacer()
                                }
                                .padding(10)
                                .background(Color.green.opacity(0.1))
                                .cornerRadius(8)
                            }
                        } else {
                            // 原版種花或其他路線
                            Button(action: {
                                session.startFlowerRoute(
                                    name: match.route.name,
                                    basePoints: match.route.nodes,
                                    loops: 0,
                                    settings: session.flowerSettings
                                )
                                session.showToast("⚪ 已啟動【\(match.route.name)】原版種花路線！")
                                onActionFinished()
                            }) {
                                HStack {
                                    Image(systemName: "circle")
                                        .foregroundColor(.secondary)
                                    Text("⚪ \(match.route.name)（使用原版路線）")
                                        .font(.system(size: 13))
                                        .foregroundColor(.primary)
                                    Spacer()
                                }
                                .padding(8)
                                .background(Color(UIColor.secondarySystemBackground))
                                .cornerRadius(8)
                            }
                        }
                    }

                    // 暫不處理
                    Button(action: { onActionFinished() }) {
                        HStack {
                            Image(systemName: "xmark.circle")
                                .foregroundColor(.secondary)
                            Text("⚪ 暫不處理")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .padding(6)
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }
}
