import SwiftUI
import UniformTypeIdentifiers

public struct DatabaseSheet: View {
    @ObservedObject var db = SavedDatabaseStore.shared
    @ObservedObject var session = AutoFarmSession.shared
    @Environment(\.dismiss) var dismiss

    @State private var selectedTab: Int = 0 // 0: 座標庫, 1: 路徑庫, 2: 瞬移紀錄
    @State private var searchText: String = ""
    @State private var sortMode: DatabaseSortMode = .pinFirst

    // 批次檔案匯入
    @State private var isFileImporterPresented: Bool = false
    @State private var isPasteImportPresented: Bool = false
    @State private var pasteRouteName: String = ""
    @State private var pasteRouteTag: String = ""
    @State private var pasteCoordinatesText: String = ""

    // 全庫備份與還原
    @State private var isRestoreImporterPresented: Bool = false
    @State private var backupShareUrl: URL? = nil
    @State private var isShareBackupPresented: Bool = false

    // 新增座標
    @State private var isAddLocationPresented: Bool = false
    @State private var newLocName: String = ""
    @State private var newLocTag: String = ""
    @State private var newLocNote: String = ""
    @State private var newLocLat: String = ""
    @State private var newLocLng: String = ""

    // 標籤與備忘錄編輯
    @State private var isEditTagAndNotePresented: Bool = false
    @State private var editingItemId: UUID? = nil
    @State private var editingItemIsRoute: Bool = false
    @State private var editingItemTitle: String = ""
    @State private var editingTagText: String = ""
    @State private var editingNoteText: String = ""

    // 路線進度詢問 ActionSheet
    @State private var isResumeRouteChoicePresented: Bool = false
    @State private var routeForResumeChoice: SavedRoute? = nil

    @State private var selectedRouteForConfig: SavedRoute? = nil
    @State private var routeToEdit: SavedRoute? = nil

    public init() {}

    public var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Picker("資料庫類別", selection: $selectedTab) {
                    Text("座標 (\(db.savedLocations.count))").tag(0)
                    Text("路線 (\(db.savedRoutes.count))").tag(1)
                    Text("歷史紀錄 (\(db.locationHistory.count))").tag(2)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)

                if selectedTab == 0 || selectedTab == 1 {
                    searchAndSortBar
                }

                if selectedTab == 0 {
                    locationsView
                } else if selectedTab == 1 {
                    routesView
                } else {
                    locationHistoryView
                }
            }
            .navigationTitle("座標與路徑資料庫")
            .navigationBarItems(
                leading: Button("關閉") { dismiss() },
                trailing: headerTrailingActions
            )
            // 批次匯入 GPX/CSV/TXT (支援多選)
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
                switch result {
                case .success(let urls):
                    guard !urls.isEmpty else { return }
                    let (successCount, failedCount, names) = db.importRoutesFromFiles(urls: urls)
                    if successCount > 0 {
                        let sample = names.prefix(3).joined(separator: ", ")
                        session.toastMessage = "成功批次匯入 \(successCount) 條路線！[\(sample)\(names.count > 3 ? "..." : "")]"
                    } else {
                        session.toastMessage = "匯入失敗，選取檔案中未包含有效座標"
                    }
                case .failure(let err):
                    session.toastMessage = "選取檔案失敗: \(err.localizedDescription)"
                }
            }
            // 還原全庫備份 (JSON)
            .fileImporter(
                isPresented: $isRestoreImporterPresented,
                allowedContentTypes: [UTType.json, UTType.data],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    let (ok, msg) = db.restoreFullBackup(from: url, merge: false)
                    session.toastMessage = msg
                case .failure(let err):
                    session.toastMessage = "還原失敗: \(err.localizedDescription)"
                }
            }
            .sheet(isPresented: $isShareBackupPresented) {
                if let url = backupShareUrl {
                    ActivityView(activityItems: [url])
                }
            }
            .sheet(isPresented: $isPasteImportPresented) {
                pasteImportSheet
            }
            .sheet(isPresented: $isAddLocationPresented) {
                addLocationSheet
            }
            .sheet(isPresented: $isEditTagAndNotePresented) {
                editTagAndNoteSheet
            }
            .sheet(item: $selectedRouteForConfig) { route in
                RouteModeConfigSheet(route: route) { mode, loopMode, loops, flowerSettings, fruitWalkDist in
                    executeSelectedRoute(route: route, mode: mode, loopMode: loopMode, loops: loops, flowerSettings: flowerSettings, fruitWalkDist: fruitWalkDist)
                }
            }
            .sheet(item: $routeToEdit) { route in
                RouteEditorView(route: route)
            }
            .actionSheet(isPresented: $isResumeRouteChoicePresented) {
                resumeRouteActionSheet
            }
        }
    }

    // MARK: - 搜尋與排序欄
    private var searchAndSortBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 13))
                TextField("搜尋名稱、標籤或經緯度...", text: $searchText)
                    .font(.system(size: 13))
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 13))
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(8)

            Menu {
                ForEach(DatabaseSortMode.allCases) { mode in
                    Button(action: { sortMode = mode }) {
                        HStack {
                            Text(mode.rawValue)
                            if sortMode == mode {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 12))
                    Text(sortMode.rawValue)
                        .font(.system(size: 11, weight: .bold))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .background(Color(UIColor.secondarySystemBackground))
                .foregroundColor(.primary)
                .cornerRadius(8)
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 6)
    }

    // MARK: - 頂部動作群 (加號 + 全庫備份選單)
    private var headerTrailingActions: some View {
        HStack(spacing: 12) {
            if selectedTab == 0 {
                Button(action: {
                    newLocName = ""
                    newLocTag = ""
                    newLocNote = ""
                    newLocLat = "\(session.currentLat)"
                    newLocLng = "\(session.currentLng)"
                    isAddLocationPresented = true
                }) {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .bold))
                }
            }

            Menu {
                Section(header: Text("全資料庫備份管理")) {
                    Button(action: {
                        if let url = db.exportFullBackup() {
                            backupShareUrl = url
                            isShareBackupPresented = true
                        } else {
                            session.toastMessage = "匯出備份失敗"
                        }
                    }) {
                        Label("匯出全庫備份 (JSON)", systemImage: "square.and.arrow.up")
                    }

                    Button(action: {
                        isRestoreImporterPresented = true
                    }) {
                        Label("還原全庫備份 (JSON)", systemImage: "square.and.arrow.down")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 16))
            }
        }
    }

    // MARK: - 座標庫視圖
    private var locationsView: some View {
        let list = db.filteredLocations(query: searchText, sortMode: sortMode)
        return List {
            if list.isEmpty {
                Text(searchText.isEmpty ? "尚未儲存任何座標。可在地圖長按或點右上角新增按鈕儲存。" : "無符合搜尋條件的座標。")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                ForEach(list) { loc in
                    HStack(spacing: 8) {
                        Button(action: {
                            db.togglePinLocation(id: loc.id)
                        }) {
                            Image(systemName: loc.isPinned ? "pin.fill" : "pin")
                                .font(.system(size: 14))
                                .foregroundColor(loc.isPinned ? .orange : .secondary.opacity(0.4))
                        }
                        .buttonStyle(BorderlessButtonStyle())

                        Button(action: {
                            session.teleport(to: loc.latitude, lng: loc.longitude, label: loc.name)
                            dismiss()
                        }) {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
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

                                    if !loc.note.isEmpty {
                                        Text(loc.note)
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer()
                                Text("瞬移")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.blue)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.blue.opacity(0.1))
                                    .cornerRadius(6)
                            }
                        }

                        Button(action: {
                            openEditTagAndNote(id: loc.id, isRoute: false, currentTitle: loc.name, currentTag: loc.tag, currentNote: loc.note)
                        }) {
                            Image(systemName: loc.note.isEmpty ? "square.and.pencil" : "note.text")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(BorderlessButtonStyle())
                    }
                }
                .onDelete { indexSet in
                    for i in indexSet {
                        let id = list[i].id
                        db.deleteLocation(id: id)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - 路徑庫視圖
    private var routesView: some View {
        let list = db.filteredRoutes(query: searchText, sortMode: sortMode)
        return VStack(spacing: 0) {
            // 匯入捷徑列 (支援多選批次檔案匯入 + 貼上匯入)
            HStack(spacing: 8) {
                Button(action: { isFileImporterPresented = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.down.on.square.fill")
                        Text("批次匯入 GPX/CSV/TXT")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(Color.purple)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }

                Button(action: {
                    pasteRouteName = ""
                    pasteRouteTag = ""
                    pasteCoordinatesText = ""
                    isPasteImportPresented = true
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.clipboard.fill")
                        Text("貼上座標匯入")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 6)

            List {
                if list.isEmpty {
                    Text(searchText.isEmpty ? "尚未儲存任何路徑。可點擊上方按鈕批次匯入。" : "無符合搜尋條件的路徑。")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(list) { route in
                        HStack(spacing: 8) {
                            Button(action: {
                                db.togglePinRoute(id: route.id)
                            }) {
                                Image(systemName: route.isPinned ? "pin.fill" : "pin")
                                    .font(.system(size: 14))
                                    .foregroundColor(route.isPinned ? .orange : .secondary.opacity(0.4))
                            }
                            .buttonStyle(BorderlessButtonStyle())

                            Button(action: {
                                handleRouteSelected(route)
                            }) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
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

                                        if !route.note.isEmpty {
                                            Text(route.note)
                                                .font(.system(size: 11))
                                                .foregroundColor(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                    Spacer()
                                    Text("設定 >")
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .foregroundColor(.purple)
                                }
                            }

                            // 編輯路線點位按鈕
                            Button(action: {
                                routeToEdit = route
                            }) {
                                Image(systemName: "list.bullet.indent")
                                    .font(.system(size: 14))
                                    .foregroundColor(.blue)
                                    .padding(4)
                            }
                            .buttonStyle(BorderlessButtonStyle())

                            Button(action: {
                                openEditTagAndNote(id: route.id, isRoute: true, currentTitle: route.name, currentTag: route.tag, currentNote: route.note)
                            }) {
                                Image(systemName: route.note.isEmpty ? "square.and.pencil" : "note.text")
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(BorderlessButtonStyle())
                        }
                    }
                    .onDelete { indexSet in
                        for i in indexSet {
                            let id = list[i].id
                            db.deleteRoute(id: id)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    // MARK: - 歷史紀錄視圖
    private var locationHistoryView: some View {
        VStack(spacing: 0) {
            if !db.locationHistory.isEmpty {
                HStack {
                    Text("共 \(db.locationHistory.count) 筆歷史紀錄")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button(action: {
                        db.clearHistory()
                        session.toastMessage = "已清空歷史紀錄"
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
                if db.locationHistory.isEmpty {
                    Text("尚無歷史紀錄。執行單點瞬移或巡航路線後將自動記錄。")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(db.locationHistory) { item in
                        Button(action: {
                            session.executeHistoryItem(item)
                            dismiss()
                        }) {
                            HStack(spacing: 10) {
                                Image(systemName: iconForHistoryItem(item))
                                    .font(.system(size: 16))
                                    .foregroundColor(colorForHistoryItem(item))
                                    .frame(width: 22)

                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(item.type.rawValue)
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 1)
                                            .background(colorForHistoryItem(item))
                                            .cornerRadius(4)

                                        Text(item.title)
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundColor(.primary)
                                            .lineLimit(1)

                                        Spacer()

                                        Text(item.formattedTime)
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                    }

                                    HStack(spacing: 6) {
                                        Text("\(String(format: "%.6f", item.latitude)), \(String(format: "%.6f", item.longitude))")
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundColor(.secondary)

                                        if let nodes = item.routeNodes, !nodes.isEmpty {
                                            Text("・\(nodes.count) 點")
                                                .font(.system(size: 11))
                                                .foregroundColor(.secondary)
                                        }
                                        if item.loops > 0 {
                                            Text("・\(item.loops) 圈")
                                                .font(.system(size: 11))
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }

                                Spacer()

                                Text(item.type == .teleport ? "瞬移" : "執行")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(colorForHistoryItem(item))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(colorForHistoryItem(item).opacity(0.12))
                                    .cornerRadius(6)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
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

    // MARK: - 路線處理
    private func handleRouteSelected(_ route: SavedRoute) {
        if RouteProgressStore.hasProgress(for: route.name) {
            self.routeForResumeChoice = route
            self.isResumeRouteChoicePresented = true
        } else {
            self.selectedRouteForConfig = route
        }
    }

    private var resumeRouteActionSheet: ActionSheet {
        let name = routeForResumeChoice?.name ?? "此路線"
        return ActionSheet(
            title: Text("發現路線【\(name)】暫存進度"),
            message: Text("此路線有先前暫存之進度，請選擇執行方式："),
            buttons: [
                .default(Text("接續上次進度")) {
                    if let r = routeForResumeChoice, let progress = RouteProgressStore.getProgress(for: r.name) {
                        session.resumeProgress(progress)
                        dismiss()
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
        dismiss()
    }

    // MARK: - 標籤與備忘錄編輯 Sheet
    private func openEditTagAndNote(id: UUID, isRoute: Bool, currentTitle: String, currentTag: String, currentNote: String) {
        self.editingItemId = id
        self.editingItemIsRoute = isRoute
        self.editingItemTitle = currentTitle
        self.editingTagText = currentTag
        self.editingNoteText = currentNote
        self.isEditTagAndNotePresented = true
    }

    private var editTagAndNoteSheet: some View {
        NavigationView {
            Form {
                Section(header: Text("項目資訊")) {
                    Text(editingItemTitle)
                        .font(.headline)
                }

                Section(header: Text("標籤分類")) {
                    TextField("標籤名稱 (例：花苞區、日常補給)", text: $editingTagText)
                }

                Section(header: Text("備忘錄筆記 (Notes)")) {
                    TextEditor(text: $editingNoteText)
                        .frame(minHeight: 100)
                }

                Section {
                    Button("儲存變更") {
                        if let id = editingItemId {
                            if editingItemIsRoute {
                                db.updateRouteTag(id: id, tag: editingTagText)
                                db.updateRouteNote(id: id, note: editingNoteText)
                            } else {
                                db.updateLocationTag(id: id, tag: editingTagText)
                                db.updateLocationNote(id: id, note: editingNoteText)
                            }
                        }
                        isEditTagAndNotePresented = false
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundColor(.blue)
                }
            }
            .navigationTitle("編輯標籤與備忘錄")
            .navigationBarItems(leading: Button("取消") { isEditTagAndNotePresented = false })
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
                    TextField("備忘錄筆記 (選填)", text: $newLocNote)
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
                            db.addLocation(name: newLocName, latitude: lat, longitude: lng, tag: newLocTag, note: newLocNote)
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

// MARK: - 原生分享控制器封裝
public struct ActivityView: UIViewControllerRepresentable {
    public let activityItems: [Any]

    public func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    public func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
