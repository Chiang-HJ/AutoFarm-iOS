import SwiftUI
import UIKit
import UniformTypeIdentifiers
import CoreLocation

public struct ControlDrawerView: View {
    @ObservedObject var session = AutoFarmSession.shared
    @ObservedObject var db = SavedDatabaseStore.shared

    @State private var isExpanded: Bool = true
    @State private var selectedTab: Int = 0 // 0: 座標資料庫, 1: 路徑資料庫, 2: 瞬移紀錄

    // 檔案匯入 (GPX / CSV / TXT)
    @State private var isFileImporterPresented: Bool = false

    // 貼上文字匯入
    @State private var isPasteImportPresented: Bool = false
    @State private var pasteRouteName: String = ""
    @State private var pasteRouteTag: String = ""
    @State private var pasteCoordinatesText: String = ""

    // 手動新增座標
    @State private var isAddLocationPresented: Bool = false
    @State private var newLocName: String = ""
    @State private var newLocTag: String = ""
    @State private var newLocLat: String = ""
    @State private var newLocLng: String = ""

    // 編輯標籤 Sheet
    @State private var isEditTagPresented: Bool = false
    @State private var editingItemId: UUID? = nil
    @State private var editingItemIsRoute: Bool = false
    @State private var editingItemTitle: String = ""
    @State private var editingTagText: String = ""

    // 路線模式參數設定 Sheet
    @State private var selectedRouteForConfig: SavedRoute? = nil
    @State private var routeToEdit: SavedRoute? = nil

    // 路線分享 Sheet
    @State private var routeToShare: SavedRoute? = nil
    @State private var isRouteSharePresented: Bool = false

    // 卡菇清單 Sheet
    @State private var isBlockedMushroomPresented: Bool = false

    // 運行中動態切換路線確認對話盒
    @State private var isRouteSwitchConfirmPresented: Bool = false
    @State private var pendingTargetRoute: SavedRoute? = nil

    // 暫存進度詢問對話盒 (接續上次進度 vs 從頭全新開始)
    @State private var isResumeRouteChoicePresented: Bool = false
    @State private var routeForResumeChoice: SavedRoute? = nil

    // 獨立速度文字輸入狀態
    @State private var speedInputText: String = "18"
    @State private var showJumpPointAlert: Bool = false
    @State private var jumpPointInputText: String = ""

    // 自由拖曳抽屜高度狀態 (緊湊 130, 半高 380, 全螢幕 640)
    @State private var drawerHeight: CGFloat = 380
    @GestureState private var dragOffset: CGFloat = 0

    // 儲存目前位置命名詢問彈窗 (留空自動反向地理編碼國家地名)
    @State private var isSaveLocationAlertPresented: Bool = false
    @State private var saveLocationNameInput: String = ""

    // 資料庫全備份匯出與還原 (相容 APK / IPA)
    @State private var isBackupImporterPresented: Bool = false
    @State private var exportBackupURL: URL? = nil
    @State private var isExportSharePresented: Bool = false

    // 搜尋與排序 (預設以最近使用優先排序，持久化記憶)
    @State private var locationSearchText: String = ""
    @State private var routeSearchText: String = ""
    @State private var locationSortMode: DatabaseSortMode = {
        if let raw = UserDefaults.standard.string(forKey: "Drawer_LocationSortMode"),
           let mode = DatabaseSortMode(rawValue: raw) {
            return mode
        }
        return .recentlyUsed
    }()
    @State private var routeSortMode: DatabaseSortMode = {
        if let raw = UserDefaults.standard.string(forKey: "Drawer_RouteSortMode"),
           let mode = DatabaseSortMode(rawValue: raw) {
            return mode
        }
        return .recentlyUsed
    }()

    // 重新命名
    @State private var isRenamePresented: Bool = false
    @State private var renameTargetId: UUID? = nil
    @State private var renameTargetIsRoute: Bool = false
    @State private var renameInputText: String = ""

    // 花田總覽地圖
    @State private var isOverviewMapPresented: Bool = false

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
                VStack(spacing: 8) {
                    if selectedTab == 0 {
                        locationsSection
                    } else if selectedTab == 1 {
                        routesSection
                    } else {
                        locationHistorySection
                    }

                    // 最下方的三個 Tab 導覽列
                    bottomTabBar
                }
                .transition(.opacity)
            }
        }
        .frame(height: max(130, min(UIScreen.main.bounds.height - 80, drawerHeight)), alignment: .top)
        .offset(y: dragOffset)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(UIColor.systemBackground))
                .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: -3)
                .padding(.bottom, -400)
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
            allowsMultipleSelection: true
        ) { result in
            handleFileImportResult(result)
        }
        .sheet(isPresented: $isPasteImportPresented) {
            pasteImportSheet
        }
        .sheet(isPresented: $isAddLocationPresented) {
            addLocationSheet
        }
        .sheet(isPresented: $isEditTagPresented) {
            editTagSheet
        }
        .sheet(item: $selectedRouteForConfig) { route in
            RouteModeConfigSheet(route: route) { mode, loopMode, loops, flowerSettings, fruitWalkDist in
                executeSelectedRoute(route: route, mode: mode, loopMode: loopMode, loops: loops, flowerSettings: flowerSettings, fruitWalkDist: fruitWalkDist)
            }
        }
        .sheet(item: $routeToEdit) { route in
            RouteEditorView(route: route)
        }
        .sheet(isPresented: $isRouteSharePresented) {
            RouteShareView(initialRoute: routeToShare)
        }
        .sheet(isPresented: $isBlockedMushroomPresented) {
            BlockedMushroomView()
        }
        .sheet(isPresented: $isOverviewMapPresented) {
            FlowerStationMapView()
        }
        .alert("重新命名", isPresented: $isRenamePresented) {
            TextField("輸入新名稱", text: $renameInputText)
            Button("確認儲存") {
                if let targetId = renameTargetId, !renameInputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    if renameTargetIsRoute {
                        db.renameRoute(id: targetId, newName: renameInputText)
                    } else {
                        db.renameLocation(id: targetId, newName: renameInputText)
                    }
                }
            }
            Button("取消", role: .cancel) {}
        }
        .alert("儲存目前座標", isPresented: $isSaveLocationAlertPresented) {
            TextField("輸入座標名稱 (留空自動使用國家/地區名)", text: $saveLocationNameInput)
            Button("確認儲存") {
                let lat = session.currentLat
                let lng = session.currentLng
                let customName = saveLocationNameInput.trimmingCharacters(in: .whitespacesAndNewlines)
                if !customName.isEmpty {
                    db.addLocation(name: customName, latitude: lat, longitude: lng)
                    if let lastId = db.savedLocations.last?.id {
                        db.useLocation(id: lastId)
                    }
                    session.showToast("已儲存座標：\(customName)")
                } else {
                    let loc = CLLocation(latitude: lat, longitude: lng)
                    CLGeocoder().reverseGeocodeLocation(loc) { placemarks, _ in
                        var geoName = ""
                        if let p = placemarks?.first {
                            let parts = [p.country, p.administrativeArea, p.locality ?? p.subLocality, p.thoroughfare].compactMap { $0 }.filter { !$0.isEmpty }
                            geoName = parts.joined(separator: " ")
                        }
                        let finalName = geoName.isEmpty ? String(format: "目前位置 (%.4f, %.4f)", lat, lng) : geoName
                        DispatchQueue.main.async {
                            self.db.addLocation(name: finalName, latitude: lat, longitude: lng)
                            if let lastId = self.db.savedLocations.last?.id {
                                self.db.useLocation(id: lastId)
                            }
                            self.session.showToast("已儲存座標：\(finalName)")
                        }
                    }
                }
            }
            Button("取消", role: .cancel) {}
        }
        .fileImporter(
            isPresented: $isBackupImporterPresented,
            allowedContentTypes: [UTType.json, UTType.data, UTType.plainText],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                let res = db.restoreFullBackup(from: url, merge: true)
                session.showToast(res.message, isError: !res.success)
            case .failure(let err):
                session.showToast("讀取備份失敗：\(err.localizedDescription)", isError: true)
            }
        }
        .sheet(isPresented: $isExportSharePresented) {
            if let url = exportBackupURL {
                ActivityViewController(activityItems: [url])
            }
        }
        .actionSheet(isPresented: $isResumeRouteChoicePresented) {
            resumeRouteActionSheet
        }
        .onAppear {
            speedInputText = String(format: "%.1f", session.speedKmh)
        }
    }


    private var displayedLocations: [SavedLocation] {
        db.filteredLocations(query: locationSearchText, sortMode: locationSortMode)
    }

    private var displayedRoutes: [SavedRoute] {
        db.filteredRoutes(query: routeSearchText, sortMode: routeSortMode)
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
                    Image(systemName: headerIconName)
                        .foregroundColor(.blue)
                        .font(.system(size: 14))
                    Text(headerTitle)
                        .font(.system(size: 15, weight: .bold))
                }

                Spacer()

                // 花田總覽地圖按鈕
                Button(action: {
                    hideKeyboard()
                    isOverviewMapPresented = true
                }) {
                    Image(systemName: "map.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.blue)
                        .padding(6)
                        .background(Color.blue.opacity(0.12))
                        .clipShape(Circle())
                }

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

                // 展開 / 收合切換 (點擊切換 130 <-> 380)
                Button(action: {
                    hideKeyboard()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        isExpanded.toggle()
                        drawerHeight = isExpanded ? 380 : 130
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
        .contentShape(Rectangle())
        .gesture(
            DragGesture()
                .updating($dragOffset) { value, state, _ in
                    state = value.translation.height
                }
                .onEnded { value in
                    let rawHeight = drawerHeight - value.translation.height
                    let snapPoints: [CGFloat] = [130, 380, 640]
                    let target = snapPoints.min(by: { abs($0 - rawHeight) < abs($1 - rawHeight) }) ?? 380
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        drawerHeight = target
                        isExpanded = target > 140
                    }
                }
        )
    }

    private var headerTitle: String {
        switch selectedTab {
        case 0: return "座標資料庫"
        case 1: return "路徑資料庫"
        default: return "瞬移歷史紀錄"
        }
    }

    private var headerIconName: String {
        switch selectedTab {
        case 0: return "mappin.circle.fill"
        case 1: return "folder.fill"
        default: return "clock.arrow.circlepath"
        }
    }

    // MARK: - 平時待命時的獨立速度調整區塊 (純文字輸入框，支援收起鍵盤，無快捷鍵)
    private var idleSpeedControlSection: some View {
        HStack(spacing: 8) {
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
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .frame(width: 55)
                    .padding(.vertical, 5)
                    .background(Color(UIColor.tertiarySystemBackground))
                    .cornerRadius(8)

                Text("km/h")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            // 鍵盤完成收起按鈕
            Button(action: {
                commitSpeedInput()
                hideKeyboard()
            }) {
                Text("完成")
                    .font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }

            // 卡菇清單快捷按鈕 (對齊安卓卡菇定時管理)
            Button(action: {
                hideKeyboard()
                self.isBlockedMushroomPresented = true
            }) {
                HStack(spacing: 3) {
                    Image(systemName: "timer")
                        .font(.system(size: 11, weight: .bold))
                    Text("卡菇")
                        .font(.system(size: 11, weight: .bold))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.purple.opacity(0.15))
                .foregroundColor(.purple)
                .cornerRadius(8)
            }

            // 停止虛擬定位還原真實 GPS
            Button(action: {
                hideKeyboard()
                session.stopMocking()
            }) {
                HStack(spacing: 3) {
                    Image(systemName: "location.slash.fill")
                        .font(.system(size: 11, weight: .bold))
                    Text("還原GPS")
                        .font(.system(size: 11, weight: .bold))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.red.opacity(0.15))
                .foregroundColor(.red)
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

                    HStack(spacing: 6) {
                        Text("\(labelType) \(currentDisp)/\(totalDisp) | 循環第 \(session.routeCurrentLoop + 1) 圈 | 預計 \(session.etaString)")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)

                        Button(action: {
                            hideKeyboard()
                            jumpPointInputText = "\(currentDisp)"
                            showJumpPointAlert = true
                        }) {
                            HStack(spacing: 2) {
                                Image(systemName: "number")
                                Text("跳點")
                            }
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.15))
                            .foregroundColor(.blue)
                            .cornerRadius(4)
                        }
                    }
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
                // 暫停 / 繼續 (方案 A: 若有臨時瞬移插隊，按繼續自動返回出發點繼續)
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

                // 輸入跳點
                Button(action: {
                    hideKeyboard()
                    jumpPointInputText = "\(session.currentDisplayIndex + 1)"
                    showJumpPointAlert = true
                }) {
                    VStack(spacing: 3) {
                        Image(systemName: "number.circle.fill")
                            .font(.system(size: 14))
                        Text("輸入跳點")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(Color.blue.opacity(0.15))
                    .foregroundColor(.blue)
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

                // 停止路線 (長按蓄力確認，保留當前虛擬位置)
                HoldToConfirmButton(
                    title: "停止路線",
                    icon: "stop.fill",
                    color: .red,
                    duration: 0.8
                ) {
                    hideKeyboard()
                    session.stopRoute()
                }

                // 恢復真實 GPS (長按蓄力確認，重置 locationd)
                HoldToConfirmButton(
                    title: "還原GPS",
                    icon: "location.slash.fill",
                    color: .red,
                    duration: 0.8
                ) {
                    hideKeyboard()
                    session.stopMocking()
                }
            }
        }
        .padding(12)
        .background(Color(UIColor.secondarySystemBackground).opacity(0.85))
        .cornerRadius(14)
        .padding(.horizontal, 16)
        .alert("輸入點位數字跳點", isPresented: $showJumpPointAlert) {
            TextField("點位編號 (1 ~ \(session.displayWaypoints.count))", text: $jumpPointInputText)
                .keyboardType(.numberPad)
            Button("確定跳轉") {
                if let num = Int(jumpPointInputText.trimmingCharacters(in: .whitespacesAndNewlines)),
                   num >= 1, num <= session.displayWaypoints.count {
                    session.jumpToWaypoint(index: num - 1)
                } else {
                    session.showToast("請輸入 1 ~ \(session.displayWaypoints.count) 之間的點位編號")
                }
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text("有效範圍：1 ~ \(session.displayWaypoints.count) 點")
        }
    }

    // MARK: - 最底部三 Tab 導覽列
    private var bottomTabBar: some View {
        HStack(spacing: 6) {
            tabButton(title: "座標", count: db.savedLocations.count, icon: "location.fill", tabIndex: 0)
            tabButton(title: "路線", count: db.savedRoutes.count, icon: "point.topleft.down.curvedto.point.bottomright.up", tabIndex: 1)
            tabButton(title: "歷史紀錄", count: db.locationHistory.count, icon: "clock.arrow.circlepath", tabIndex: 2)
        }
        .padding(4)
        .background(Color(UIColor.secondarySystemBackground).opacity(0.95))
        .cornerRadius(12)
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }

    private func tabButton(title: String, count: Int, icon: String, tabIndex: Int) -> some View {
        let isSelected = selectedTab == tabIndex
        return Button(action: {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                selectedTab = tabIndex
            }
        }) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                Text("\(title) (\(count))")
                    .font(.system(size: 11, weight: isSelected ? .bold : .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(isSelected ? Color.blue : Color.clear)
            .foregroundColor(isSelected ? .white : .secondary)
            .cornerRadius(9)
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - 座標庫視圖 (支援置頂、標籤、點擊直接瞬移方案 A)
    private var locationsSection: some View {
        VStack(spacing: 6) {
            // 操作工具列
            HStack(spacing: 8) {
                // 儲存目前位置快捷鍵 (彈出命名視窗，留空自動使用國家/地區地名)
                Button(action: {
                    hideKeyboard()
                    saveLocationNameInput = ""
                    isSaveLocationAlertPresented = true
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
                    newLocTag = ""
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

            // 搜尋與排序列
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                    TextField("搜尋座標名稱或標籤", text: $locationSearchText)
                        .font(.system(size: 12))
                    if !locationSearchText.isEmpty {
                        Button(action: { locationSearchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                                .font(.system(size: 11))
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(8)

                Menu {
                    ForEach(DatabaseSortMode.allCases) { mode in
                        Button(mode.rawValue) {
                            locationSortMode = mode
                            UserDefaults.standard.set(mode.rawValue, forKey: "Drawer_LocationSortMode")
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 11))
                        Text(locationSortMode.rawValue)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(8)
                }
            }
            .padding(.horizontal, 16)

            // 座標清單 (依置頂與時間排序)
            ScrollView {
                LazyVStack(spacing: 6) {
                    if displayedLocations.isEmpty {
                        Text("無符合條件之座標。可在地圖長按或點上方按鈕新增。")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .padding(.vertical, 24)
                    } else {
                        ForEach(displayedLocations) { loc in
                            HStack(spacing: 6) {
                                // 置頂按鈕
                                Button(action: {
                                    hideKeyboard()
                                    db.togglePinLocation(id: loc.id)
                                }) {
                                    Image(systemName: loc.isPinned ? "pin.fill" : "pin")
                                        .font(.system(size: 13))
                                        .foregroundColor(loc.isPinned ? .orange : .secondary.opacity(0.5))
                                        .frame(width: 26, height: 26)
                                }

                                // 點擊直接瞬移 (方案 A：路線中斷時暫存離開點並暫停路線，按繼續時瞬移回原處接續)
                                Button(action: {
                                    hideKeyboard()
                                    db.useLocation(id: loc.id)
                                    session.teleport(to: loc.latitude, lng: loc.longitude, label: loc.name)
                                }) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "mappin.circle.fill")
                                            .font(.system(size: 20))
                                            .foregroundColor(.blue)

                                        VStack(alignment: .leading, spacing: 2) {
                                            HStack(spacing: 4) {
                                                Text(loc.name)
                                                    .font(.system(size: 14, weight: .bold))
                                                    .foregroundColor(.primary)

                                                if !loc.tag.isEmpty {
                                                    Text(loc.tag)
                                                        .font(.system(size: 10, weight: .bold))
                                                        .foregroundColor(.blue)
                                                        .padding(.horizontal, 5)
                                                        .padding(.vertical, 1)
                                                        .background(Color.blue.opacity(0.12))
                                                        .cornerRadius(4)
                                                }
                                            }

                                            Text("\(String(format: "%.6f", loc.latitude)), \(String(format: "%.6f", loc.longitude))")
                                                .font(.system(size: 11, design: .monospaced))
                                                .foregroundColor(.secondary)
                                        }

                                        Spacer()

                                        Text("瞬移")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundColor(.blue)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color.blue.opacity(0.1))
                                            .cornerRadius(6)
                                    }
                                }

                                // 重新命名
                                Button(action: {
                                    hideKeyboard()
                                    renameTargetId = loc.id
                                    renameTargetIsRoute = false
                                    renameInputText = loc.name
                                    isRenamePresented = true
                                }) {
                                    Image(systemName: "pencil")
                                        .font(.system(size: 13))
                                        .foregroundColor(.secondary)
                                        .frame(width: 24, height: 24)
                                }

                                // 編輯標籤
                                Button(action: {
                                    hideKeyboard()
                                    openEditTag(id: loc.id, isRoute: false, currentTitle: loc.name, currentTag: loc.tag)
                                }) {
                                    Image(systemName: "tag")
                                        .font(.system(size: 13))
                                        .foregroundColor(.secondary)
                                        .frame(width: 24, height: 24)
                                }

                                // 刪除按鈕
                                Button(action: {
                                    hideKeyboard()
                                    db.deleteLocation(id: loc.id)
                                }) {
                                    Image(systemName: "trash")
                                        .font(.system(size: 13))
                                        .foregroundColor(.red.opacity(0.7))
                                        .frame(width: 24, height: 24)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(loc.isPinned ? Color.orange.opacity(0.08) : Color(UIColor.secondarySystemBackground).opacity(0.6))
                            .cornerRadius(10)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            .frame(maxHeight: max(220, drawerHeight - 180))
        }
    }

    // MARK: - 路徑庫視圖 (支援置頂、標籤、點擊智慧詢問暫存進度)
    private var routesSection: some View {
        VStack(spacing: 6) {
            // 貼上座標匯入列 (檔案匯入集中於資料庫視窗)
            HStack(spacing: 8) {
                Button(action: {
                    hideKeyboard()
                    pasteRouteName = ""
                    pasteRouteTag = ""
                    pasteCoordinatesText = ""
                    isPasteImportPresented = true
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.clipboard.fill")
                        Text("貼上座標匯入")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
            }
            .padding(.horizontal, 16)

            // 路線搜尋與排序列
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                    TextField("搜尋路線名稱或標籤", text: $routeSearchText)
                        .font(.system(size: 12))
                    if !routeSearchText.isEmpty {
                        Button(action: { routeSearchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                                .font(.system(size: 11))
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(8)

                Menu {
                    ForEach(DatabaseSortMode.allCases) { mode in
                        Button(mode.rawValue) {
                            routeSortMode = mode
                            UserDefaults.standard.set(mode.rawValue, forKey: "Drawer_RouteSortMode")
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 11))
                        Text(routeSortMode.rawValue)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(8)
                }
            }
            .padding(.horizontal, 16)

            // 路徑清單 (依置頂與時間排序)
            ScrollView {
                LazyVStack(spacing: 6) {
                    if displayedRoutes.isEmpty {
                        Text("無符合條件之路線。點上方按鈕匯入 GPX 或貼上座標。")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .padding(.vertical, 24)
                    } else {
                        ForEach(displayedRoutes) { route in
                            HStack(spacing: 6) {
                                // 置頂按鈕
                                Button(action: {
                                    hideKeyboard()
                                    db.togglePinRoute(id: route.id)
                                }) {
                                    Image(systemName: route.isPinned ? "pin.fill" : "pin")
                                        .font(.system(size: 13))
                                        .foregroundColor(route.isPinned ? .orange : .secondary.opacity(0.5))
                                        .frame(width: 26, height: 26)
                                }

                                // 點擊路線：先判斷是否有暫存進度或正在執行中路線
                                Button(action: {
                                    hideKeyboard()
                                    handleRouteSelected(route)
                                }) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                                            .font(.system(size: 17))
                                            .foregroundColor(.purple)

                                        VStack(alignment: .leading, spacing: 2) {
                                            HStack(spacing: 4) {
                                                Text(route.name)
                                                    .font(.system(size: 14, weight: .bold))
                                                    .foregroundColor(.primary)

                                                if !route.tag.isEmpty {
                                                    Text(route.tag)
                                                        .font(.system(size: 10, weight: .bold))
                                                        .foregroundColor(.purple)
                                                        .padding(.horizontal, 5)
                                                        .padding(.vertical, 1)
                                                        .background(Color.purple.opacity(0.12))
                                                        .cornerRadius(4)
                                                }

                                                if RouteProgressStore.hasProgress(for: route.name) {
                                                    Text("有暫存")
                                                        .font(.system(size: 9, weight: .bold))
                                                        .foregroundColor(.orange)
                                                        .padding(.horizontal, 4)
                                                        .padding(.vertical, 1)
                                                        .background(Color.orange.opacity(0.15))
                                                        .cornerRadius(3)
                                                }
                                            }

                                            Text("共 \(route.nodes.count) 個航點")
                                                .font(.system(size: 11))
                                                .foregroundColor(.secondary)
                                        }

                                        Spacer()

                                        Text("設定 >")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundColor(.purple)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color.purple.opacity(0.1))
                                            .cornerRadius(6)
                                    }
                                }

                                // 編輯路線點位
                                Button(action: {
                                    hideKeyboard()
                                    self.routeToEdit = route
                                }) {
                                    Image(systemName: "list.bullet.indent")
                                        .font(.system(size: 13))
                                        .foregroundColor(.blue)
                                        .frame(width: 24, height: 24)
                                }

                                // 重新命名
                                Button(action: {
                                    hideKeyboard()
                                    renameTargetId = route.id
                                    renameTargetIsRoute = true
                                    renameInputText = route.name
                                    isRenamePresented = true
                                }) {
                                    Image(systemName: "pencil")
                                        .font(.system(size: 13))
                                        .foregroundColor(.secondary)
                                        .frame(width: 24, height: 24)
                                }

                                // 編輯標籤
                                Button(action: {
                                    hideKeyboard()
                                    openEditTag(id: route.id, isRoute: true, currentTitle: route.name, currentTag: route.tag)
                                }) {
                                    Image(systemName: "tag")
                                        .font(.system(size: 13))
                                        .foregroundColor(.secondary)
                                        .frame(width: 24, height: 24)
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
                                        .frame(width: 24, height: 24)
                                }

                                // 刪除按鈕
                                Button(action: {
                                    hideKeyboard()
                                    db.deleteRoute(id: route.id)
                                }) {
                                    Image(systemName: "trash")
                                        .font(.system(size: 13))
                                        .foregroundColor(.red.opacity(0.7))
                                        .frame(width: 24, height: 24)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(route.isPinned ? Color.purple.opacity(0.08) : Color(UIColor.secondarySystemBackground).opacity(0.6))
                            .cornerRadius(10)
                            .contextMenu {
                                Button(action: {
                                    hideKeyboard()
                                    if let url = db.exportRouteToGPX(route: route) {
                                        exportBackupURL = url
                                        isExportSharePresented = true
                                    } else {
                                        session.showToast("匯出 GPX 失敗", isError: true)
                                    }
                                }) {
                                    Label("匯出此路線 (GPX)", systemImage: "square.and.arrow.up")
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            .frame(maxHeight: max(220, drawerHeight - 180))
        }
    }

    // MARK: - 全功能歷史紀錄視圖 (支援單點瞬移、直線、種花、跳果實、同心圓，點擊直接執行)
    private var locationHistorySection: some View {
        VStack(spacing: 6) {
            // 工具列：清空按鈕與筆數統計
            HStack {
                Text("共 \(db.locationHistory.count) 筆歷史紀錄")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                Spacer()

                if !db.locationHistory.isEmpty {
                    Button(action: {
                        hideKeyboard()
                        db.clearHistory()
                        session.toastMessage = "已清空歷史紀錄"
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                            Text("清空紀錄")
                        }
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.red)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(6)
                    }
                }
            }
            .padding(.horizontal, 16)

            // 紀錄清單
            ScrollView {
                LazyVStack(spacing: 6) {
                    if db.locationHistory.isEmpty {
                        Text("目前尚無定位或路線紀錄。執行單點瞬移或各類巡航路線時，系統將自動記錄於此。")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .padding(.vertical, 24)
                    } else {
                        ForEach(db.locationHistory) { item in
                            Button(action: {
                                hideKeyboard()
                                session.executeHistoryItem(item)
                            }) {
                                HStack(spacing: 8) {
                                    Image(systemName: iconForHistoryItem(item))
                                        .font(.system(size: 16))
                                        .foregroundColor(colorForHistoryItem(item))
                                        .frame(width: 22)

                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            Text(item.type.rawValue)
                                                .font(.system(size: 9, weight: .bold))
                                                .foregroundColor(.white)
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 1)
                                                .background(colorForHistoryItem(item))
                                                .cornerRadius(4)

                                            Text(item.title)
                                                .font(.system(size: 13, weight: .bold))
                                                .foregroundColor(.primary)
                                                .lineLimit(1)

                                            Spacer()

                                            Text(item.formattedTime)
                                                .font(.system(size: 10))
                                                .foregroundColor(.secondary)
                                        }

                                        HStack(spacing: 6) {
                                            Text("\(String(format: "%.6f", item.latitude)), \(String(format: "%.6f", item.longitude))")
                                                .font(.system(size: 11, design: .monospaced))
                                                .foregroundColor(.secondary)

                                            if let nodes = item.routeNodes, !nodes.isEmpty {
                                                Text("・\(nodes.count) 點")
                                                    .font(.system(size: 10))
                                                    .foregroundColor(.secondary)
                                            }
                                            if item.loops > 0 {
                                                Text("・\(item.loops) 圈")
                                                    .font(.system(size: 10))
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                    }

                                    Spacer()

                                    Text(item.type == .teleport ? "瞬移" : "執行")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(colorForHistoryItem(item))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(colorForHistoryItem(item).opacity(0.12))
                                        .cornerRadius(6)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Color(UIColor.secondarySystemBackground).opacity(0.6))
                                .cornerRadius(10)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            .frame(maxHeight: max(220, drawerHeight - 180))
        }
    }

    private func iconForHistoryItem(_ item: LocationHistoryItem) -> String {
        switch item.type {
        case .teleport: return "location.fill"
        case .linearRoute: return "point.topleft.down.curvedto.point.bottomright.up"
        case .flowerRoute: return "camera.macro"
        case .fruitRoute: return "figure.walk"
        case .concentricRoute: return "circle.circle"
        }
    }

    private func colorForHistoryItem(_ item: LocationHistoryItem) -> Color {
        switch item.type {
        case .teleport: return .blue
        case .linearRoute: return .purple
        case .flowerRoute: return .orange
        case .fruitRoute: return .green
        case .concentricRoute: return .indigo
        }
    }

    // MARK: - 路線點擊處理邏輯 (切換路線確認 + 暫存進度詢問)
    private func handleRouteSelected(_ route: SavedRoute) {
        db.useRoute(name: route.name)
        // 直接開啟路線配置視窗，由使用者選擇模式並開跑 (開跑時自動替換舊路線)
        checkAndProceedWithRoute(route)
    }

    private func checkAndProceedWithRoute(_ route: SavedRoute) {
        if RouteProgressStore.hasProgress(for: route.name) {
            self.routeForResumeChoice = route
            self.isResumeRouteChoicePresented = true
        } else {
            self.selectedRouteForConfig = route
        }
    }

    // 正在運行中路線切換詢問
    private var routeSwitchConfirmationAlert: Alert {
        Alert(
            title: Text("正在運行路線【\(session.activeRouteName)】"),
            message: Text("是否要切換至新路線？請選擇是否暫存目前進度："),
            primaryButton: .default(Text("存檔進度並切換")) {
                session.saveProgress()
                if let target = pendingTargetRoute {
                    pendingTargetRoute = nil
                    checkAndProceedWithRoute(target)
                }
            },
            secondaryButton: .destructive(Text("直接切換 (不存檔)")) {
                session.stopRoute()
                if let target = pendingTargetRoute {
                    pendingTargetRoute = nil
                    checkAndProceedWithRoute(target)
                }
            }
        )
    }

    // 發現暫存進度 ActionSheet (接續上次進度 vs 從頭全新開始)
    private var resumeRouteActionSheet: ActionSheet {
        let name = routeForResumeChoice?.name ?? "此路線"
        return ActionSheet(
            title: Text("發現路線【\(name)】暫存進度"),
            message: Text("此路線有先前中斷之進度，請選擇執行方式："),
            buttons: [
                .default(Text("接續上次進度")) {
                    if let r = routeForResumeChoice, let progress = RouteProgressStore.getProgress(for: r.name) {
                        session.resumeProgress(progress)
                    }
                    routeForResumeChoice = nil
                },
                .destructive(Text("從頭全新開始 (重置進度)")) {
                    if let r = routeForResumeChoice {
                        RouteProgressStore.clearProgress(for: r.name)
                        selectedRouteForConfig = r
                    }
                    routeForResumeChoice = nil
                },
                .cancel(Text("取消")) {
                    routeForResumeChoice = nil
                }
            ]
        )
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

    // MARK: - 檔案匯入處理 (支援單檔多路線自動拆分與多檔案批次匯入)
    private func handleFileImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard !urls.isEmpty else { return }
            if urls.count == 1 {
                let (success, name, count, error) = db.importRouteFromFile(url: urls[0])
                if success {
                    session.toastMessage = "成功匯入路線【\(name)】共 \(count) 個航點！"
                } else {
                    session.toastMessage = error ?? "匯入失敗"
                }
            } else {
                let (successCount, failedCount, names) = db.importRoutesFromFiles(urls: urls)
                if successCount > 0 {
                    let sample = names.prefix(3).joined(separator: ", ")
                    session.toastMessage = "成功批次匯入 \(successCount) 條路線！[\(sample)\(names.count > 3 ? "..." : "")]"
                } else {
                    session.toastMessage = "匯入失敗，選取檔案中未包含有效座標"
                }
            }
        case .failure(let err):
            session.toastMessage = "選取檔案失敗: \(err.localizedDescription)"
        }
    }

    // MARK: - 標籤編輯
    private func openEditTag(id: UUID, isRoute: Bool, currentTitle: String, currentTag: String) {
        self.editingItemId = id
        self.editingItemIsRoute = isRoute
        self.editingItemTitle = currentTitle
        self.editingTagText = currentTag
        self.isEditTagPresented = true
    }

    private var editTagSheet: some View {
        NavigationView {
            Form {
                Section(header: Text("編輯標籤分類")) {
                    Text(editingItemTitle)
                        .font(.headline)
                    TextField("輸入標籤分類名稱 (例：花苞區、日常補給)", text: $editingTagText)
                }

                Section {
                    Button("儲存標籤") {
                        if let id = editingItemId {
                            if editingItemIsRoute {
                                db.updateRouteTag(id: id, tag: editingTagText)
                            } else {
                                db.updateLocationTag(id: id, tag: editingTagText)
                            }
                        }
                        isEditTagPresented = false
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundColor(.blue)

                    if !editingTagText.isEmpty {
                        Button("清除標籤") {
                            if let id = editingItemId {
                                if editingItemIsRoute {
                                    db.updateRouteTag(id: id, tag: "")
                                } else {
                                    db.updateLocationTag(id: id, tag: "")
                                }
                            }
                            isEditTagPresented = false
                        }
                        .frame(maxWidth: .infinity)
                        .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("標籤設定")
            .navigationBarItems(leading: Button("取消") { isEditTagPresented = false })
        }
    }

    // MARK: - 貼上座標匯入 Sheet
    private var pasteImportSheet: some View {
        NavigationView {
            Form {
                Section(header: Text("路線基本資訊")) {
                    TextField("輸入路線名稱 (例如：大安花區巡航)", text: $pasteRouteName)
                    TextField("標籤分類 (選填，例如：大安區、刷花)", text: $pasteRouteTag)
                }

                Section(header: Text("貼上座標列表 (支援多行，格式：lat,lng)"), footer: Text("範例：\n25.033964, 121.564468\n25.034500, 121.565200\n支援以逗號、空格或分號分隔之經緯度座標。")) {
                    TextEditor(text: $pasteCoordinatesText)
                        .frame(minHeight: 180)
                        .font(.system(size: 12, design: .monospaced))
                }

                Section {
                    Button(action: {
                        let (success, count) = db.importRouteFromPastedText(name: pasteRouteName, text: pasteCoordinatesText, tag: pasteRouteTag)
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
                Section(header: Text("座標名稱與標籤")) {
                    TextField("名稱 (例如：信義威秀大花苞)", text: $newLocName)
                    TextField("標籤分類 (選填，例如：花苞、補給站)", text: $newLocTag)
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
                            db.addLocation(name: newLocName, latitude: lat, longitude: lng, tag: newLocTag)
                            isAddLocationPresented = false
                            session.toastMessage = "座標已儲存"
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

// MARK: - UIActivityViewController 封裝 (供資料庫全備份 JSON 匯出分享)
public struct ActivityViewController: UIViewControllerRepresentable {
    var activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil

    public func makeUIViewController(context: UIViewControllerRepresentableContext<ActivityViewController>) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
    }

    public func updateUIViewController(_ uiViewController: UIActivityViewController, context: UIViewControllerRepresentableContext<ActivityViewController>) {}
}
