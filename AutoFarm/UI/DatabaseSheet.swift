import SwiftUI
import UniformTypeIdentifiers

public struct DatabaseSheet: View {
    @ObservedObject var db = SavedDatabaseStore.shared
    @ObservedObject var session = AutoFarmSession.shared
    @Environment(\.dismiss) var dismiss

    @State private var selectedTab: Int = 0 // 0: 座標庫, 1: 路徑庫
    @State private var isFileImporterPresented: Bool = false
    @State private var isPasteImportPresented: Bool = false
    @State private var pasteRouteName: String = ""
    @State private var pasteCoordinatesText: String = ""

    @State private var isAddLocationPresented: Bool = false
    @State private var newLocName: String = ""
    @State private var newLocLat: String = ""
    @State private var newLocLng: String = ""

    @State private var selectedRouteForMode: SavedRoute? = nil

    public init() {}

    public var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Picker("資料庫類別", selection: $selectedTab) {
                    Text("座標資料庫 (\(db.savedLocations.count))").tag(0)
                    Text("路徑資料庫 (\(db.savedRoutes.count))").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 10)

                if selectedTab == 0 {
                    locationsView
                } else {
                    routesView
                }
            }
            .navigationTitle("座標與路徑資料庫")
            .navigationBarItems(
                leading: Button("關閉") { dismiss() },
                trailing: headerTrailingButton
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
                switch result {
                case .success(let url):
                    let (success, name, count, error) = db.importRouteFromFile(url: url)
                    if success {
                        session.toastMessage = "成功匯入路線【\(name)】共 \(count) 點！"
                    } else {
                        session.toastMessage = error ?? "匯入失敗"
                    }
                case .failure(let err):
                    session.toastMessage = "選取檔案失敗: \(err.localizedDescription)"
                }
            }
            .sheet(isPresented: $isPasteImportPresented) {
                pasteImportSheet
            }
            .sheet(isPresented: $isAddLocationPresented) {
                addLocationSheet
            }
            .actionSheet(item: $selectedRouteForMode) { route in
                ActionSheet(
                    title: Text("【\(route.name)】共 \(route.nodes.count) 點"),
                    message: Text("請選擇此路線的執行模式："),
                    buttons: [
                        .default(Text("直線巡航 (依序循環)")) {
                            session.startLinearRoute(
                                name: route.name,
                                basePoints: route.nodes,
                                loops: 0,
                                mode: session.loopMode
                            )
                            dismiss()
                        },
                        .default(Text("繞圈種花 (多花點雙圈28m/24m)")) {
                            session.startFlowerRoute(
                                name: route.name,
                                basePoints: route.nodes,
                                loops: 0,
                                settings: session.flowerSettings
                            )
                            dismiss()
                        },
                        .default(Text("跳收果實 (南北80m直徑行走)")) {
                            session.startFruitRoute(
                                name: route.name,
                                basePoints: route.nodes,
                                loops: 0,
                                walkDistance: 80.0
                            )
                            dismiss()
                        },
                        .cancel(Text("取消"))
                    ]
                )
            }
        }
    }

    // MARK: - 座標庫視圖
    private var locationsView: some View {
        List {
            if db.savedLocations.isEmpty {
                Text("尚未儲存任何座標。可在地圖長按或點選目前位置進行儲存。")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                ForEach(db.savedLocations) { loc in
                    Button(action: {
                        session.teleport(to: loc.latitude, lng: loc.longitude)
                        dismiss()
                    }) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(loc.name)
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.primary)
                                Text("\(String(format: "%.6f", loc.latitude)), \(String(format: "%.6f", loc.longitude))")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Text("點擊瞬移")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }
                }
                .onDelete { indexSet in
                    for i in indexSet {
                        let id = db.savedLocations[i].id
                        db.deleteLocation(id: id)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - 路徑庫視圖
    private var routesView: some View {
        VStack(spacing: 0) {
            // 匯入捷徑列 (檔案匯入 + 貼上匯入)
            HStack(spacing: 8) {
                Button(action: { isFileImporterPresented = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.down.fill")
                        Text("匯入 GPX/CSV/TXT")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.purple)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }

                Button(action: {
                    pasteRouteName = ""
                    pasteCoordinatesText = ""
                    isPasteImportPresented = true
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.clipboard.fill")
                        Text("貼上座標匯入")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            List {
                if db.savedRoutes.isEmpty {
                    Text("尚未儲存任何路徑。可點擊上方按鈕貼上座標匯入。")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(db.savedRoutes) { route in
                        Button(action: {
                            self.selectedRouteForMode = route
                        }) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(route.name)
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(.primary)
                                    Text("共 \(route.nodes.count) 個航點")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Text("選擇模式 >")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                    .onDelete { indexSet in
                        for i in indexSet {
                            let id = db.savedRoutes[i].id
                            db.deleteRoute(id: id)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    @ViewBuilder
    private var headerTrailingButton: some View {
        if selectedTab == 0 {
            Button(action: {
                newLocName = ""
                newLocLat = "\(session.currentLat)"
                newLocLng = "\(session.currentLng)"
                isAddLocationPresented = true
            }) {
                Image(systemName: "plus")
            }
        }
    }

    // MARK: - 貼上座標匯入 Sheet
    private var pasteImportSheet: some View {
        NavigationView {
            Form {
                Section(header: Text("路線基本資訊")) {
                    TextField("輸入路線名稱 (例如：大安花區巡航)", text: $pasteRouteName)
                }

                Section(header: Text("貼上座標列表 (支援多行，格式：lat,lng)"), footer: Text("範例：\n25.033964, 121.564468\n25.034500, 121.565200\n支援以逗號或空格分隔之經緯度座標。")) {
                    TextEditor(text: $pasteCoordinatesText)
                        .frame(minHeight: 180)
                        .font(.system(size: 12, design: .monospaced))
                }

                Section {
                    Button(action: handlePasteImport) {
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
            .navigationTitle("貼上座標匯入路徑")
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
                        }
                    }
                }
            }
            .navigationTitle("新增座標")
            .navigationBarItems(leading: Button("取消") { isAddLocationPresented = false })
        }
    }

    private func handlePasteImport() {
        let (success, count) = db.importRouteFromPastedText(name: pasteRouteName, text: pasteCoordinatesText)
        if success {
            isPasteImportPresented = false
        }
    }
}
