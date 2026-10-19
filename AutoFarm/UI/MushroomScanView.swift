import SwiftUI
import CoreLocation

public struct MushroomScanView: View {
    @ObservedObject var scanManager = MushroomScanManager.shared
    @ObservedObject var logManager = MushroomLogManager.shared
    @ObservedObject var session = AutoFarmSession.shared
    @ObservedObject var db = SavedDatabaseStore.shared
    @Environment(\.dismiss) var dismiss

    @State private var selectedTab: Int = 0 // 0: 區域掃描設定, 1: 掃菇紀錄庫 (含紅點)
    @State private var scanRadiusMeters: Double = 3000.0
    @State private var gridSpacingMeters: Double = 600.0
    @State private var cruiseSpeedKmh: Double = 800.0
    @State private var autoOpenGame: Bool = true

    @State private var previewNodes: [RouteNode] = []
    @State private var customRouteName: String = "廣域掃菇巡航"

    public init() {}

    public var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Picker("掃菇模式", selection: $selectedTab) {
                    Text("區域設定").tag(0)
                    Text("掃菇紀錄 (\(logManager.records.count))\(logManager.unreadCount > 0 ? " (新)" : "")").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)

                if selectedTab == 0 {
                    scanSetupView
                } else {
                    scanRecordsView
                }
            }
            .navigationTitle("掃菇巡航助手")
            .navigationBarItems(
                leading: Button("關閉") { dismiss() },
                trailing: trailingButton
            )
            .onAppear {
                generatePreviewRoute()
                if logManager.unreadCount > 0 {
                    logManager.markAllRead()
                }
            }
        }
    }

    // MARK: - 區域掃描設定視圖
    private var scanSetupView: some View {
        Form {
            Section(header: Text("掃菇巡航狀態")) {
                if scanManager.isScanning {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("正以 \(Int(scanManager.scanSpeedKmh)) km/h 巡航掃描中")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.green)
                            Text("路線【\(scanManager.activeRouteName)】已鎖定 \(scanManager.detectedMushroomCount) 顆蘑菇")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button("停止掃菇") {
                            scanManager.stopScan()
                        }
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.red)
                        .cornerRadius(8)
                    }
                } else {
                    Text("目前未啟動掃菇。設定下方參數後點擊按鈕，系統將以 800 km/h 巡航並自動跳轉至皮克敏！")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            Section(header: Text("巡航範圍設定")) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("掃描半徑範圍")
                        Spacer()
                        Text("\(Int(scanRadiusMeters)) 公尺 (\(String(format: "%.1f", scanRadiusMeters / 1000.0)) km)")
                            .fontWeight(.bold)
                            .foregroundColor(.blue)
                    }
                    Slider(value: $scanRadiusMeters, in: 1000...10000, step: 500) { _ in
                        generatePreviewRoute()
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("S型網格間距")
                        Spacer()
                        Text("\(Int(gridSpacingMeters)) 公尺")
                            .fontWeight(.bold)
                            .foregroundColor(.purple)
                    }
                    Slider(value: $gridSpacingMeters, in: 300...1000, step: 50) { _ in
                        generatePreviewRoute()
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("巡航時速")
                        Spacer()
                        Text("\(Int(cruiseSpeedKmh)) km/h (超高速巡航)")
                            .fontWeight(.bold)
                            .foregroundColor(.orange)
                    }
                    Slider(value: $cruiseSpeedKmh, in: 200...800, step: 50)
                }

                Toggle("啟動後自動跳轉皮克敏遊戲", isOn: $autoOpenGame)
            }

            Section(header: Text("路線預覽資訊")) {
                HStack {
                    Text("以目前定位為中心點")
                    Spacer()
                    Text("\(String(format: "%.4f", session.currentLat)), \(String(format: "%.4f", session.currentLng))")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("預計覆蓋航點數")
                    Spacer()
                    Text("\(previewNodes.count) 個掃航點")
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                }
                TextField("自訂掃菇路線名稱", text: $customRouteName)
            }

            Section {
                Button(action: {
                    startScanAction()
                }) {
                    HStack {
                        Spacer()
                        Image(systemName: "bolt.horizontal.fill")
                        Text("開始掃菇巡航 (自動跳轉皮克敏)")
                            .font(.system(size: 15, weight: .bold))
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(Color.purple)
                .foregroundColor(.white)

                Button(action: {
                    saveAsRoute()
                }) {
                    HStack {
                        Spacer()
                        Image(systemName: "bookmark.fill")
                        Text("儲存此掃菇路線至路徑庫")
                            .font(.system(size: 14, weight: .bold))
                        Spacer()
                    }
                    .padding(.vertical, 2)
                }
                .foregroundColor(.blue)
            }
        }
    }

    // MARK: - 掃菇紀錄庫視圖
    private var scanRecordsView: some View {
        VStack(spacing: 0) {
            if !logManager.records.isEmpty {
                HStack {
                    Text("共記錄 \(logManager.records.count) 顆鎖定蘑菇")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button(action: {
                        logManager.clearAll()
                        session.toastMessage = "已清空掃菇紀錄"
                    }) {
                        Text("清空紀錄")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.red)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
            }

            List {
                if logManager.records.isEmpty {
                    VStack(spacing: 8) {
                        Text("尚無掃菇紀錄。")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("啟動巡航後在遊戲中看到大蘑菇時按下螢幕截圖，系統將自動解析畫面並依 800 km/h 航跡精準回推真實座標並記錄在此！")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.vertical, 40)
                    .frame(maxWidth: .infinity)
                } else {
                    ForEach(logManager.records) { rec in
                        HStack(spacing: 10) {
                            // 縮圖 (若有)
                            if let base64 = rec.cropBase64,
                               let data = Data(base64Encoded: base64),
                               let img = UIImage(data: data) {
                                Image(uiImage: img)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 44, height: 44)
                                    .cornerRadius(8)
                                    .clipped()
                            } else {
                                Image(systemName: "camera.macro")
                                    .font(.system(size: 20))
                                    .foregroundColor(.purple)
                                    .frame(width: 44, height: 44)
                                    .background(Color.purple.opacity(0.12))
                                    .cornerRadius(8)
                            }

                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 4) {
                                    Text(rec.typeName)
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(.primary)

                                    if !rec.landmark.isEmpty {
                                        Text(rec.landmark)
                                            .font(.system(size: 10))
                                            .foregroundColor(.blue)
                                            .lineLimit(1)
                                    }
                                }

                                Text("\(String(format: "%.5f", rec.lat)), \(String(format: "%.5f", rec.lng))")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.secondary)

                                Text("發現時間：\(rec.formattedTime)")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            // 一鍵瞬移至該蘑菇
                            Button(action: {
                                session.teleport(to: rec.lat, lng: rec.lng, label: rec.typeName)
                                session.toastMessage = "已瞬移至【\(rec.typeName)】座標！"
                                dismiss()
                            }) {
                                Text("瞬移")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.blue)
                                    .cornerRadius(8)
                            }

                            // 存入座標庫
                            Button(action: {
                                db.addLocation(name: rec.typeName, latitude: rec.lat, longitude: rec.lng, tag: "掃菇鎖定")
                                session.toastMessage = "已存入常用座標庫！"
                            }) {
                                Image(systemName: "bookmark")
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                                    .padding(6)
                            }
                            .buttonStyle(BorderlessButtonStyle())
                        }
                    }
                    .onDelete { indexSet in
                        for i in indexSet {
                            let id = logManager.records[i].id
                            logManager.deleteRecord(id: id)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    @ViewBuilder
    private var trailingButton: some View {
        if selectedTab == 0 && scanManager.isScanning {
            Button(action: {
                MushroomScanManager.openPikminBloom()
            }) {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.up.right.square")
                    Text("切回遊戲")
                        .font(.system(size: 12, weight: .bold))
                }
            }
        }
    }

    private func generatePreviewRoute() {
        let nodes = MushroomRouteGenerator.generateRadiusRoute(
            centerLat: session.currentLat,
            centerLng: session.currentLng,
            radiusMeters: scanRadiusMeters,
            spacingMeters: gridSpacingMeters
        )
        self.previewNodes = nodes
    }

    private func startScanAction() {
        if previewNodes.isEmpty {
            generatePreviewRoute()
        }
        guard !previewNodes.isEmpty else { return }

        let name = customRouteName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "掃菇巡航" : customRouteName
        scanManager.startScan(name: name, points: previewNodes, speedKmh: cruiseSpeedKmh, autoOpenGame: autoOpenGame)
        dismiss()
    }

    private func saveAsRoute() {
        if previewNodes.isEmpty {
            generatePreviewRoute()
        }
        guard !previewNodes.isEmpty else { return }
        let name = customRouteName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "掃菇路線" : customRouteName
        db.saveRoute(name: name, nodes: previewNodes, tag: "掃菇")
        session.toastMessage = "已將掃菇路線【\(name)】存入路徑庫 (共 \(previewNodes.count) 點)"
    }
}
