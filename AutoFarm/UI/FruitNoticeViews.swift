import SwiftUI
import CoreLocation
import UIKit

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

                        Text("（\(flowersSummary())）・點擊查看路線與收果")
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

    // 收果直徑 (花心半徑為 walkDistance / 2)
    @State private var walkDistance: Double = 80.0

    // 多選勾選的花田 index 集合
    @State private var selectedFlowerIndices: Set<Int> = []

    private let distancePrefKey = "AutoFarm_FruitWalkDistance"

    public init() {}

    public var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                List {
                    // 1. 收果半徑與直徑步幅調節區塊
                    distanceSettingsSection

                    // 2. 批次全選 / 取消列
                    batchControlSection

                    // 3. 成熟花苞清單
                    matureFlowersSection
                }
                .listStyle(InsetGroupedListStyle())

                // 底部浮動：一鍵啟動所選花田依序收果
                if !selectedFlowerIndices.isEmpty {
                    bottomBatchActionBar
                }
            }
            .navigationTitle("花田果實成熟通知")
            .navigationBarItems(
                leading: Button(action: { station.fetchFlowerPoints() }) {
                    Image(systemName: "arrow.clockwise")
                },
                trailing: Button("關閉") { dismiss() }
            )
            .onAppear(perform: setupInitialState)
        }
    }

    // MARK: - 1. 收果步幅 / 半徑設定
    private var distanceSettingsSection: some View {
        Section(header: Text("收果步幅與半徑設定")) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "ruler.fill")
                        .foregroundColor(.orange)
                        .font(.system(size: 14))

                    Text("行走直徑")
                        .font(.system(size: 14, weight: .semibold))

                    Spacer()

                    Text("\(Int(walkDistance)) 公尺")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.blue)

                    Text("（半徑 \(Int(walkDistance / 2.0))m）")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

                // 快捷標籤
                HStack(spacing: 8) {
                    ForEach([40.0, 60.0, 80.0, 100.0, 120.0], id: \.self) { dist in
                        Button(action: {
                            updateDistance(dist)
                        }) {
                            Text("\(Int(dist))m")
                                .font(.system(size: 12, weight: walkDistance == dist ? .bold : .regular))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .background(walkDistance == dist ? Color.blue : Color(UIColor.secondarySystemBackground))
                                .foregroundColor(walkDistance == dist ? .white : .primary)
                                .cornerRadius(6)
                        }
                        .buttonStyle(BorderlessButtonStyle())
                    }
                }

                // Stepper 微調 (步進 10m，範圍 20m ~ 200m)
                Stepper(
                    value: Binding(
                        get: { walkDistance },
                        set: { updateDistance($0) }
                    ),
                    in: 20.0...200.0,
                    step: 10.0
                ) {
                    Text("微調步進 (±10m)")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - 2. 批次全選 / 取消列
    private var batchControlSection: some View {
        Section {
            HStack {
                let validCount = countFlowersWithRoutes()
                Text("已選取 \(selectedFlowerIndices.count) / \(validCount) 處可收花田")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)

                Spacer()

                Button("全選可收項目") {
                    selectAllValidFlowers()
                }
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.blue)
                .buttonStyle(BorderlessButtonStyle())

                Divider().frame(height: 12)

                Button("全部取消") {
                    selectedFlowerIndices.removeAll()
                }
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .buttonStyle(BorderlessButtonStyle())
            }
        }
    }

    // MARK: - 3. 成熟花苞清單
    private var matureFlowersSection: some View {
        Section(header: Text("花田果實成熟列表 (共 \(station.matureFlowers.count) 處)")) {
            if station.matureFlowers.isEmpty {
                Text("目前暫無成熟大果實花田")
                    .foregroundColor(.secondary)
                    .font(.system(size: 14))
            } else {
                ForEach(station.matureFlowers) { flower in
                    let matches = station.findMatchingRoutes(for: flower)
                    let hasRoute = !matches.isEmpty
                    let isSelected = selectedFlowerIndices.contains(flower.index)

                    FruitFlowerCard(
                        flower: flower,
                        matches: matches,
                        isSelected: isSelected,
                        walkDistance: walkDistance,
                        onToggleSelect: {
                            if hasRoute {
                                if isSelected {
                                    selectedFlowerIndices.remove(flower.index)
                                } else {
                                    selectedFlowerIndices.insert(flower.index)
                                }
                            }
                        },
                        onActionFinished: {
                            dismiss()
                        }
                    )
                }
            }
        }
    }

    // MARK: - 4. 底部浮動：一鍵啟動所選花田依序收果
    private var bottomBatchActionBar: some View {
        VStack(spacing: 0) {
            Divider()
            VStack(spacing: 8) {
                Button(action: handleStartBatchHarvest) {
                    HStack(spacing: 8) {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 18))
                        Text("🚀 啟動所選 \(selectedFlowerIndices.count) 處花田依序收果 (直徑 \(Int(walkDistance))m)")
                            .font(.system(size: 15, weight: .bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                    .shadow(color: Color.green.opacity(0.35), radius: 6, x: 0, y: 3)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(UIColor.systemBackground).opacity(0.98))
        }
    }

    // MARK: - 資料初始化與輔助邏輯
    private func setupInitialState() {
        let savedDist = UserDefaults.standard.double(forKey: distancePrefKey)
        if savedDist > 0 {
            self.walkDistance = savedDist
        }
        // 預設自動勾選所有具備路線的成熟花田
        selectAllValidFlowers()
    }

    private func updateDistance(_ newDist: Double) {
        self.walkDistance = newDist
        UserDefaults.standard.set(newDist, forKey: distancePrefKey)
    }

    private func countFlowersWithRoutes() -> Int {
        station.matureFlowers.filter { !station.findMatchingRoutes(for: $0).isEmpty }.count
    }

    private func selectAllValidFlowers() {
        let validIndices = station.matureFlowers
            .filter { !station.findMatchingRoutes(for: $0).isEmpty }
            .map { $0.index }
        self.selectedFlowerIndices = Set(validIndices)
    }

    private func handleStartBatchHarvest() {
        let selectedFlowers = station.matureFlowers.filter { selectedFlowerIndices.contains($0.index) }
        guard !selectedFlowers.isEmpty else { return }

        var combinedBaseNodes: [RouteNode] = []
        for flower in selectedFlowers {
            let matches = station.findMatchingRoutes(for: flower)
            if let best = matches.first {
                combinedBaseNodes.append(contentsOf: best.route.nodes)
            }
        }

        guard !combinedBaseNodes.isEmpty else {
            session.showToast("未能從所選花田中解析出有效路線節點")
            return
        }

        session.startFruitRoute(
            name: "觀測站批量收果 (\(selectedFlowers.count) 處)",
            basePoints: combinedBaseNodes,
            loops: 0,
            walkDistance: walkDistance
        )
        session.showToast("🟢 已啟動【\(selectedFlowers.count) 處花田】批量依序收果！")
        dismiss()
    }
}

// MARK: - 單一成熟花田卡片與路線決策
private struct FruitFlowerCard: View {
    let flower: FlowerStationPoint
    let matches: [StationRouteMatch]
    let isSelected: Bool
    let walkDistance: Double
    let onToggleSelect: () -> Void
    let onActionFinished: () -> Void

    @ObservedObject var session = AutoFarmSession.shared

    private var hasRoute: Bool {
        !matches.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 頂部花田標題與勾選框
            HStack(alignment: .top, spacing: 10) {
                // 多選勾選圓鈕
                Button(action: onToggleSelect) {
                    if hasRoute {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 22))
                            .foregroundColor(isSelected ? .green : .secondary)
                    } else {
                        Image(systemName: "slash.circle")
                            .font(.system(size: 20))
                            .foregroundColor(.gray.opacity(0.5))
                    }
                }
                .buttonStyle(BorderlessButtonStyle())
                .disabled(!hasRoute)
                .padding(.top, 2)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("🌸 「\(flower.name)」")
                            .font(.system(size: 15, weight: .bold))
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
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.orange)

                    if !flower.planter.isEmpty {
                        Text("種花者：\(flower.planter)")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()
            }

            Divider()

            // 路線決策或無路線警示
            if !hasRoute {
                // ⚠️ 無路線明確提醒
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.system(size: 14))

                        VStack(alignment: .leading, spacing: 2) {
                            Text("本地資料庫暫無此花田之路線")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.orange)
                            Text("請先至常用路線庫或群組下載/匯入對應路線後再行收果。")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }

                    // 複製花田資訊以利搜尋路線
                    Button(action: {
                        let text = flower.coordinate != nil ?
                            "\(flower.name) (\(String(format: "%.6f", flower.coordinate!.latitude)), \(String(format: "%.6f", flower.coordinate!.longitude)))" :
                            flower.name
                        UIPasteboard.general.string = text
                        session.showToast("已複製花田名稱與座標！")
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.on.doc")
                            Text("複製花田名稱與座標 (方便搜尋/建立路線)")
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.blue)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(BorderlessButtonStyle())
                }
                .padding(8)
                .background(Color.orange.opacity(0.08))
                .cornerRadius(8)
            } else {
                // 具備匹配路線時的選擇與啟動 (精簡為單一最佳推薦路線)
                if let bestMatch = matches.first(where: { $0.isHarvestRecommended }) ?? matches.first {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("📋 推薦收果路線：")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.secondary)

                        Button(action: {
                            session.startFruitRoute(
                                name: bestMatch.route.name,
                                basePoints: bestMatch.route.nodes,
                                loops: 0,
                                walkDistance: walkDistance
                            )
                            session.showToast("🟢 已啟動【\(bestMatch.route.name)】跳收果實 (直徑 \(Int(walkDistance))m)！")
                            onActionFinished()
                        }) {
                            HStack {
                                Image(systemName: bestMatch.isHarvestRecommended ? "checkmark.circle.fill" : "play.circle")
                                    .foregroundColor(bestMatch.isHarvestRecommended ? .green : .blue)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(bestMatch.isHarvestRecommended ? "🟢 【推薦】" : "⚪ ")\(bestMatch.route.name)")
                                        .font(.system(size: 13, weight: bestMatch.isHarvestRecommended ? .bold : .semibold))
                                        .foregroundColor(bestMatch.isHarvestRecommended ? .green : .primary)
                                    Text("共 \(bestMatch.route.nodes.count) 個航點・以 \(Int(walkDistance))m 直徑收果")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            .padding(10)
                            .background(bestMatch.isHarvestRecommended ? Color.green.opacity(0.08) : Color(UIColor.secondarySystemBackground))
                            .cornerRadius(8)
                        }
                        .buttonStyle(BorderlessButtonStyle())
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}
