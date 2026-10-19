import Foundation
import UIKit
import Combine
import Photos
import UserNotifications
import AudioToolbox

public final class MushroomScanManager: NSObject, ObservableObject, PHPhotoLibraryChangeObserver {
    public static let shared = MushroomScanManager()

    @Published public var isScanning: Bool = false
    @Published public var scanSpeedKmh: Double = 800.0
    @Published public var activeRouteName: String = ""
    @Published public var detectedMushroomCount: Int = 0

    private var previousFetchResult: PHFetchResult<PHAsset>?
    private var isListeningToPhotos: Bool = false

    private override init() {
        super.init()
        requestNotificationPermission()
    }

    // MARK: - 自動跳轉皮克敏遊戲
    public static func openPikminBloom() {
        let candidateUrls = [
            "pikminbloom://",
            "https://pikminbloom.com/"
        ]

        for uStr in candidateUrls {
            if let url = URL(string: uStr) {
                if UIApplication.shared.canOpenURL(url) {
                    UIApplication.shared.open(url, options: [:], completionHandler: nil)
                    return
                }
            }
        }

        // 若無註冊 URL Scheme，嘗試直接開啟
        if let url = URL(string: "pikminbloom://") {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
    }

    // MARK: - 啟動掃菇模式
    public func startScan(name: String, points: [RouteNode], speedKmh: Double = 800.0, autoOpenGame: Bool = true) {
        guard !points.isEmpty else { return }
        self.isScanning = true
        self.scanSpeedKmh = speedKmh
        self.activeRouteName = name
        self.detectedMushroomCount = 0

        // 1. 啟動 800 km/h 巡航
        AutoFarmSession.shared.startMushroomScanRoute(name: name, basePoints: points, speedKmh: speedKmh)

        // 2. 啟動相簿即時截圖監聽 (玩家在遊戲中截圖立即自動反推座標並記錄)
        startListeningToScreenshots()

        // 3. 自動跳轉進入皮克敏遊戲
        if autoOpenGame {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                MushroomScanManager.openPikminBloom()
            }
        }
    }

    public func stopScan() {
        self.isScanning = false
        stopListeningToScreenshots()
        AutoFarmSession.shared.stopRoute()
    }

    // MARK: - 相簿新截圖監聽
    private func startListeningToScreenshots() {
        guard !isListeningToPhotos else { return }
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.fetchLimit = 1
        previousFetchResult = PHAsset.fetchAssets(with: .image, options: fetchOptions)

        PHPhotoLibrary.shared().register(self)
        isListeningToPhotos = true
    }

    private func stopListeningToScreenshots() {
        if isListeningToPhotos {
            PHPhotoLibrary.shared().unregisterChangeObserver(self)
            isListeningToPhotos = false
        }
    }

    public func photoLibraryDidChange(_ changeInstance: PHChange) {
        guard isScanning, let prev = previousFetchResult else { return }
        guard let changes = changeInstance.changeDetails(for: prev) else { return }
        let current = changes.fetchResultAfterChanges
        previousFetchResult = current

        guard let latestAsset = current.firstObject else { return }

        // 確認是否為剛剛產生的新照片 (30 秒內)
        if let date = latestAsset.creationDate, abs(date.timeIntervalSinceNow) < 30.0 {
            loadAssetImage(latestAsset) { image in
                guard let img = image else { return }
                self.processCapturedImage(img)
            }
        }
    }

    private func loadAssetImage(_ asset: PHAsset, completion: @escaping (UIImage?) -> Void) {
        let options = PHImageRequestOptions()
        options.isSynchronous = false
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = false

        PHImageManager.default().requestImage(
            for: asset,
            targetSize: CGSize(width: 1080, height: 2340),
            contentMode: .aspectFit,
            options: options
        ) { image, _ in
            completion(image)
        }
    }

    /// 分析畫面並透過航跡回推真實經緯度
    public func processCapturedImage(_ image: UIImage) {
        MushroomOcrEngine.recognize(image: image) { result in
            // 若成功辨識出蘑菇關鍵字
            let name = result.mushroomName
            if !name.isEmpty && name != "未辨識出蘑菇" {
                // 依當前 800 km/h 航向與速度，精準回推蘑菇生成時的經緯度
                let currentLat = AutoFarmSession.shared.currentLat
                let currentLng = AutoFarmSession.shared.currentLng
                let speed = AutoFarmSession.shared.speedKmh

                let backLoc = CruiseTrajectoryTracker.shared.getBackCalculatedLocation(
                    currentLat: currentLat,
                    currentLng: currentLng,
                    currentSpeedKmh: speed
                )

                if let rec = MushroomLogManager.shared.addRecord(
                    typeName: name,
                    score: 95,
                    lat: backLoc.lat,
                    lng: backLoc.lng,
                    landmark: result.landmark,
                    cropImage: image
                ) {
                    DispatchQueue.main.async {
                        self.detectedMushroomCount += 1
                        self.notifyMushroomFound(record: rec)
                    }
                }
            }
        }
    }

    private func notifyMushroomFound(record: MushroomScanRecord) {
        // 觸發震動與系統音效
        AudioServicesPlaySystemSound(1007) // SMS received chime
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)

        // 發送本地通知橫幅
        let content = UNMutableNotificationContent()
        content.title = "已鎖定蘑菇：\(record.typeName)"
        content.body = "座標：\(String(format: "%.5f", record.lat)), \(String(format: "%.5f", record.lng)) \(record.landmark.isEmpty ? "" : "(\(record.landmark))")"
        content.sound = .default

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }
}
