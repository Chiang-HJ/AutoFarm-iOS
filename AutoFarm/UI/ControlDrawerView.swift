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

    // 路線模式參數設定 Sheet
    @State private var selectedRouteForConfig: SavedRoute? = nil

    // 路線分享 Sheet
    @State private var routeToShare: SavedRoute? = nil
    @State private var isRouteSharePresented: Bool = false

    // 運行中動態切換路徑/座標之確認對話盒
    @State private var isSwitchConfirmPresented: Bool = false
    @State private var pendingTargetLocation: SavedLocation? = nil
    @State private var pendingTargetRoute: SavedRoute? = nil

    // 獨立速度文字輸入狀態
    @State private var speedInputText: String = "18"

    var onOpenShare: () -> Void
    var onOpenSettings: () -> Void

    public init(onOpenShare: @escaping () -> Void, onOpenSettings: @escaping () -> Void) {
        self.onOpenShare = onOpenShare
        self.onOpenSettings = onOpenSettings
    }

    public var body: some View {
        VStack(spacing: 8) {
            // 頂部抓把與抽屜標題列
            drawerHeader

            // 運行中巡航卡片 (對齊安卓懸浮球功能按鍵)
            if !session.routePoints.isEmpty {
                activeRouteControlCard
            } else {
                // 平時待命時的獨立速度調整區塊 (純輸入框，支援收起鍵盤，無快捷鍵)
                idleSpeedControlSection
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
        .sheet(item: $selectedRouteForConfig) { route in
            RouteModeConfigSheet(route: route) { mode, loopMode, loops, flowerSettings, fruitWalkDist in
                executeSelectedRoute(route: route, mode: mode, loopMode: loopMode, loops: loops, flowerSettings: flowerSettings, fruitWalkDist: fruitWalkDist)
            }
        }
        .sheet(isPresented: $isRouteSharePresented) {
            if let r = routeToShare {
                SingleRouteShareSheet(route: r)
            } else {
                RouteShareView()
            }
        }
        .alert(isPresented: $isSwitchConfirmPresented) {
            switchConfirmationAlert
        }
        .onAppear {
            speedInputText = String(format: "%.1f", session.speedKmh)
        }
    }

    // MARK: - 抽屜頂部把手與標題列
    private var drawerHeader: some View {
        VStack(spacing: 6) {
            Capsule()
                .fill(Color.gray.opacity(0.35))
                .frame(width: 38, height: 4)
                .padding(.top, 4)

            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "folder.fill")
                        .foregroundColor(.blue)
                        .font(.system(size: 14))
                    Text(selectedTab == 0 ? "座標資料庫" : "路徑資料庫")
                        .font(.system(size: 15, weight: .bold))
                }

                Spacer()

                // 設定按鈕
                Button(action: {
                    hideKeyboard()
                    onOpenSettings()
                }) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .padding(6)
                        .background(Color(UIColor.secondarySystemBackground))
                        .clipShape(Circle())
                }

                // 展開 / 收合切換
                Button(action: {
                    hideKeyboard()
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

    // MARK: - 平時待命時的獨立速度調整區塊 (純文字輸入框，支援收起鍵盤，已移除快捷鍵)
    private var idleSpeedControlSection: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "gauge.with.needle")
                    .foregroundColor(.blue)
                    .font(.system(size: 14))
                Text("移動時速:")
                    .font(.system(size: 13, weight: .semibold))
            }

            // 純數字輸入框
            HStack(spacing: 4) {
                TextField("18.0", text: $speedInputText, onCommit: commitSpeedInput)
                    .keyboardType(.decimalPad)
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .frame(width: 75)
                    .padding(.vertical, 5)
                    .background(Color(UIColor.tertiarySystemBackground))
                    .cornerRadius(8)

                Text("km/h")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            Spacer()

            // 鍵盤完成收起按鈕
            Button(action: {
                commitSpeedInput()
                hideKeyboard()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                    Text("完成")
                        .font(.system(size: 12, weight: .bold))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(UIColor.secondarySystemBackground).opacity(0.85))
        .cornerRadius(12)
        .padding(.horizontal, 16)
    }

    private func commitSpeedInput() {
        if let val = Double(speedInputText), val > 0 {
            session.speedKmh = min(max(val, 0.5), 120.0)
            speedInputText = String(format: "%.1f", session.speedKmh)
        } else {
            speedInputText = String(format: "%.1f", session.speedKmh)
        }
    }

    // MARK: - 運行中巡航卡片 (完全對齊安卓懸浮球按鍵)
    private var activeRouteControlCard: some View {
        VStack(spacing: 10) {
            // 1. 路線資訊列
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(session.isRoutePaused ? Color.orange : Color.green)
                            .frame(width: 8, height: 8)
                        Text(session.activeRouteName)
                            .font(.system(size: 14, weight: .bold))
                            .lineLimit(1)
                        Text(session.isRoutePaused ? "(已暫停)" : "(運行中)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(session.isRoutePaused ? .orange : .green)
                    }

                    let currentDisp = session.currentDisplayIndex + 1
                    let totalDisp = session.displayWaypoints.count
                    let labelType = (session.executionMode == 1) ? "花苞" : "航點"

                    Text("\(labelType) \(currentDisp)/\(totalDisp) | 循環第 \(session.routeCurrentLoop + 1) 圈 | 預計 \(session.etaString)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Spacer()

                // 即時時速輸入框與完成收鍵盤按鈕
                HStack(spacing: 4) {
                    TextField("18", text: $speedInputText, onCommit: {
                        commitSpeedInput()
                        hideKeyboard()
                    })
                    .keyboardType(.decimalPad)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .frame(width: 50)
                    .padding(.vertical, 3)
                    .background(Color(UIColor.tertiarySystemBackground))
                    .cornerRadius(6)

                    Text("km/h")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    Button(action: {
                        commitSpeedInput()
                        hideKeyboard()
                    }) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.blue)
                    }
                }
            }

            Divider()

            // 2. 安卓懸浮球功能按鈕陣列
            // 第一排：暫停/繼續、上一點、下一點、路線中心、暫存進度
            HStack(spacing: 8) {
                // 暫停 / 繼續
                Button(action: {
                    hideKeyboard()
                    session.toggleRoutePause()
                }) {
                    VStack(spacing: 3) {
                        Image(systemName: session.isRoutePaused ? "play.fill" : "pause.fill")
                            .font(.system(size: 15))
                        Text(session.isRoutePaused ? "繼續" : "暫停")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(session.isRoutePaused ? Color.green : Color.orange)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }

                // 上一點
                Button(action: {
                    hideKeyboard()
                    session.prevRoutePoint()
                }) {
                    VStack(spacing: 3) {
                        Image(systemName: "backward.end.fill")
                            .font(.system(size: 14))
                        Text("上一點")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(Color(UIColor.tertiarySystemBackground))
                    .foregroundColor(.primary)
                    .cornerRadius(8)
                }

                // 下一點
                Button(action: {
                    hideKeyboard()
                    session.nextRoutePoint()
                }) {
                    VStack(spacing: 3) {
                        Image(systemName: "forward.end.fill")
                            .font(.system(size: 14))
                        Text("下一點")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(Color(UIColor.tertiarySystemBackground))
                    .foregroundColor(.primary)
                    .cornerRadius(8)
                }

                // 路線中心 (自動暫停並瞬移中心)
                Button(action: {
                    hideKeyboard()
                    session.centerOnRoute()
                }) {
                    VStack(spacing: 3) {
                        Image(systemName: "scope")
                            .font(.system(size: 14))
                        Text("路線中心")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(Color.purple.opacity(0.15))
                    .foregroundColor(.purple)
                    .cornerRadius(8)
                }

                // 暫存進度
                Button(action: {
                    hideKeyboard()
                    session.saveProgress()
                }) {
                    VStack(spacing: 3) {
                        Image(systemName: "square.and.arrow.down.fill")
                            .font(.system(size: 14))
                        Text("暫存進度")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(Color.blue.opacity(0.15))
                    .foregroundColor(.blue)
                    .cornerRadius(8)
                }
            }

            // 第二排：路線全覽、分享路線、停止路線、恢復真實GPS
            HStack(spacing: 8) {
                // 路線全覽
                Button(action: {
                    hideKeyboard()
                    session.fitCameraToRouteBounds()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 12))
                        Text("路線全覽")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(Color(UIColor.tertiarySystemBackground))
                    .foregroundColor(.primary)
                    .cornerRadius(8)
                }

                // 分享路線
                Button(action: {
                    hideKeyboard()
                    if let saved = db.savedRoutes.first(where: { $0.name == session.activeRouteName }) {
                        self.routeToShare = saved
                    } else {
                        self.routeToShare = SavedRoute(id: UUID(), name: session.activeRouteName, nodes: session.originalBasePoints)
                    }
                    self.isRouteSharePresented = true
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 12))
                        Text("分享路線")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(Color.blue.opacity(0.15))
                    .foregroundColor(.blue)
                    .cornerRadius(8)
                }

                // 停止路線 (保留當前虛擬位置)
                Button(action: {
                    hideKeyboard()
                    session.stopRoute()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 12))
                        Text("停止路線")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(Color.red.opacity(0.15))
                    .foregroundColor(.red)
                    .cornerRadius(8)
                }

                // 恢復真實 GPS (重置 locationd)
                Button(action: {
                    hideKeyboard()
                    session.stopMocking()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "location.slash.fill")
                            .font(.system(size: 12))
                        Text("還原GPS")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(Color.gray.opacity(0.18))
                    .foregroundColor(.primary)
                    .cornerRadius(8)
                }
            }
        }
        .padding(12)
        .background(Color(UIColor.secondarySystemBackground).opacity(0.85))
        .cornerRadius(14)
        .padding(.horizontal, 16)
    }

    // MARK: - 座標庫視圖
    private var locationsSection: some View {
        VStack(spacing: 6) {
            // 操作工具列
            HStack(spacing: 8) {
                // 儲存目前位置快捷鍵
                Button(action: {
                    hideKeyboard()
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
                    hideKeyboard()
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
                                    hideKeyboard()
                                    handleLocationClick(loc)
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
                                    hideKeyboard()
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
                Button(action: {
                    hideKeyboard()
                    isFileImporterPresented = true
                }) {
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
                    hideKeyboard()
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
                                // 路線點擊設定模式
                                Button(action: {
                                    hideKeyboard()
                                    handleRouteClick(route)
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
                                        Text("設定參數 >")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundColor(.purple)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color.purple.opacity(0.1))
                                            .cornerRadius(6)
                                    }
                                }

                                // 路線專屬分享按鈕
                                Button(action: {
                                    hideKeyboard()
                                    self.routeToShare = route
                                    self.isRouteSharePresented = true
                                }) {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.system(size: 13))
                                        .foregroundColor(.blue)
                                        .padding(6)
                                }

                                // 刪除按鈕
                                Button(action: {
                                    hideKeyboard()
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

    // MARK: - 運行中切換邏輯
    private func handleLocationClick(_ loc: SavedLocation) {
        if !session.routePoints.isEmpty {
            pendingTargetLocation = loc
            pendingTargetRoute = nil
            isSwitchConfirmPresented = true
        } else {
            session.teleport(to: loc.latitude, lng: loc.longitude)
        }
    }

    private func handleRouteClick(_ route: SavedRoute) {
        if !session.routePoints.isEmpty {
            pendingTargetRoute = route
            pendingTargetLocation = nil
            isSwitchConfirmPresented = true
        } else {
            selectedRouteForConfig = route
        }
    }

    private var switchConfirmationAlert: Alert {
        Alert(
            title: Text("正在運行路線【\(session.activeRouteName)】"),
            message: Text("是否要切換目標？請選擇是否暫存目前進度："),
            primaryButton: .default(Text("存檔進度並切換")) {
                session.saveProgress()
                applyPendingSwitch()
            },
            secondaryButton: .destructive(Text("直接切換 (不存檔)")) {
                session.stopRoute()
                applyPendingSwitch()
            }
        )
    }

    private func applyPendingSwitch() {
        if let loc = pendingTargetLocation {
            session.teleport(to: loc.latitude, lng: loc.longitude)
            session.isRoutePaused = true
            pendingTargetLocation = nil
        } else if let route = pendingTargetRoute {
            selectedRouteForConfig = route
            pendingTargetRoute = nil
        }
    }

    // MARK: - 執行選定路線
    private func executeSelectedRoute(
        route: SavedRoute,
        mode: Int,
        loopMode: LoopMode,
        loops: Int,
        flowerSettings: MultiFlowerSettings,
        fruitWalkDist: Double
    ) {
        switch mode {
        case 0:
            session.startLinearRoute(
                name: route.name,
                basePoints: route.nodes,
                loops: loops,
                mode: loopMode
            )
        case 1:
            session.startFlowerRoute(
                name: route.name,
                basePoints: route.nodes,
                loops: loops,
                settings: flowerSettings
            )
        case 2:
            session.startFruitRoute(
                name: route.name,
                basePoints: route.nodes,
                loops: loops,
                walkDistance: fruitWalkDist
            )
        default:
            break
        }
    }

    // MARK: - 檔案匯入處理
    private func handleFileImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
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

/// 全域收起鍵盤擴展
extension View {
    public func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
