import SwiftUI
import UIKit
import UniformTypeIdentifiers
import CoreLocation

public struct ControlDrawerView: View {
    @ObservedObject var session = AutoFarmSession.shared
    @ObservedObject var db = SavedDatabaseStore.shared

    @State private var isExpanded: Bool = true
    @State private var selectedTab: Int = 0 // 0: 座標資料庫, 1: 路徑資料庫

    // 檔案匯入 (GPX / CSV / TXT)
    @State private var isFileImporterPresented: Bool = false

    // 貼上文字匯入
    @State private var isPasteImportPresented: Bool = false
    @State private var pasteRouteName: String = ""
    @State private var pasteCoordinatesText: String = ""

    // 手動新增座標
    @State private var isAddLocationPresented: Bool = false
    @State private var newLocName: String = ""
    @State private var newLocLat: String = ""
    @State private var newLocLng: String = ""

    // 路線模式選擇 ActionSheet
    @State private var selectedRouteForMode: SavedRoute? = nil

    var onOpenShare: () -> Void
    var onOpenSettings: () -> Void

    public init(onOpenShare: @escaping () -> Void, onOpenSettings: @escaping () -> Void) {
        self.onOpenShare = onOpenShare
        self.onOpenSettings = onOpenSettings
    }

    public var body: some View {
        VStack(spacing: 8) {
            // 頂部抓把與收合切換列
            drawerHeader

            // 當有路線正在執行中：顯示巡航運行控制卡
            if !session.routePoints.isEmpty {
                activeRouteControlCard
            }

            // 展開時顯示資料庫內容
            if isExpanded {
                VStack(spacing: 10) {
                    // 類別選擇器 (座標資料庫 / 路徑資料庫)
                    Picker("資料庫類別", selection: $selectedTab) {
                        Text("座標資料庫 (\(db.savedLocations.count))").tag(0)
                        Text("路徑資料庫 (\(db.savedRoutes.count))").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)

                    if selectedTab == 0 {
                        locationsSection
                    } else {
                        routesSection
                    }
                }
                .transition(.opacity)
            }
        }
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(UIColor.systemBackground))
                .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: -3)
        )
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: [
                UTType(filenameExtension: "gpx") ?? .data,
                UTType.commaSeparatedText,
                UTType.plainText,
                UTType.text,
                UTType.data
            ],
            allowsMultipleSelection: false
        ) { result in
            handleFileImportResult(result)
        }
        .sheet(isPresented: $isPasteImportPresented) {
            pasteImportSheet
        }
        .sheet(isPresented: $isAddLocationPresented) {
            addLocationSheet
        }
        .actionSheet(item: $selectedRouteForMode) { route in
            routeModeActionSheet(for: route)
        }
    }

    // MARK: - 抽屜頂部把手與快捷列
    private var drawerHeader: some View {
        VStack(spacing: 6) {
            Capsule()
                .fill(Color.gray.opacity(0.35))
                .frame(width: 38, height: 4)
                .padding(.top, 4)

            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "cylinder.split.1x2.fill")
                        .foregroundColor(.blue)
                        .font(.system(size: 14))
                    Text(selectedTab == 0 ? "座標資料庫" : "路徑資料庫")
                        .font(.system(size: 15, weight: .bold))
                }

                Spacer()

                // 搖桿開關按鈕
                Button(action: {
                    withAnimation(.spring()) {
                        session.isJoystickEnabled.toggle()
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: session.isJoystickEnabled ? "gamecontroller.fill" : "gamecontroller")
                            .font(.system(size: 12))
                        Text(session.isJoystickEnabled ? "搖桿開" : "搖桿關")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(session.isJoystickEnabled ? Color.blue.opacity(0.15) : Color.gray.opacity(0.15))
                    .foregroundColor(session.isJoystickEnabled ? .blue : .secondary)
                    .cornerRadius(8)
                }

                // 設定按鈕
                Button(action: onOpenSettings) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .padding(6)
                        .background(Color(UIColor.secondarySystemBackground))
                        .clipShape(Circle())
                }

                // 展開 / 收合切換
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        isExpanded.toggle()
                    }
                }) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.secondary)
                        .padding(6)
                        .background(Color(UIColor.secondarySystemBackground))
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - 運行中巡航控制卡片
    private var activeRouteControlCard: some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                        Text(session.activeRouteName)
                            .font(.system(size: 14, weight: .bold))
                            .lineLimit(1)
                    }
                    Text("航點 \(session.currentRouteIndex + 1)/\(session.routePoints.count) | 循環 \(session.routeCurrentLoop) 圈 | 預計 \(session.etaString)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()

                // 暫停 / 繼續
                Button(action: { session.toggleRoutePause() }) {
                    HStack(spacing: 4) {
                        Image(systemName: session.isRoutePaused ? "play.fill" : "pause.fill")
                        Text(session.isRoutePaused ? "繼續" : "暫停")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(session.isRoutePaused ? Color.green : Color.orange)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }

                // 停止巡航
                Button(action: { session.stopRoute() }) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 12, weight: .bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.red.opacity(0.15))
                        .foregroundColor(.red)
                        .cornerRadius(8)
                }
            }

            // 速度調整滑桿
            HStack(spacing: 8) {
                Image(systemName: "gauge.with.needle")
                    .foregroundColor(.secondary)
                    .font(.system(size: 12))
                Slider(value: $session.speedKmh, in: 1.0...60.0, step: 0.5)
                Text("\(String(format: "%.1f", session.speedKmh)) km/h")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .frame(width: 65, alignment: .trailing)
            }
        }
        .padding(10)
        .background(Color(UIColor.secondarySystemBackground).opacity(0.85))
        .cornerRadius(12)
        .padding(.horizontal, 16)
    }

    // MARK: - 座標庫視圖
    private var locationsSection: some View {
        VStack(spacing: 6) {
            // 操作工具列
            HStack(spacing: 8) {
                // 儲存目前位置快捷鍵
                Button(action: {
                    let lat = session.currentLat
                    let lng = session.currentLng
                    db.addLocation(name: "目前位置 \(db.savedLocations.count + 1)", latitude: lat, longitude: lng)
                    session.toastMessage = "已儲存目前座標！"
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "location.badge.plus")
                        Text("儲存目前位置")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(Color.blue.opacity(0.12))
                    .foregroundColor(.blue)
                    .cornerRadius(8)
                }

                // 自訂經緯度
                Button(action: {
                    newLocName = ""
                    newLocLat = String(format: "%.6f", session.currentLat)
                    newLocLng = String(format: "%.6f", session.currentLng)
                    isAddLocationPresented = true
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                        Text("自訂座標")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color(UIColor.secondarySystemBackground))
                    .foregroundColor(.primary)
                    .cornerRadius(8)
                }
            }
            .padding(.horizontal, 16)

            // 座標清單
            ScrollView {
                LazyVStack(spacing: 6) {
                    if db.savedLocations.isEmpty {
                        Text("尚未儲存任何座標。可在地圖長按或點上方按鈕新增。")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .padding(.vertical, 24)
                    } else {
                        ForEach(db.savedLocations) { loc in
                            HStack {
                                Button(action: {
                                    session.teleport(to: loc.latitude, lng: loc.longitude)
                                }) {
                                    HStack(spacing: 10) {
                                        Image(systemName: "mappin.circle.fill")
                                            .font(.system(size: 22))
                                            .foregroundColor(.blue)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(loc.name)
                                                .font(.system(size: 14, weight: .bold))
                                                .foregroundColor(.primary)
                                            Text("\(String(format: "%.6f", loc.latitude)), \(String(format: "%.6f", loc.longitude))")
                                                .font(.system(size: 11, design: .monospaced))
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        Text("點擊瞬移")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundColor(.blue)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color.blue.opacity(0.1))
                                            .cornerRadius(6)
                                    }
                                }

                                Button(action: {
                                    db.deleteLocation(id: loc.id)
                                }) {
                                    Image(systemName: "trash")
                                        .font(.system(size: 13))
                                        .foregroundColor(.red.opacity(0.7))
                                        .padding(6)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color(UIColor.secondarySystemBackground).opacity(0.6))
                            .cornerRadius(10)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            .frame(maxHeight: 220)
        }
    }

    // MARK: - 路徑庫視圖
    private var routesSection: some View {
        VStack(spacing: 6) {
            // 檔案與文字匯入列
            HStack(spacing: 8) {
                // 1. 匯入檔案 (GPX / CSV / TXT)
                Button(action: { isFileImporterPresented = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.down.fill")
                        Text("匯入檔案 (GPX/CSV/TXT)")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(Color.purple)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }

                // 2. 貼上文字匯入
                Button(action: {
                    pasteRouteName = ""
                    pasteCoordinatesText = ""
                    isPasteImportPresented = true
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.clipboard.fill")
                        Text("貼上座標匯入")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
            }
            .padding(.horizontal, 16)

            // 路徑清單
            ScrollView {
                LazyVStack(spacing: 6) {
                    if db.savedRoutes.isEmpty {
                        Text("尚未儲存任何路線。請點擊上方按鈕匯入 GPX、CSV 或貼上座標。")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .padding(.vertical, 24)
                    } else {
                        ForEach(db.savedRoutes) { route in
                            HStack {
                                Button(action: {
                                    self.selectedRouteForMode = route
                                }) {
                                    HStack(spacing: 10) {
                                        Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                                            .font(.system(size: 18))
                                            .foregroundColor(.purple)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(route.name)
                                                .font(.system(size: 14, weight: .bold))
                                                .foregroundColor(.primary)
                                            Text("共 \(route.nodes.count) 個航點")
                                                .font(.system(size: 11))
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        Text("選擇模式 >")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundColor(.purple)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color.purple.opacity(0.1))
                                            .cornerRadius(6)
                                    }
                                }

                                Button(action: {
                                    db.deleteRoute(id: route.id)
                                }) {
                                    Image(systemName: "trash")
                                        .font(.system(size: 13))
                                        .foregroundColor(.red.opacity(0.7))
                                        .padding(6)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color(UIColor.secondarySystemBackground).opacity(0.6))
                            .cornerRadius(10)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            .frame(maxHeight: 220)
        }
    }

    // MARK: - 模式選擇 ActionSheet
    private func routeModeActionSheet(for route: SavedRoute) -> ActionSheet {
        ActionSheet(
            title: Text("【\(route.name)】共 \(route.nodes.count) 點"),
            message: Text("請選擇巡航模式立即啟動："),
            buttons: [
                .default(Text("直線巡航 (依序循環)")) {
                    session.startLinearRoute(
                        name: route.name,
                        basePoints: route.nodes,
                        loops: 0,
                        mode: session.loopMode
                    )
                },
                .default(Text("繞圈種花 (多花點雙圈28m/24m)")) {
                    session.startFlowerRoute(
                        name: route.name,
                        basePoints: route.nodes,
                        loops: 0,
                        settings: session.flowerSettings
                    )
                },
                .default(Text("跳收果實 (南北80m行走)")) {
                    session.startFruitRoute(
                        name: route.name,
                        basePoints: route.nodes,
                        loops: 0,
                        walkDistance: 80.0
                    )
                },
                .cancel(Text("取消"))
            ]
        )
    }

    // MARK: - 檔案匯入處理
    private func handleFileImportResult(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let (success, name, count, error) = db.importRouteFromFile(url: url)
            if success {
                session.toastMessage = "成功匯入路線【\(name)】共 \(count) 個航點！"
            } else {
                session.toastMessage = error ?? "匯入失敗"
            }
        case .failure(let err):
            session.toastMessage = "選取檔案失敗: \(err.localizedDescription)"
        }
    }

    // MARK: - 貼上座標匯入 Sheet
    private var pasteImportSheet: some View {
        NavigationView {
            Form {
                Section(header: Text("路線基本資訊")) {
                    TextField("輸入路線名稱 (例如：大安花區巡航)", text: $pasteRouteName)
                }

                Section(header: Text("貼上座標列表 (支援多行，格式：lat,lng)"), footer: Text("範例：\n25.033964, 121.564468\n25.034500, 121.565200\n支援以逗號、空格或分號分隔之經緯度座標。")) {
                    TextEditor(text: $pasteCoordinatesText)
                        .frame(minHeight: 180)
                        .font(.system(size: 12, design: .monospaced))
                }

                Section {
                    Button(action: {
                        let (success, count) = db.importRouteFromPastedText(name: pasteRouteName, text: pasteCoordinatesText)
                        if success {
                            isPasteImportPresented = false
                            session.toastMessage = "已匯入 \(count) 個航點！"
                        } else {
                            session.toastMessage = "未能解析出座標，請檢查格式"
                        }
                    }) {
                        HStack {
                            Spacer()
                            Text("解析並匯入路徑庫")
                                .font(.headline)
                                .foregroundColor(.white)
                            Spacer()
                        }
                    }
                    .listRowBackground(Color.blue)
                }
            }
            .navigationTitle("貼上座標匯入")
            .navigationBarItems(leading: Button("取消") { isPasteImportPresented = false })
        }
    }

    // MARK: - 手動新增座標 Sheet
    private var addLocationSheet: some View {
        NavigationView {
            Form {
                Section(header: Text("座標名稱")) {
                    TextField("例如：信義威秀大花苞", text: $newLocName)
                }
                Section(header: Text("經緯度")) {
                    TextField("緯度 (Latitude)", text: $newLocLat)
                        .keyboardType(.numbersAndPunctuation)
                    TextField("經度 (Longitude)", text: $newLocLng)
                        .keyboardType(.numbersAndPunctuation)
                }
                Section {
                    Button("儲存此座標") {
                        if let lat = Double(newLocLat), let lng = Double(newLocLng) {
                            db.addLocation(name: newLocName, latitude: lat, longitude: lng)
                            isAddLocationPresented = false
                            session.toastMessage = "座標已儲存！"
                        }
                    }
                }
            }
            .navigationTitle("新增座標")
            .navigationBarItems(leading: Button("取消") { isAddLocationPresented = false })
        }
    }
}
