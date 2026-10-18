import SwiftUI

public struct RouteShareView: View {
    @ObservedObject var session = AutoFarmSession.shared
    @Environment(\.dismiss) var dismiss

    @State private var selectedFormat: GpxFormat = .joystick
    @State private var enableDensify: Bool = false
    @State private var speedInput: String = "15.0"
    @State private var isUploading: Bool = false
    @State private var uploadedUrl: String? = nil
    @State private var errorMessage: String? = nil

    public init() {}

    private var targetPoints: [RouteNode] {
        let pts = !session.originalBasePoints.isEmpty ? session.originalBasePoints : session.routePoints
        if enableDensify {
            return EngineMath.densifyRoute(points: pts)
        }
        return pts
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
                Section(header: Text("路線資訊")) {
                    HStack {
                        Text("路線名稱")
                        Spacer()
                        Text(session.activeRouteName)
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("航點數量")
                        Spacer()
                        Text("\(targetPoints.count) 點")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("總長度")
                        Spacer()
                        Text(totalDistanceMeters >= 1000 ? String(format: "%.2f 公里", totalDistanceMeters / 1000.0) : "\(Int(totalDistanceMeters)) 公尺")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("預估耗時 (@\(speedInput) km/h)")
                        Spacer()
                        Text(estimatedTimeStr)
                            .foregroundColor(.secondary)
                    }
                }

                Section(header: Text("防封鎖與調整選項")) {
                    Toggle("真人碎步插點 (densifyRoute)", isOn: $enableDensify)
                    HStack {
                        Text("預估移動速度 (km/h)")
                        Spacer()
                        TextField("15.0", text: $speedInput)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                }

                Section(header: Text("匯出與分享")) {
                    Picker("GPX 格式", selection: $selectedFormat) {
                        ForEach(GpxFormat.allCases) { format in
                            Text(format.displayName).tag(format)
                        }
                    }

                    Button(action: exportAndShareSingleGpx) {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("分享 \(selectedFormat.displayName)")
                        }
                    }

                    Button(action: uploadGofile) {
                        HStack {
                            Image(systemName: "cloud.fill")
                            Text(isUploading ? "正在上傳至 Gofile..." : "上傳 Gofile 產生公開下載連結")
                        }
                    }
                    .disabled(isUploading)

                    if let url = uploadedUrl {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("公開下載短網址 (已複製至剪貼簿)：")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(url)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.blue)
                        }
                    }

                    if let err = errorMessage {
                        Text(err)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("分享路線")
            .navigationBarItems(trailing: Button("完成") { dismiss() })
        }
    }

    private func exportAndShareSingleGpx() {
        let gpxStr = RouteShareManager.generateGpx(points: targetPoints, format: selectedFormat, routeName: session.activeRouteName)
        let fileName = "\(session.activeRouteName)\(selectedFormat.suffix).gpx"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try gpxStr.write(to: tempURL, atomically: true, encoding: .utf8)
            RouteShareManager.shareFile(fileURL: tempURL)
        } catch {
            errorMessage = "寫入檔案失敗: \(error.localizedDescription)"
        }
    }

    private func uploadGofile() {
        isUploading = true
        errorMessage = nil
        let gpxStr = RouteShareManager.generateGpx(points: targetPoints, format: selectedFormat, routeName: session.activeRouteName)
        let fileName = "\(session.activeRouteName)\(selectedFormat.suffix).gpx"
        guard let data = gpxStr.data(using: .utf8) else {
            isUploading = false
            return
        }

        Task {
            do {
                let link = try await RouteShareManager.uploadToGofile(fileName: fileName, fileData: data)
                await MainActor.run {
                    self.uploadedUrl = link
                    self.isUploading = false
                    UIPasteboard.general.string = link
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "上傳失敗: \(error.localizedDescription)"
                    self.isUploading = false
                }
            }
        }
    }
}
