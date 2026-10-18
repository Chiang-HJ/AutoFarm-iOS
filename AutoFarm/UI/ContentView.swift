import SwiftUI
import CoreLocation
import UIKit

public struct ContentView: View {
    @StateObject private var session = AutoFarmSession.shared
    @ObservedObject private var db = SavedDatabaseStore.shared

    @State private var searchInput: String = ""
    @State private var isSharePresented: Bool = false
    @State private var isSettingsPresented: Bool = false
    @State private var isDatabasePresented: Bool = false
    @State private var pendingResumeProgress: RouteProgress? = nil

    // 單點模式選定座標 (長按地圖 或 點擊目前位置觸發)
    @State private var selectedSingleCoord: CLLocationCoordinate2D? = nil
    @State private var isSavingCoordNamePrompt: Bool = false
    @State private var saveCoordNameInput: String = ""

    // 自由拖曳虛擬搖桿開關位置
    @State private var joystickPositionOffset: CGSize = .zero
    @GestureState private var joystickDragOffset: CGSize = .zero

    public init() {}

    public var body: some View {
        ZStack {
            // 1. 全螢幕互動地圖
            MainMapView(
                onLongPress: { coord in
                    self.saveCoordNameInput = ""
                    self.isSavingCoordNamePrompt = false
                    self.selectedSingleCoord = coord
                },
                onTapCurrentLocation: {
                    self.saveCoordNameInput = ""
                    self.isSavingCoordNamePrompt = false
                    self.selectedSingleCoord = CLLocationCoordinate2D(latitude: session.currentLat, longitude: session.currentLng)
                }
            )
            .edgesIgnoringSafeArea(.all)

            // 2. 主介面浮層
            VStack(spacing: 0) {
                // 頂部多功能精簡工具列 (待命狀態乾淨俐落)
                topActionBar
                    .padding(.horizontal, 12)
                    .padding(.top, 44) // 避開 Dynamic Island / 狀態列

                // 狀態懸浮 HUD 膠囊
                StatusHUDView()
                    .padding(.top, 6)

                Spacer()

                // 地圖右側獨立懸浮功能按鈕群
                HStack {
                    Spacer()
                    VStack(spacing: 12) {
                        // 視角平滑置中至目前定位 (相機順移回角色當前位置)
                        Button(action: {
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
                            self.saveCoordNameInput = ""
                            self.isSavingCoordNamePrompt = false
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
                    }
                    .padding(.trailing, 16)
                    .padding(.bottom, 10)
                }

                // 底部控制抽屜 (平時待命速度設定 + 資料庫；運行時平移安卓懸浮球)
                ControlDrawerView(
                    onOpenShare: { isSharePresented = true },
                    onOpenSettings: { isSettingsPresented = true }
                )
            }
            .edgesIgnoringSafeArea(.bottom)

            // 3. 可全螢幕任意自由拖曳位置的虛擬搖桿開關與方向盤
            draggableJoystickView

            // 4. 單點多功能互動卡片 (長按或點選目前位置)
            if let coord = selectedSingleCoord {
                singlePointActionOverlay(coord: coord)
            }

            // 5. 啟動時偵測到未完成進度之提示視窗
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

    // MARK: - 可自由拖曳位置的虛擬搖桿組件
    private var draggableJoystickView: some View {
        VStack(alignment: .leading, spacing: 8) {
            if session.isJoystickEnabled {
                VirtualJoystickView()
                    .transition(.scale.combined(with: .opacity))
            }

            // 獨立搖桿開關按鈕 (支援全螢幕拖曳)
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                    session.isJoystickEnabled.toggle()
                }
            }) {
                HStack(spacing: 5) {
                    Image(systemName: session.isJoystickEnabled ? "gamecontroller.fill" : "gamecontroller")
                        .font(.system(size: 18))
                    if !session.isJoystickEnabled {
                        Text("搖桿")
                            .font(.system(size: 11, weight: .bold))
                    }
                }
                .foregroundColor(session.isJoystickEnabled ? .white : .blue)
                .frame(minWidth: 44, minHeight: 44)
                .padding(.horizontal, session.isJoystickEnabled ? 0 : 8)
                .background(session.isJoystickEnabled ? Color.blue : Color(UIColor.secondarySystemBackground).opacity(0.92))
                .clipShape(Capsule())
                .shadow(color: Color.black.opacity(0.2), radius: 5, x: 0, y: 2)
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
        }
        .offset(
            x: joystickPositionOffset.width + joystickDragOffset.width,
            y: joystickPositionOffset.height + joystickDragOffset.height
        )
        .position(x: 70, y: 550)
    }

    // MARK: - 頂部工具列 (平時待命狀態專用，保持乾淨)
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

            // DVT 連線就緒指示燈
            Circle()
                .fill(session.isSimulatingLocation ? Color.blue : Color.green)
                .frame(width: 10, height: 10)

            // 座標與路徑資料庫
            Button(action: { isDatabasePresented = true }) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.blue)
                    .frame(width: 34, height: 34)
                    .background(Color(UIColor.secondarySystemBackground).opacity(0.92))
                    .cornerRadius(8)
            }

            // 連線與憑證設定
            Button(action: { isSettingsPresented = true }) {
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

    private func handleCoordinateSearch() {
        let cleaned = searchInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.contains(",") {
            let parts = cleaned.split(separator: ",")
            if parts.count == 2,
               let lat = Double(parts[0].trimmingCharacters(in: .whitespaces)),
               let lng = Double(parts[1].trimmingCharacters(in: .whitespaces)) {
                session.teleport(to: lat, lng: lng)
                searchInput = ""
            }
        }
    }

    private func checkUncompletedProgress() {
        if let latest = RouteProgressStore.listAllSavedProgress().first {
            self.pendingResumeProgress = latest
        }
    }
}
