import SwiftUI

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

    // Gofile 雲端分享設定
    @State private var gofileToken: String = UserDefaults.standard.string(forKey: "gofile_token") ?? ""
    @State private var isUploading: Bool = false
    @State private var uploadStatusText: String = ""
    @State private var shareOutputUrlText: String? = nil
    @State private var errorMessage: String? = nil

    public init() {}

    // MARK: - 計算輸出點位集合
    private var baseRawPoints: [RouteNode] {
        if selectedSourceIndex == 0 {
            // 優先取實際生成之完整巡航/繞路軌跡 (含花圈、果實、同心圓、繞路)
            if !session.routePoints.isEmpty {
                return session.routePoints
            } else if !session.originalBasePoints.isEmpty {
                return session.originalBasePoints
            }
        } else {
            // 取原始基準航點
            if !session.originalBasePoints.isEmpty {
                return session.originalBasePoints
            } else if !session.routePoints.isEmpty {
                return session.routePoints
            }
        }
        return []
    }

    private var targetPoints: [RouteNode] {
        var pts = baseRawPoints
        if isReversed {
            pts = pts.reversed()
        }
        if enableSmartBypass && pts.count >= 2 {
            pts = RouteShareManager.processSmartRoute(points: pts, densify: enableDensify)
        } else if enableDensify && pts.count >= 2 {
            pts = EngineMath.densifyRoute(points: pts)
        }
        return pts
    }

    private var exportBaseName: String {
        let trimmed = customFileName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        let sessionName = session.activeRouteName.trimmingCharacters(in: .whitespacesAndNewlines)
        return sessionName.isEmpty || sessionName == "無路線" ? "自訂路線" : sessionName
    }

    private var totalDistanceMeters: Double {
        var total = 0.0
        let pts = targetPoints
        guard pts.count >= 2 else { return 0.0 }
        for i in 0..<(pts.count - 1) {
            total += EngineMath.getDistance(lat1: pts[i].lat, lon1: pts[i].lng, lat2: pts[i+1].lat, lon2: pts[i+1].lng)
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
                // 1. 點位來源選擇 (解決純點位問題)
                Section(header: Text("點位來源選擇")) {
                    Picker("點位來源", selection: $selectedSourceIndex) {
                        Text("實際運行/繞路軌跡 (\(session.routePoints.count) 點)").tag(0)
                        Text("原始基準點位 (\(session.originalBasePoints.count) 點)").tag(1)
                    }
                    .pickerStyle(.segmented)

                    if selectedSourceIndex == 0 && session.routePoints.count > session.originalBasePoints.count {
                        Text("目前包含雙圈種花、果實漫步或同心圓等完整生成的實際巡航軌跡。")
                            .font(.caption2)
                            .foregroundColor(.green)
                    }
                }

                // 2. 基本資訊與統計卡片
                Section(header: Text("路線基本資訊")) {
                    HStack {
                        Text("自訂名稱")
                        TextField("輸入檔案名稱", text: $customFileName)
                            .multilineTextAlignment(.trailing)
                    }

                    HStack {
                        Text("輸出點位")
                        Spacer()
                        Text("\(targetPoints.count) 點" + (enableDensify ? " (含碎步)" : "") + (enableSmartBypass ? " (含避障)" : ""))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.primary)
                    }

                    HStack {
                        Text("路線總長")
                        Spacer()
                        Text(totalDistanceMeters >= 1000 ? String(format: "%.2f 公里", totalDistanceMeters / 1000.0) : "\(Int(totalDistanceMeters)) 公尺")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.blue)
                    }

                    HStack {
                        Text("預估耗時 (@\(speedInput) km/h)")
                        Spacer()
                        Text(estimatedTimeStr)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.orange)
                    }
                }

                // 3. 路線變更與優化選項 (對齊安卓版)
                Section(header: Text("路線變更與優化選項")) {
                    // 反轉路線
                    Button(action: {
                        isReversed.toggle()
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

                    // 50m 收果安全繞路
                    Toggle(isOn: $enableSmartBypass) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("套用收果安全繞路 (50m 弧度避障)")
                                .font(.system(size: 14, weight: .medium))
                            Text("繞開花田 50m 核心禁區，沿外圍 60~70m 平滑穿梭")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }

                    // 模擬真人碎步插點
                    Toggle(isOn: $enableDensify) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("模擬真人碎步插點 (densifyRoute)")
                                .font(.system(size: 14, weight: .medium))
                            Text("長直線中每 100~150m 自動補隨機步伐防直飛")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }

                    // 移動時速快捷設定
                    VStack(alignment: .leading, spacing: 6) {
                        Text("預估時速 (km/h)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        HStack(spacing: 8) {
                            Button("9.5 (慢走)") { speedInput = "9.5" }
                                .buttonStyle(.bordered)
                                .font(.caption)
                            Button("15.0 (快跑)") { speedInput = "15.0" }
                                .buttonStyle(.bordered)
                                .font(.caption)
                            Button("30.0 (單車)") { speedInput = "30.0" }
                                .buttonStyle(.bordered)
                                .font(.caption)
                            Spacer()
                            TextField("15.0", text: $speedInput)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 60)
                        }
                    }
                }

                // 4. GPX 格式與原生分享
                Section(header: Text("GPX 格式與本機分享")) {
                    Picker("選擇格式", selection: $selectedFormat) {
                        ForEach(GpxFormat.allCases) { format in
                            Text(format.displayName).tag(format)
                        }
                    }

                    Button(action: exportAndShareSingleGpx) {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("系統分享 \(selectedFormat.displayName)")
                                .fontWeight(.bold)
                        }
                    }
                }

                // 5. Gofile 雲端分享 (對齊安卓版完整功能)
                Section(header: Text("Gofile 雲端分享 (產生公開短網址)")) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Gofile Account Token")
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
                        Text("選填。填寫將自動歸戶至您的 Gofile 帳號管理；留空則以訪客匿名身份上傳。Token 會自動儲存於本機。")
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
                            .padding(.vertical, 8)
                            .background(Color.purple)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                        }
                        .disabled(isUploading || targetPoints.isEmpty)

                        // 按鈕 2: 5 格式放入同資料夾
                        Button(action: uploadAllFormatsFolder) {
                            HStack(spacing: 4) {
                                Image(systemName: "folder.badge.plus")
                                Text("5格式同資料夾")
                                    .font(.system(size: 13, weight: .bold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                        }
                        .disabled(isUploading || targetPoints.isEmpty)
                    }

                    // 雲端分享結果展示
                    if let resultUrl = shareOutputUrlText {
                        VStack(alignment: .leading, spacing: 6) {
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
                                .cornerRadius(6)

                            Button(action: {
                                UIPasteboard.general.string = resultUrl
                                session.toastMessage = "已重新複製連結至剪貼簿！"
                            }) {
                                HStack {
                                    Spacer()
                                    Image(systemName: "doc.on.doc")
                                    Text("再次複製網址")
                                        .font(.caption)
                                        .fontWeight(.bold)
                                    Spacer()
                                }
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
            }
            .navigationTitle("路線分享與雲端")
            .navigationBarItems(trailing: Button("完成") { dismiss() })
            .onAppear {
                if customFileName.isEmpty {
                    customFileName = session.activeRouteName == "無路線" ? "" : session.activeRouteName
                }
                // 預設若有生成之擴展點位，選定實際巡航軌跡
                if !session.routePoints.isEmpty {
                    selectedSourceIndex = 0
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
                    session.toastMessage = "上傳成功！已複製下載網址"
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
                        session.toastMessage = "已將 5 份格式成功放入同資料夾！"
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
