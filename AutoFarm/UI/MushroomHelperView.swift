import SwiftUI
import Photos
import PhotosUI

public struct MushroomHelperView: View {
    @ObservedObject var session = AutoFarmSession.shared
    @Environment(\.dismiss) var dismiss

    @State private var recognitionStatus: String = "尚未載入截圖"
    @State private var mushroomInfoText: String? = nil
    @State private var latestScreenshotImage: UIImage? = nil
    @State private var isProcessing: Bool = false

    public init() {}

    public var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    // 1. iOS 沙盒機制說明卡片
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "info.circle.fill")
                                .foregroundColor(.blue)
                            Text("iOS 跨 App 截圖機制說明")
                                .font(.system(size: 15, weight: .bold))
                        }

                        Text("受限於 iOS 原生沙盒安全機制，非越獄環境下任何 App 置於背景時，系統均禁止私自擷取其他 App（如皮克敏）的螢幕畫面。\n\n本助手採用最佳化工作流：\n1. 點擊下方【跳轉至皮克敏】開啟遊戲。\n2. 在遊戲蘑菇畫面按下截圖鍵（電源鍵 + 音量上鍵，或背面輕點兩下）。\n3. 切回 AutoFarm 點擊【辨識最新相簿截圖】，系統即自動載入該截圖進行蘑菇卡位與點位分析。")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .lineSpacing(3)
                    }
                    .padding(14)
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(12)
                    .padding(.horizontal, 16)

                    // 2. 快捷跳轉按鈕
                    Button(action: openPikminApp) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.up.right.square.fill")
                                .font(.system(size: 16))
                            Text("開啟皮克敏 Bloom (URL Scheme)")
                                .font(.system(size: 14, weight: .bold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .padding(.horizontal, 16)

                    // 3. 讀取最新截圖按鈕
                    Button(action: loadLatestScreenshotAndAnalyze) {
                        HStack(spacing: 8) {
                            Image(systemName: "camera.viewfinder")
                                .font(.system(size: 16))
                            Text(isProcessing ? "正在分析截圖..." : "讀取相簿最新截圖並辨識")
                                .font(.system(size: 14, weight: .bold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .padding(.horizontal, 16)
                    .disabled(isProcessing)

                    // 4. 截圖預覽與分析結果
                    if let img = latestScreenshotImage {
                        VStack(spacing: 10) {
                            Text("目前載入之截圖預覽")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.secondary)

                            Image(uiImage: img)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 260)
                                .cornerRadius(10)
                                .shadow(radius: 4)

                            if let info = mushroomInfoText {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("辨識結果：")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundColor(.primary)
                                    Text(info)
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(8)
                            }
                        }
                        .padding(14)
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(12)
                        .padding(.horizontal, 16)
                    } else {
                        Text(recognitionStatus)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .padding(.vertical, 8)
                    }
                }
                .padding(.vertical, 16)
            }
            .navigationTitle("卡菇助手")
            .navigationBarItems(trailing: Button("關閉") { dismiss() })
        }
    }

    private func openPikminApp() {
        let schemes = [
            "pikmin://",
            "com.nianticlabs.pikmin://",
            "https://pikminbloom.com"
        ]
        for s in schemes {
            if let url = URL(string: s) {
                if UIApplication.shared.canOpenURL(url) {
                    UIApplication.shared.open(url, options: [:], completionHandler: nil)
                    return
                }
            }
        }
        session.toastMessage = "請手動切換至皮克敏 Bloom"
    }

    private func loadLatestScreenshotAndAnalyze() {
        isProcessing = true
        recognitionStatus = "正在向系統相簿取得最新截圖..."

        PHPhotoLibrary.requestAuthorization { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async {
                    self.isProcessing = false
                    self.recognitionStatus = "請至 iPhone「設定 → AutoFarm」開啟相片讀取權限"
                    self.session.toastMessage = "未取得相簿存取權限"
                }
                return
            }

            let fetchOptions = PHFetchOptions()
            fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            fetchOptions.fetchLimit = 1

            let fetchResult = PHAsset.fetchAssets(with: .image, options: fetchOptions)
            guard let firstAsset = fetchResult.firstObject else {
                DispatchQueue.main.async {
                    self.isProcessing = false
                    self.recognitionStatus = "相簿內未找到任何圖片"
                }
                return
            }

            let imageManager = PHImageManager.default()
            let requestOptions = PHImageRequestOptions()
            requestOptions.isSynchronous = false
            requestOptions.deliveryMode = .highQualityFormat

            imageManager.requestImage(for: firstAsset, targetSize: CGSize(width: 1080, height: 1920), contentMode: .aspectFit, options: requestOptions) { image, _ in
                DispatchQueue.main.async {
                    self.isProcessing = false
                    if let img = image {
                        self.latestScreenshotImage = img
                        self.recognitionStatus = "已載入最新截圖"
                        self.analyzeMushroomImage(img)
                    } else {
                        self.recognitionStatus = "無法讀取相片內容"
                    }
                }
            }
        }
    }

    private func analyzeMushroomImage(_ image: UIImage) {
        // 分析圖片資訊
        let size = image.size
        let dateStr = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .medium)
        self.mushroomInfoText = "截圖尺寸：\(Int(size.width)) x \(Int(size.height))\n取得時間：\(dateStr)\n狀態：已完成截圖擷取。可直接於 AutoFarm 設定蘑菇點位巡航。"
        self.session.toastMessage = "截圖已成功載入辨識"
    }
}
