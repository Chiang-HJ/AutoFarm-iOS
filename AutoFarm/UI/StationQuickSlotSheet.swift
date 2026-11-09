import SwiftUI

/// 觀測站花田快速卡位與巡航開跑彈窗 (支援由主地圖或觀測站總覽直接調起)
public struct StationQuickSlotSheet: View {
    let point: FlowerStationPoint
    var onDismiss: () -> Void

    @ObservedObject var station = FlowerStationManager.shared
    @ObservedObject var session = AutoFarmSession.shared
    @Environment(\.dismiss) var dismiss

    @State private var inputNickname: String = ""
    @State private var inputRemark: String = ""
    @State private var selectedRouteName: String = ""
    @State private var isSubmittingSlot: Bool = false

    public init(point: FlowerStationPoint, onDismiss: @escaping () -> Void = {}) {
        self.point = point
        self.onDismiss = onDismiss
    }

    public var body: some View {
        NavigationView {
            Form {
                Section(header: Text("花田資訊")) {
                    HStack {
                        Text("花田名稱")
                        Spacer()
                        Text(point.name).bold()
                    }
                    if let s = point.seedlings {
                        HStack {
                            Text("苗數規格")
                            Spacer()
                            Text("\(s) 苗").foregroundColor(.secondary)
                        }
                    }
                    HStack {
                        Text("目前狀態")
                        Spacer()
                        if point.isCounting {
                            Text("冷卻中 (剩餘 \(formatSeconds(point.remainingSeconds)))")
                                .bold()
                                .foregroundColor(.red)
                        } else if let occ = point.occupierUid, !occ.isEmpty {
                            Text("由 \(point.planter.isEmpty ? "他人" : point.planter) 佔用中")
                                .bold()
                                .foregroundColor(.orange)
                        } else {
                            Text("空間待命")
                                .bold()
                                .foregroundColor(.green)
                        }
                    }
                }

                Section(header: Text("卡位參數")) {
                    HStack {
                        Text("卡位暱稱")
                        TextField("輸入卡位者暱稱", text: $inputNickname)
                            .multilineTextAlignment(.trailing)
                    }

                    HStack {
                        Text("自訂備註")
                        TextField("如：預計下午開花 (選填)", text: $inputRemark)
                            .multilineTextAlignment(.trailing)
                    }
                }

                Section(header: Text("推薦巡航路線")) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(selectedRouteName.isEmpty ? "尚未匹配到路線" : selectedRouteName)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.primary)

                            if let r = SavedDatabaseStore.shared.savedRoutes.first(where: { $0.name == selectedRouteName }) {
                                Text("共 \(r.nodes.count) 個航點・繞圈種花模式")
                                    .font(.system(size: 11))
                                    .foregroundColor(.orange)
                            }
                        }

                        Spacer()

                        Menu {
                            let matches = station.findMatchingRoutes(for: point)
                            if !matches.isEmpty {
                                Text("智慧匹配路線").font(.caption)
                                ForEach(matches) { m in
                                    Button(action: {
                                        selectedRouteName = m.route.name
                                        station.setPreferredRouteName(m.route.name, for: point.name)
                                        session.showToast("已更正並記住【\(point.name)】推薦路線為【\(m.route.name)】")
                                    }) {
                                        HStack {
                                            Text(m.route.name)
                                            if m.route.name == selectedRouteName {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                                Divider()
                            }

                            Text("全部路徑庫").font(.caption)
                            ForEach(SavedDatabaseStore.shared.savedRoutes) { r in
                                Button(action: {
                                    selectedRouteName = r.name
                                    station.setPreferredRouteName(r.name, for: point.name)
                                    session.showToast("已更正並記住【\(point.name)】推薦路線為【\(r.name)】")
                                }) {
                                    Text(r.name)
                                }
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "pencil.circle.fill")
                                Text("更正")
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.orange)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.orange.opacity(0.12))
                            .cornerRadius(6)
                        }
                    }
                }

                Section {
                    // 1. 瞬移至此
                    if let coord = point.coordinate {
                        Button(action: {
                            session.teleport(to: coord, label: point.name)
                            closeSheet()
                        }) {
                            HStack {
                                Image(systemName: "location.fill")
                                    .foregroundColor(.blue)
                                Text("瞬移至此花田中心")
                                    .foregroundColor(.primary)
                            }
                        }
                    }

                    // 2. 一鍵卡位
                    Button(action: {
                        submitSlotting(startCruise: false)
                    }) {
                        HStack {
                            Image(systemName: "person.badge.shield.checkmark.fill")
                                .foregroundColor(.green)
                            Text(isSubmittingSlot ? "正在卡位..." : "一鍵卡位 (保留花田)")
                                .foregroundColor(.green)
                                .bold()
                        }
                    }
                    .disabled(isSubmittingSlot)

                    // 3. 一鍵卡位並自動開跑巡航
                    Button(action: {
                        submitSlotting(startCruise: true)
                    }) {
                        HStack {
                            Image(systemName: "play.circle.fill")
                                .foregroundColor(.orange)
                            Text(isSubmittingSlot ? "正在處理..." : "一鍵卡位並開跑巡航")
                                .foregroundColor(.orange)
                                .bold()
                        }
                    }
                    .disabled(isSubmittingSlot)
                }
            }
            .navigationTitle(point.name)
            .navigationBarItems(trailing: Button("關閉") { closeSheet() })
            .onAppear {
                let name = station.stationDisplayName
                self.inputNickname = !name.isEmpty ? name : station.stationEmail
                self.inputRemark = ""
                let matches = station.findMatchingRoutes(for: point)
                let pref = station.getPreferredRouteName(for: point.name)
                let best = matches.first(where: { $0.route.name == pref }) ?? matches.first
                self.selectedRouteName = best?.route.name ?? (pref ?? "")
            }
        }
    }

    private func closeSheet() {
        onDismiss()
        dismiss()
    }

    private func submitSlotting(startCruise: Bool) {
        guard !inputNickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            session.showToast("請輸入卡位暱稱")
            return
        }

        isSubmittingSlot = true
        let nickname = inputNickname.trimmingCharacters(in: .whitespacesAndNewlines)
        let remark = inputRemark.trimmingCharacters(in: .whitespacesAndNewlines)

        station.occupySpot(pointIndex: point.index, pointName: point.name, planterNickname: nickname, durationHours: 23.0, isHidden: false, remark: remark) { success, msg in
            isSubmittingSlot = false
            if success {
                session.showToast("已成功卡位【\(point.name)】！")

                if startCruise {
                    if !self.selectedRouteName.isEmpty,
                       let chosenRoute = SavedDatabaseStore.shared.savedRoutes.first(where: { $0.name == self.selectedRouteName }) {
                        self.station.setPreferredRouteName(chosenRoute.name, for: point.name)
                        // 以繞圈種花模式開跑 (executionMode = 1)
                        self.session.startFlowerRoute(
                            name: chosenRoute.name,
                            basePoints: chosenRoute.nodes,
                            loops: 0,
                            settings: self.session.flowerSettings
                        )
                        SavedDatabaseStore.shared.useRoute(name: chosenRoute.name)
                        self.session.showToast("已卡位並啟動【\(chosenRoute.name)】繞圈種花巡航！")
                    } else if let coord = point.coordinate {
                        self.session.teleport(to: coord, label: point.name)
                        SavedDatabaseStore.shared.addTeleportHistory(
                            lat: coord.latitude,
                            lng: coord.longitude,
                            label: "觀測站【\(point.name)】"
                        )
                        self.session.showToast("已卡位並瞬移至【\(point.name)】花田中心")
                    }
                    closeSheet()
                } else {
                    closeSheet()
                }
            } else {
                session.showToast("卡位失敗：\(msg)")
            }
        }
    }

    private func formatSeconds(_ sec: Int) -> String {
        let h = sec / 3600
        let m = (sec % 3600) / 60
        return "\(h)時\(m)分"
    }
}
