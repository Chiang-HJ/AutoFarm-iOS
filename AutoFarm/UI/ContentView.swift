import SwiftUI
import CoreLocation
import UIKit

public struct ContentView: View {
    @StateObject private var session = AutoFarmSession.shared
    @ObservedObject private var db = SavedDatabaseStore.shared
    @ObservedObject private var clipboard = ClipboardDetector.shared

    @State private var searchInput: String = ""
    @State private var isSharePresented: Bool = false
    @State private var isSettingsPresented: Bool = false
    @State private var isDatabasePresented: Bool = false
    @State private var pendingResumeProgress: RouteProgress? = nil

    // 單點模式選定座標 (長按地圖 或 點擊目前位置觸發)
    @State private var selectedSingleCoord: CLLocationCoordinate2D? = nil
    @State private var isSavingCoordNamePrompt: Bool = false
    @State private var saveCoordNameInput: String = ""

    // 點選地圖數字球選定之航點索引 (對齊安卓：從此點出發 / 瞬移 / 刪除 / 複製)
    @State private var selectedWaypointIndex: Int? = nil

    // 自由拖曳虛擬搖桿開關位置
    @State private var joystickPositionOffset: CGSize = .zero
    @GestureState private var joystickDragOffset: CGSize = .zero

    public init() {}

    public var body: some View {
        if !session.isLoggedIn {
            LoginView()
        } else {
            mainContentView
        }
    }

    // MARK: - 已登入之主畫面視圖
    private var mainContentView: some View {
        ZStack {
            // 1. 全螢幕互動地圖
            MainMapView(
                onLongPress: { coord in
                    hideKeyboard()
                    self.saveCoordNameInput = ""
                    self.isSavingCoordNamePrompt = false
                    self.selectedWaypointIndex = nil
                    self.selectedSingleCoord = coord
                },
                onSelectWaypoint: { index in
                    hideKeyboard()
                    self.selectedSingleCoord = nil
                    self.selectedWaypointIndex = index
                },
                onTapCurrentLocation: {
                    hideKeyboard()
                    self.saveCoordNameInput = ""
                    self.isSavingCoordNamePrompt = false
                    self.selectedWaypointIndex = nil
                    self.selectedSingleCoord = CLLocationCoordinate2D(latitude: session.currentLat, longitude: session.currentLng)
                }
            )
            .edgesIgnoringSafeArea(.all)
            .onTapGesture {
                hideKeyboard()
            }

            // 2. 主介面浮層
            VStack(spacing: 0) {
                // 頂部多功能工具列
                topActionBar
                    .padding(.horizontal, 12)
                    .padding(.top, 44) // 避開 Dynamic Island / 狀態列

                // 剪貼簿座標即時感測懸浮橫幅
                if let item = clipboard.activeItem {
                    clipboardBanner(item: item)
                        .padding(.horizontal, 12)
                        .padding(.top, 6)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(100)
                }

                // 狀態懸浮 HUD 膠囊
                StatusHUDView()
                    .padding(.top, 6)

                Spacer()

                // 地圖右側獨立懸浮功能按鈕群
                HStack {
                    Spacer()
                    VStack(spacing: 12) {
                        // 視角置中目前定位
                        Button(action: {
                            hideKeyboard()
                            session.centerCameraOnCurrentLocation()
                        }) {
                            Image(systemName: "location.fill")
                                .font(.system(size: 18))
                                .foregroundColor(.blue)
                                .frame(width: 44, height: 44)
                                .background(Color(UIColor.secondarySystemBackground).opacity(0.92))
                                .clipShape(Circle())
                                .shadow(color: Color.black.opacity(0.18), radius: 5, x: 0, y: 2)
                        }

                        // 目前位置單點選單
                        Button(action: {
                            hideKeyboard()
                            self.saveCoordNameInput = ""
                            self.isSavingCoordNamePrompt = false
                            self.selectedWaypointIndex = nil
                            self.selectedSingleCoord = CLLocationCoordinate2D(latitude: session.currentLat, longitude: session.currentLng)
                        }) {
                            Image(systemName: "mappin.and.ellipse")
                                .font(.system(size: 18))
                                .foregroundColor(.purple)
                                .frame(width: 44, height: 44)
                                .background(Color(UIColor.secondarySystemBackground).opacity(0.92))
                                .clipShape(Circle())
                                .shadow(color: Color.black.opacity(0.18), radius: 5, x: 0, y: 2)
                        }

                        // 一鍵停止虛擬定位回到真實 GPS
                        Button(action: {
                            hideKeyboard()
                            session.stopMocking()
                        }) {
                            Image(systemName: "location.slash.fill")
                                .font(.system(size: 18))
                                .foregroundColor(.red)
                                .frame(width: 44, height: 44)
                                .background(Color(UIColor.secondarySystemBackground).opacity(0.92))
                                .clipShape(Circle())
                                .shadow(color: Color.black.opacity(0.18), radius: 5, x: 0, y: 2)
                        }
                    }
                    .padding(.trailing, 16)
                    .padding(.bottom, 10)
                }

                // 底部控制抽屜
                ControlDrawerView(
                    onOpenShare: { isSharePresented = true },
                    onOpenSettings: { isSettingsPresented = true }
                )
            }
            .edgesIgnoringSafeArea(.bottom)

            // 3. 可自由拖曳的懸浮方向盤與開關
            draggableJoystickView

            // 4. 點選地圖數字球操作浮動卡片 (對齊安卓：從此點開始運行、瞬移、刪除此航點、複製)
            if let wpIdx = selectedWaypointIndex {
                waypointActionOverlay(index: wpIdx)
            }

            // 5. 單點多功能互動卡片 (長按或點選目前位置)
            if let coord = selectedSingleCoord {
                singlePointActionOverlay(coord: coord)
            }

            // 6. 啟動時偵測到未完成進度之提示視窗 (自動讀取意外中斷前最新保存之路線)
            if let resume = pendingResumeProgress {
                Color.black.opacity(0.4).edgesIgnoringSafeArea(.all)
                ResumeProgressSheet(
                    progress: resume,
                    onResume: {
                        session.resumeProgress(resume)
                        pendingResumeProgress = nil
                    },
                    onRestart: {
                        RouteProgressStore.clearProgress(for: resume.routeName)
                        pendingResumeProgress = nil
                    },
                    onDismiss: {
                        pendingResumeProgress = nil
                    }
                )
            }
        }
        .onAppear {
            checkUncompletedProgress()
            clipboard.checkClipboardOnForeground()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            clipboard.checkClipboardOnForeground()
        }
        .sheet(isPresented: $isDatabasePresented) {
            DatabaseSheet()
        }
        .sheet(isPresented: $isSharePresented) {
            RouteShareView()
        }
        .sheet(isPresented: $isSettingsPresented) {
            SettingsSheet()
        }
    }

    // MARK: - 點選地圖數字球操作卡片 (完全對齊安卓功能)
    @ViewBuilder
    private func waypointActionOverlay(index: Int) -> some View {
        let waypoints = session.displayWaypoints
        if index >= 0 && index < waypoints.count {
            let node = waypoints[index]
            let isFlower = (session.executionMode == 1)
            let pointTitle = isFlower ? "花苞 #\(index + 1)" : "航點 #\(index + 1)"

            Color.black.opacity(0.35)
                .edgesIgnoringSafeArea(.all)
                .onTapGesture {
                    selectedWaypointIndex = nil
                }

            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(pointTitle)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.primary)
                        Text("\(String(format: "%.6f", node.lat)), \(String(format: "%.6f", node.lng))")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button(action: { selectedWaypointIndex = nil }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                            .font(.system(size: 20))
                    }
                }

                Divider()

                VStack(spacing: 8) {
                    // 1. 從此點開始運行 (繼續自動巡航，不暫停)
                    Button(action: {
                        session.jumpToWaypoint(index: index)
                        selectedWaypointIndex = nil
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 16))
                            Text("從此點開始運行 (繼續巡航)")
                                .font(.system(size: 13, weight: .bold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }

                    HStack(spacing: 8) {
                        // 2. 瞬移到此點 (暫停路線)
                        Button(action: {
                            session.teleport(to: node.lat, lng: node.lng)
                            selectedWaypointIndex = nil
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "location.fill")
                                Text("瞬移到此點 (暫停)")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }

                        // 3. 複製座標
                        Button(action: {
                            UIPasteboard.general.string = "\(String(format: "%.6f", node.lat)), \(String(format: "%.6f", node.lng))"
                            session.toastMessage = "已複製航點座標"
                            selectedWaypointIndex = nil
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "doc.on.doc.fill")
                                Text("複製座標")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(Color(UIColor.secondarySystemBackground))
                            .foregroundColor(.primary)
                            .cornerRadius(10)
                        }
                    }

                    // 4. 刪除此航點 (對齊安卓：直接從當前路線中剔除此點)
                    Button(action: {
                        session.removeWaypoint(at: index)
                        selectedWaypointIndex = nil
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "trash.fill")
                            Text("刪除此航點")
                                .font(.system(size: 12, weight: .bold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(Color.red.opacity(0.15))
                        .foregroundColor(.red)
                        .cornerRadius(10)
                    }
                }
            }
            .padding(16)
            .background(Color(UIColor.systemBackground))
            .cornerRadius(16)
            .shadow(radius: 12)
            .padding(.horizontal, 24)
        }
    }

    // MARK: - 可自由拖曳位置的懸浮搖桿組件
    private var draggableJoystickView: some View {
        VStack {
            if session.isJoystickEnabled {
                VirtualJoystickView()
                    .transition(.scale.combined(with: .opacity))
            } else {
                // 獨立搖桿開關按鈕 (支援全螢幕任意拖動)
                Button(action: {
                    hideKeyboard()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        session.isJoystickEnabled = true
                    }
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "gamecontroller.fill")
                            .font(.system(size: 18))
                        Text("搖桿")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .frame(height: 40)
                    .padding(.horizontal, 12)
                    .background(Color.blue)
                    .clipShape(Capsule())
                    .shadow(color: Color.black.opacity(0.25), radius: 5, x: 0, y: 2)
                }
            }
        }
        .gesture(
            DragGesture()
                .updating($joystickDragOffset) { value, state, _ in
                    state = value.translation
                }
                .onEnded { value in
                    joystickPositionOffset.width += value.translation.width
                    joystickPositionOffset.height += value.translation.height
                }
        )
        .offset(
            x: joystickPositionOffset.width + joystickDragOffset.width,
            y: joystickPositionOffset.height + joystickDragOffset.height
        )
        .position(x: 80, y: 520)
    }

    // MARK: - 頂部工具列
    private var topActionBar: some View {
        HStack(spacing: 8) {
            // 座標與搜尋輸入
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 13))
                TextField("搜尋或輸入 lat,lng 座標", text: $searchInput, onCommit: handleCoordinateSearch)
                    .font(.system(size: 12))
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                if !searchInput.isEmpty {
                    Button(action: { searchInput = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 12))
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color(UIColor.secondarySystemBackground).opacity(0.92))
            .cornerRadius(12)

            // DVT 連線指示燈
            Circle()
                .fill(session.isSimulatingLocation ? Color.blue : Color.green)
                .frame(width: 10, height: 10)

            // 座標與路徑資料庫
            Button(action: {
                hideKeyboard()
                isDatabasePresented = true
            }) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.blue)
                    .frame(width: 34, height: 34)
                    .background(Color(UIColor.secondarySystemBackground).opacity(0.92))
                    .cornerRadius(8)
            }

            // 連線與憑證設定
            Button(action: {
                hideKeyboard()
                isSettingsPresented = true
            }) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.primary)
                    .frame(width: 34, height: 34)
                    .background(Color(UIColor.secondarySystemBackground).opacity(0.92))
                    .cornerRadius(8)
            }
        }
    }

    // MARK: - 單點模式浮動操作面板
    @ViewBuilder
    private func singlePointActionOverlay(coord: CLLocationCoordinate2D) -> some View {
        Color.black.opacity(0.35)
            .edgesIgnoringSafeArea(.all)
            .onTapGesture {
                selectedSingleCoord = nil
                isSavingCoordNamePrompt = false
            }

        VStack(spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("選定單點座標")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                    Text("\(String(format: "%.6f", coord.latitude)), \(String(format: "%.6f", coord.longitude))")
                        .font(.system(size: 14, weight: .bold))
                }
                Spacer()
                Button(action: {
                    selectedSingleCoord = nil
                    isSavingCoordNamePrompt = false
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                        .font(.system(size: 20))
                }
            }

            if isSavingCoordNamePrompt {
                // 儲存座標輸入框
                VStack(spacing: 10) {
                    TextField("輸入座標名稱 (例：信義大花苞)", text: $saveCoordNameInput)
                        .textFieldStyle(.roundedBorder)

                    HStack(spacing: 8) {
                        Button(action: {
                            db.addLocation(name: saveCoordNameInput, latitude: coord.latitude, longitude: coord.longitude)
                            selectedSingleCoord = nil
                            isSavingCoordNamePrompt = false
                        }) {
                            Text("僅儲存不定位")
                                .font(.system(size: 12, weight: .bold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.gray.opacity(0.2))
                                .foregroundColor(.primary)
                                .cornerRadius(8)
                        }

                        Button(action: {
                            db.addLocation(name: saveCoordNameInput, latitude: coord.latitude, longitude: coord.longitude)
                            session.teleport(to: coord.latitude, lng: coord.longitude)
                            selectedSingleCoord = nil
                            isSavingCoordNamePrompt = false
                        }) {
                            Text("儲存並同時瞬移")
                                .font(.system(size: 12, weight: .bold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                    }
                }
                .padding(.vertical, 4)
            } else {
                // 四大核心單點操作
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        // 1. 複製座標
                        Button(action: {
                            UIPasteboard.general.string = "\(String(format: "%.6f", coord.latitude)), \(String(format: "%.6f", coord.longitude))"
                            selectedSingleCoord = nil
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "doc.on.doc.fill")
                                Text("複製座標")
                                    .font(.system(size: 13, weight: .bold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color(UIColor.secondarySystemBackground))
                            .foregroundColor(.primary)
                            .cornerRadius(10)
                        }

                        // 2. 儲存座標
                        Button(action: {
                            isSavingCoordNamePrompt = true
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "bookmark.fill")
                                Text("儲存座標")
                                    .font(.system(size: 13, weight: .bold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color(UIColor.secondarySystemBackground))
                            .foregroundColor(.primary)
                            .cornerRadius(10)
                        }
                    }

                    HStack(spacing: 8) {
                        // 3. 同心圓種花
                        Button(action: {
                            session.startConcentricFlower(
                                centerLat: coord.latitude,
                                centerLng: coord.longitude,
                                radius: 30.0,
                                step: 10.0,
                                mode: .multiRing
                            )
                            selectedSingleCoord = nil
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "circle.circle.fill")
                                Text("同心圓種花")
                                    .font(.system(size: 13, weight: .bold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.purple)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }

                        // 4. 瞬移到此
                        Button(action: {
                            session.teleport(to: coord.latitude, lng: coord.longitude)
                            selectedSingleCoord = nil
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "location.fill")
                                Text("瞬移到此")
                                    .font(.system(size: 13, weight: .bold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                    }
                }
            }
        }
        .padding(18)
        .background(Color(UIColor.systemBackground))
        .cornerRadius(16)
        .shadow(radius: 12)
        .padding(.horizontal, 24)
    }

    // MARK: - 剪貼簿座標偵測懸浮橫幅
    private func clipboardBanner(item: DetectedClipboardItem) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.on.clipboard.fill")
                .foregroundColor(.blue)
                .font(.system(size: 16))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text("偵測到剪貼簿座標")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.primary)
                    if let label = item.label, !label.isEmpty {
                        Text(label)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.blue)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.blue.opacity(0.12))
                            .cornerRadius(4)
                    }
                }
                Text("\(String(format: "%.5f", item.lat)), \(String(format: "%.5f", item.lng))")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            Spacer()

            // 瞬移
            Button(action: {
                withAnimation {
                    clipboard.markHandled()
                    session.teleport(to: item.lat, lng: item.lng, label: item.label ?? "剪貼簿座標")
                    session.centerCameraOnCurrentLocation()
                }
            }) {
                Text("瞬移")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.blue)
                    .cornerRadius(6)
            }

            // 存入座標庫
            Button(action: {
                withAnimation {
                    clipboard.markHandled()
                    db.addLocation(name: item.label ?? "剪貼簿座標", latitude: item.lat, longitude: item.lng)
                    session.toastMessage = "已將座標存入常用座標庫！"
                }
            }) {
                Text("儲存")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(6)
            }

            // 忽略
            Button(action: {
                withAnimation {
                    clipboard.dismiss()
                }
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)
                    .padding(5)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(UIColor.systemBackground).opacity(0.96))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.15), radius: 6, x: 0, y: 3)
    }

    private func handleCoordinateSearch() {
        hideKeyboard()
        let raw = searchInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }

        if let coords = AutoFarmSession.extractCoordinates(from: raw) {
            session.teleport(to: coords.lat, lng: coords.lng, label: "搜尋瞬移")
            session.centerCameraOnCurrentLocation()
            searchInput = ""
        } else {
            session.toastMessage = "未能從輸入內容中辨識出有效座標"
        }
    }

    private func checkUncompletedProgress() {
        if let latest = RouteProgressStore.listAllSavedProgress().first {
            self.pendingResumeProgress = latest
        }
    }
}
