import SwiftUI
import CoreLocation
import UIKit

public struct RouteShareView: View {
    @ObservedObject var session = AutoFarmSession.shared
    @Environment(\.dismiss) var dismiss

    // 點位來源：0 = 完整實際巡航/繞路軌跡 (預設), 1 = 原始基準航點
    @State private var selectedSourceIndex: Int = 0

    // 檔案名稱
    @State private var customFileName: String = ""

    // 路線變更選項
    @State private var isReversed: Bool = false
    @State private var enableSmartBypass: Bool = false
    @State private var enableDensify: Bool = false
    @State private var speedInput: String = "15.0"
    @State private var selectedFormat: GpxFormat = .joystick

    // 非同步計算狀態 (對齊 Android 避免阻塞主執行緒)
    @State private var currentPoints: [RouteNode] = []
    @State private var isCalculating: Bool = false
    @State private var calculationProgress: Float = 0.0
    @State private var calculationStatus: String = ""
    @State private var calculationTask: Task<Void, Never>? = nil

    // Gofile 雲端分享設定
    @State private var gofileToken: String = UserDefaults.standard.string(forKey: "gofile_token") ?? ""
    @State private var isUploading: Bool = false
    @State private var uploadStatusText: String = ""
    @State private var shareOutputUrlText: String? = nil
    @State private var errorMessage: String? = nil

    public init() {}

    // MARK: - 計算輸入點位來源集合
    private var baseRawPoints: [RouteNode] {
        if selectedSourceIndex == 0 {
            if !session.routePoints.isEmpty {
                return session.routePoints
            } else if !session.originalBasePoints.isEmpty {
                return session.originalBasePoints
            }
        } else {
            if !session.originalBasePoints.isEmpty {
                return session.originalBasePoints
            } else if !session.routePoints.isEmpty {
                return session.routePoints
            }
        }
        return []
    }

    private var targetPoints: [RouteNode] {
        return currentPoints
    }

    private var exportBaseName: String {
        let trimmed = customFileName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        let sessionName = session.activeRouteName.trimmingCharacters(in: .whitespacesAndNewlines)
        return sessionName.isEmpty || sessionName == "無路線" ? "自訂路線" : sessionName
    }

    private var totalDistanceMeters: Double {
        var total = 0.0
        guard currentPoints.count >= 2 else { return 0.0 }
        for i in 0..<(currentPoints.count - 1) {
            total += EngineMath.getDistance(lat1: currentPoints[i].lat, lon1: currentPoints[i].lng, lat2: currentPoints[i+1].lat, lon2: currentPoints[i+1].lng)
        }
        return total
    }

    private var estimatedTimeStr: String {
        let speedKmH = Double(speedInput) ?? 15.0
        guard speedKmH > 0 else { return "0 秒" }
        let speedMs = speedKmH / 3.6
        let totalSeconds = Int(totalDistanceMeters / speedMs)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return "\(hours) 時 \(minutes) 分 \(seconds) 秒"
        } else if minutes > 0 {
            return "\(minutes) 分 \(seconds) 秒"
        } else {
            return "\(seconds) 秒"
        }
    }

    public var body: some View {
        NavigationView {
            Form {
                // 1. 點位來源選擇
                Section(header: Text("點位來源選擇")) {
                    Picker("點位來源", selection: $selectedSourceIndex) {
                        Text("實際運行/繞路軌跡 (\(session.routePoints.count) 點)").tag(0)
                        Text("原始基準點位 (\(session.originalBasePoints.count) 點)").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: selectedSourceIndex) { _ in
                        recalculateRoute()
                    }

                    if selectedSourceIndex == 0 && session.routePoints.count > session.originalBasePoints.count {
                        Text("目前包含雙圈種花、果實漫步或同心圓等完整生成的實際巡航軌跡。")
                            .font(.caption2)
                            .foregroundColor(.green)
                    }
                }

                // 2. 路線基本資訊與統計卡片 (對齊 Android 卡片 1)
                Section(header: Text("路線基本資訊")) {
                    HStack {
                        Text("檔案名稱")
                        TextField("輸入檔案名稱", text: $customFileName)
                            .multilineTextAlignment(.trailing)
                        if !customFileName.isEmpty && customFileName != (session.activeRouteName == "無路線" ? "" : session.activeRouteName) {
                            Button(action: {
                                customFileName = session.activeRouteName == "無路線" ? "" : session.activeRouteName
                            }) {
                                Image(systemName: "arrow.counterclockwise.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(BorderlessButtonStyle())
                        }
                    }

                    HStack {
                        Text("點位數量")
                        Spacer()
                        if isCalculating {
                            Text("計算中 (\(Int(calculationProgress * 100))%)...")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.blue)
                        } else {
                            Text("\(currentPoints.count) 個點位" + (enableDensify ? " (含碎步)" : "") + (enableSmartBypass ? " (含避障)" : ""))
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.primary)
                        }
                    }

                    HStack {
                        Text("路線總長")
                        Spacer()
                        if isCalculating {
                            Text("計算中...")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.secondary)
                        } else {
                            Text(totalDistanceMeters >= 1000 ? String(format: "%.2f 公里", totalDistanceMeters / 1000.0) : "\(Int(totalDistanceMeters)) 公尺")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.blue)
                        }
                    }

                    HStack {
                        Text("預估耗時 (@\(speedInput) km/h)")
                        Spacer()
                        if isCalculating {
                            Text("計算中...")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.secondary)
                        } else {
                            Text(estimatedTimeStr)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.orange)
                        }
                    }

                    // 計算中進度指示條 (對齊 Android)
                    if isCalculating {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(calculationStatus.isEmpty ? "正在計算避障繞路..." : calculationStatus)
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.blue)
                                Spacer()
                                Text("\(Int(calculationProgress * 100))%")
                                    .font(.system(size: 13, weight: .heavy))
                                    .foregroundColor(.blue)
                            }
                            ProgressView(value: Double(calculationProgress))
                                .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                        }
                        .padding(10)
                        .background(Color.blue.opacity(0.08))
                        .cornerRadius(10)
                    }
                }

                // 3. 移動速度設定 (對齊 Android 卡片 2)
                Section(header: Text("移動速度設定 (影響預估時間)")) {
                    HStack(spacing: 8) {
                        ForEach([("9.5", "9.5km/h (慢走/孵蛋)"), ("15.0", "15km/h (快跑)"), ("30.0", "30km/h (單車)")], id: \.0) { spd, lbl in
                            Button(action: { speedInput = spd }) {
                                Text(lbl)
                                    .font(.system(size: 11, weight: speedInput == spd ? .bold : .regular))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 7)
                                    .background(speedInput == spd ? Color.blue : Color(UIColor.secondarySystemBackground))
                                    .foregroundColor(speedInput == spd ? .white : .primary)
                                    .cornerRadius(8)
                            }
                            .buttonStyle(BorderlessButtonStyle())
                        }
                    }

                    HStack {
                        Text("自訂時速 (km/h)")
                        Spacer()
                        TextField("15.0", text: $speedInput)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                }

                // 4. 路線變更選項 (對齊 Android 卡片 3：反轉、避障、插點)
                Section(header: Text("路線變更選項 (反轉、插點、避障)")) {
                    // 反轉路線按鈕
                    Button(action: {
                        isReversed.toggle()
                        recalculateRoute()
                    }) {
                        HStack {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text(isReversed ? "路線方向：已反轉掉頭 (點此還原)" : "一鍵反轉路線 (起終點掉頭)")
                                .fontWeight(isReversed ? .bold : .regular)
                            Spacer()
                            if isReversed {
                                Text("已反轉")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }
                    }

                    // gpxshare 收果安全繞路 Switch (50m 核心避障)
                    Toggle(isOn: $enableSmartBypass) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Image(systemName: "shield.fill")
                                    .foregroundColor(enableSmartBypass ? .blue : .primary)
                                    .font(.system(size: 13))
                                Text("套用收果安全繞路 (50m 弧度避障)")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(enableSmartBypass ? .blue : .primary)
                            }
                            Text("使用 gpxshare 演算法繞開花田 50m 禁區核心，沿外圍 60~70m 平滑穿梭")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .onChange(of: enableSmartBypass) { val in
                        if val {
                            enableDensify = true
                        }
                        recalculateRoute()
                    }

                    // 模擬步行碎步插點 Switch
                    Toggle(isOn: $enableDensify) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Image(systemName: "figure.walk")
                                    .foregroundColor(enableDensify ? .blue : .primary)
                                    .font(.system(size: 13))
                                Text("啟用模擬步行插點 (平滑繞行防鎖)")
                                    .font(.system(size: 14, weight: .medium))
                            }
                            Text("在長直線距離中每 100~150m 自動補隨機碎步防直飛偵測")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .onChange(of: enableDensify) { _ in
                        recalculateRoute()
                    }
                }

                // 5. 飛人匯出格式選擇 (對齊 Android 卡片 4：5 款格式 Radio 說明)
                Section(header: Text("選擇 GPX 匯出格式")) {
                    ForEach(GpxFormat.allCases) { fmt in
                        Button(action: { selectedFormat = fmt }) {
                            HStack {
                                Image(systemName: selectedFormat == fmt ? "largecircle.fill.circle" : "circle")
                                    .foregroundColor(selectedFormat == fmt ? .blue : .secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(fmt.displayName)
                                        .font(.system(size: 14, weight: selectedFormat == fmt ? .bold : .regular))
                                        .foregroundColor(.primary)
                                    Text(fmt.isTrack ? "適合支援自動行走的軌跡模式 (TRK 軌跡)" : "適合標記地標點位的航點模式 (WPT 航點)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                            }
                        }
                        .buttonStyle(BorderlessButtonStyle())
                    }
                }

                // 6. 雲端分享設定與產生網址 (對齊 Android 卡片 5：Gofile 整合)
                Section(header: Text("雲端分享設定 (產生公開下載網址)")) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "cloud.fill")
                                .foregroundColor(.purple)
                            Text("Gofile API Token")
                                .font(.system(size: 13, weight: .medium))
                            Spacer()
                            Text("選填")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        TextField("例如：xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx", text: $gofileToken)
                            .font(.system(size: 12, design: .monospaced))
                            .onChange(of: gofileToken) { val in
                                UserDefaults.standard.set(val.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "gofile_token")
                            }
                        Text("想產生像 gpxshare 一樣的公開下載連結？填寫將自動歸戶至您的 Gofile 帳號；若無亦可留空以訪客身份匿名上傳。Token 會自動儲存於本機。")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    if isUploading {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text(uploadStatusText)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.purple)
                        }
                        .padding(.vertical, 4)
                    }

                    HStack(spacing: 8) {
                        // 按鈕 1: 產生 ZIP 網址
                        Button(action: uploadAllFormatsZip) {
                            HStack(spacing: 4) {
                                Image(systemName: "doc.zipper")
                                Text("產生 ZIP 網址")
                                    .font(.system(size: 13, weight: .bold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(Color.purple)
                            .foregroundColor(.white)
                            .cornerRadius(9)
                        }
                        .buttonStyle(BorderlessButtonStyle())
                        .disabled(isUploading || currentPoints.isEmpty || isCalculating)

                        // 按鈕 2: 5 格式放入同資料夾
                        Button(action: uploadAllFormatsFolder) {
                            HStack(spacing: 4) {
                                Image(systemName: "folder.badge.plus")
                                Text("5格式同資料夾")
                                    .font(.system(size: 13, weight: .bold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(9)
                        }
                        .buttonStyle(BorderlessButtonStyle())
                        .disabled(isUploading || currentPoints.isEmpty || isCalculating)
                    }

                    // 雲端分享結果展示 (對齊 Android：文字框 + 一鍵複製 + 轉傳到 LINE / 聊天)
                    if let resultUrl = shareOutputUrlText {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("雲端分享連結已生成 (已自動複製)：")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.green)
                            }

                            Text(resultUrl)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.primary)
                                .padding(8)
                                .background(Color(UIColor.secondarySystemBackground))
                                .cornerRadius(8)

                            HStack(spacing: 8) {
                                Button(action: {
                                    UIPasteboard.general.string = resultUrl
                                    session.showToast("已複製分享文案與下載連結！")
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "doc.on.doc")
                                        Text("一鍵複製文字")
                                            .font(.system(size: 12, weight: .bold))
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(Color.green)
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                                }
                                .buttonStyle(BorderlessButtonStyle())

                                Button(action: shareResultText) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "square.and.arrow.up")
                                        Text("轉傳到 LINE / 聊天")
                                            .font(.system(size: 12, weight: .bold))
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                                }
                                .buttonStyle(BorderlessButtonStyle())
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    if let err = errorMessage {
                        Text(err)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }

                // 7. 本機匯出與發送動作區 (對齊 Android 卡片 6)
                Section(header: Text("本機匯出與動作")) {
                    // 1. 儲存/傳送選定 GPX
                    Button(action: exportAndShareSingleGpx) {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text(isCalculating ? "路徑計算中 (\(Int(calculationProgress * 100))%)..." : "傳送 / 儲存此格式 (.gpx)")
                                .fontWeight(.bold)
                        }
                    }
                    .disabled(isCalculating || currentPoints.isEmpty)

                    // 2. 一鍵打包全格式 ZIP 懶人包
                    Button(action: exportAndShareZip) {
                        HStack {
                            Image(systemName: "doc.zipper")
                            Text(isCalculating ? "路徑計算中 (\(Int(calculationProgress * 100))%)..." : "打包全格式 ZIP 傳送 / 儲存 (.zip)")
                                .fontWeight(.bold)
                                .foregroundColor(.green)
                        }
                    }
                    .disabled(isCalculating || currentPoints.isEmpty)

                    // 3. 複製純座標文字
                    Button(action: copyCoordinatesText) {
                        HStack {
                            Image(systemName: "doc.on.doc")
                            Text(isCalculating ? "路徑計算中 (\(Int(calculationProgress * 100))%)..." : "複製純座標文字 (可貼記事本/LINE)")
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                        }
                    }
                    .disabled(isCalculating || currentPoints.isEmpty)
                }
            }
            .navigationTitle("路線分享與格式轉換")
            .navigationBarItems(trailing: Button("完成") { dismiss() })
            .onAppear {
                if customFileName.isEmpty {
                    customFileName = session.activeRouteName == "無路線" ? "" : session.activeRouteName
                }
                if !session.routePoints.isEmpty {
                    selectedSourceIndex = 0
                }
                recalculateRoute()
            }
        }
    }

    // MARK: - 背景非同步計算路線點位 (對齊 Android 避免 ANR 與畫面掉幀)
    private func recalculateRoute() {
        let baseRaw = baseRawPoints
        guard !baseRaw.isEmpty else {
            self.currentPoints = []
            return
        }

        calculationTask?.cancel()
        isCalculating = true
        calculationProgress = 0.0
        calculationStatus = "準備處理..."

        let reversed = isReversed
        let smartBypass = enableSmartBypass
        let densify = enableDensify

        calculationTask = Task.detached(priority: .userInitiated) {
            let base = reversed ? baseRaw.reversed() : baseRaw
            let processed: [RouteNode]

            if smartBypass && !base.isEmpty {
                processed = RouteShareManager.processSmartRoute(
                    points: base,
                    minStep: 100.0,
                    maxStep: 150.0,
                    densify: densify,
                    attemptReorder: true
                ) { p, msg in
                    Task { @MainActor in
                        self.calculationProgress = p
                        self.calculationStatus = msg
                    }
                }
            } else if densify && !base.isEmpty {
                Task { @MainActor in
                    self.calculationProgress = 0.5
                    self.calculationStatus = "正在套用碎步插點..."
                }
                processed = EngineMath.densifyRoute(points: base)
            } else {
                processed = base
            }

            if !Task.isCancelled {
                await MainActor.run {
                    self.currentPoints = processed
                    self.calculationProgress = 1.0
                    self.calculationStatus = "完成"
                    self.isCalculating = false
                }
            }
        }
    }

    // MARK: - 單一格式 GPX 分享
    private func exportAndShareSingleGpx() {
        let pts = targetPoints
        guard !pts.isEmpty else { return }
        let gpxStr = RouteShareManager.generateGpx(points: pts, format: selectedFormat, routeName: exportBaseName)
        let fileName = "\(exportBaseName)\(selectedFormat.suffix).gpx"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try gpxStr.write(to: tempURL, atomically: true, encoding: .utf8)
            RouteShareManager.shareFile(fileURL: tempURL)
        } catch {
            errorMessage = "寫入檔案失敗: \(error.localizedDescription)"
        }
    }

    // MARK: - 打包全格式 ZIP 並本機分享
    private func exportAndShareZip() {
        let pts = targetPoints
        guard !pts.isEmpty else { return }
        let zipData = RouteShareManager.generateAllFormatsZip(points: pts, routeName: exportBaseName)
        RouteShareManager.shareZipFile(data: zipData, routeName: exportBaseName)
    }

    // MARK: - 複製純座標文字至剪貼簿
    private func copyCoordinatesText() {
        let pts = targetPoints
        guard !pts.isEmpty else { return }
        let coordsText = pts.map { "\(String(format: "%.6f", $0.lat)), \(String(format: "%.6f", $0.lng))" }.joined(separator: "\n")
        UIPasteboard.general.string = coordsText
        session.showToast("已複製 \(pts.count) 個座標文字！")
    }

    // MARK: - 轉傳雲端結果文案
    private func shareResultText() {
        guard let text = shareOutputUrlText else { return }
        RouteShareManager.shareItems([text])
    }

    // MARK: - 產生 ZIP 全格式懶人包並上傳 Gofile
    private func uploadAllFormatsZip() {
        let pts = targetPoints
        guard !pts.isEmpty else { return }

        isUploading = true
        errorMessage = nil
        shareOutputUrlText = nil
        uploadStatusText = "正在打包全格式 ZIP 壓縮包..."

        let tokenParam = gofileToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : gofileToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = exportBaseName

        Task {
            do {
                let zipData = RouteShareManager.generateAllFormatsZip(points: pts, routeName: name)
                let zipName = "\(name)_全格式懶人包.zip"

                await MainActor.run {
                    self.uploadStatusText = "正在上傳 ZIP 到 Gofile..."
                }

                let response = try await RouteShareManager.uploadToGofile(
                    fileName: zipName,
                    fileData: zipData,
                    token: tokenParam
                ) { status in
                    Task { @MainActor in
                        self.uploadStatusText = status
                    }
                }

                await MainActor.run {
                    self.isUploading = false
                    let resultMsg = "【\(name)】路線全格式懶人包 (ZIP) 已上傳！\n專屬下載網址：\n\(response.downloadPage)\n\n(內含 5 種主流飛人 GPX 與 AutoFarm 原生格式)"
                    self.shareOutputUrlText = resultMsg
                    UIPasteboard.general.string = response.downloadPage
                    session.showToast("上傳成功！已複製下載網址")
                }
            } catch {
                await MainActor.run {
                    self.isUploading = false
                    self.errorMessage = "上傳失敗: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - 5 種格式放入同一個 Gofile 資料夾
    private func uploadAllFormatsFolder() {
        let pts = targetPoints
        guard !pts.isEmpty else { return }

        isUploading = true
        errorMessage = nil
        shareOutputUrlText = nil
        uploadStatusText = "正在建立雲端資料夾並依序上傳 5 種格式..."

        var effectiveToken = gofileToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : gofileToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = exportBaseName
        let formats = GpxFormat.allCases

        Task {
            do {
                var sharedFolderId: String? = nil
                var folderUrl: String = ""
                var successCount = 0

                for (idx, fmt) in formats.enumerated() {
                    await MainActor.run {
                        self.uploadStatusText = "正在上傳 (\(idx + 1)/\(formats.count))：\(fmt.displayName)..."
                    }

                    let gpxContent = RouteShareManager.generateGpx(points: pts, format: fmt, routeName: name)
                    guard let gpxData = gpxContent.data(using: .utf8) else { continue }
                    let fileName = "\(name)\(fmt.suffix).gpx"

                    let resp = try await RouteShareManager.uploadToGofile(
                        fileName: fileName,
                        fileData: gpxData,
                        token: effectiveToken,
                        folderId: sharedFolderId
                    ) { status in
                        Task { @MainActor in
                            self.uploadStatusText = "(\(idx + 1)/\(formats.count)) \(status)"
                        }
                    }

                    successCount += 1
                    folderUrl = resp.downloadPage
                    if sharedFolderId == nil && !resp.parentFolder.isEmpty {
                        sharedFolderId = resp.parentFolder
                    }
                    if effectiveToken == nil && resp.guestToken != nil {
                        effectiveToken = resp.guestToken
                    }

                    try await Task.sleep(nanoseconds: 300_000_000) // 0.3s 間隔
                }

                await MainActor.run {
                    self.isUploading = false
                    if successCount > 0 {
                        let finalUrl = sharedFolderId != nil ? "https://gofile.io/d/\(sharedFolderId!)" : folderUrl
                        let resultMsg = "【\(name)】5 種飛人專用格式已全數上傳至同一個資料夾！\n\n整合資料夾下載網址：\n\(finalUrl)\n\n(點開網址即可直接下載以下 5 種格式：\n• JoyStick TRK / AnyTo TRK / iTools WPT / Flashman WPT / FakeGPS WPT)"
                        self.shareOutputUrlText = resultMsg
                        UIPasteboard.general.string = finalUrl
                        session.showToast("已將 5 份格式成功放入同資料夾！")
                    } else {
                        self.errorMessage = "未能上傳任何格式"
                    }
                }
            } catch {
                await MainActor.run {
                    self.isUploading = false
                    self.errorMessage = "上傳失敗: \(error.localizedDescription)"
                }
            }
        }
    }
}
