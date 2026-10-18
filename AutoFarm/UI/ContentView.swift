import SwiftUI
import CoreLocation
import UIKit

public struct ContentView: View {
    @StateObject private var session = AutoFarmSession.shared

    @State private var searchInput: String = ""
    @State private var isSharePresented: Bool = false
    @State private var isSettingsPresented: Bool = false
    @State private var pendingResumeProgress: RouteProgress? = nil
    @State private var longPressedCoord: CLLocationCoordinate2D? = nil

    public init() {}

    public var body: some View {
        ZStack {
            // 1. 全螢幕互動地圖
            MainMapView(
                onLongPress: { coord in
                    self.longPressedCoord = coord
                }
            )
            .edgesIgnoringSafeArea(.all)

            // 2. 介面階梯浮層
            VStack(spacing: 0) {
                // 頂部多功能工具列
                topActionBar
                    .padding(.horizontal, 12)
                    .padding(.top, 44) // 避開 Dynamic Island / 狀態列

                // 狀態懸浮 HUD 膠囊
                StatusHUDView()
                    .padding(.top, 8)

                Spacer()

                // 下層操作區：左側虛擬搖桿 + 底部功能控制抽屜
                HStack(alignment: .bottom, spacing: 12) {
                    VirtualJoystickView()
                        .padding(.leading, 16)
                        .padding(.bottom, 20)

                    Spacer()
                }

                ControlDrawerView(
                    onOpenShare: { isSharePresented = true },
                    onOpenSettings: { isSettingsPresented = true }
                )
            }
            .edgesIgnoringSafeArea(.bottom)

            // 長按選點彈出選單
            if let coord = longPressedCoord {
                Color.black.opacity(0.3)
                    .edgesIgnoringSafeArea(.all)
                    .onTapGesture { longPressedCoord = nil }

                VStack(spacing: 12) {
                    Text("選定座標：\(String(format: "%.5f", coord.latitude)), \(String(format: "%.5f", coord.longitude))")
                        .font(.system(size: 13, weight: .bold))

                    HStack(spacing: 10) {
                        Button(action: {
                            session.teleport(to: coord.latitude, lng: coord.longitude)
                            longPressedCoord = nil
                        }) {
                            Text("瞬移到此")
                                .font(.system(size: 13, weight: .bold))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }

                        Button(action: {
                            session.startConcentricFlower(
                                centerLat: coord.latitude,
                                centerLng: coord.longitude,
                                radius: 30.0,
                                step: 10.0,
                                mode: .multiRing
                            )
                            longPressedCoord = nil
                        }) {
                            Text("同心圓種花")
                                .font(.system(size: 13, weight: .bold))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Color.purple)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                    }
                }
                .padding(16)
                .background(Color(UIColor.systemBackground))
                .cornerRadius(14)
                .shadow(radius: 10)
            }

            // 啟動時偵測到未完成進度之提示視窗
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
        .sheet(isPresented: $isSharePresented) {
            RouteShareView()
        }
        .sheet(isPresented: $isSettingsPresented) {
            SettingsSheet()
        }
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

            // DVT 連線就緒指示燈
            Circle()
                .fill(session.pairingFilePath.isEmpty ? Color.orange : (session.isSimulatingLocation ? Color.blue : Color.green))
                .frame(width: 10, height: 10)

            // 路線中心定位 (FilterCenterFocus)
            Button(action: { session.centerOnRoute() }) {
                Image(systemName: "scope")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.purple)
                    .frame(width: 32, height: 32)
                    .background(Color(UIColor.secondarySystemBackground).opacity(0.92))
                    .cornerRadius(8)
            }

            // 暫存進度 (Save Progress)
            Button(action: { session.saveProgress() }) {
                Image(systemName: "square.and.arrow.down.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.blue)
                    .frame(width: 32, height: 32)
                    .background(Color(UIColor.secondarySystemBackground).opacity(0.92))
                    .cornerRadius(8)
            }

            // 分享路線 (Share)
            Button(action: { isSharePresented = true }) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 14))
                    .foregroundColor(.primary)
                    .frame(width: 32, height: 32)
                    .background(Color(UIColor.secondarySystemBackground).opacity(0.92))
                    .cornerRadius(8)
            }

            // 設定與配對
            Button(action: { isSettingsPresented = true }) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.primary)
                    .frame(width: 32, height: 32)
                    .background(Color(UIColor.secondarySystemBackground).opacity(0.92))
                    .cornerRadius(8)
            }
        }
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
