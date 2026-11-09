import Foundation
import CoreLocation
import Combine
import SwiftUI
import UIKit
import UserNotifications

public struct HandshakeAlertInfo: Identifiable {
    public let id = UUID()
    public let title: String
    public let message: String
    public let actionName: String

    public init(title: String, message: String, actionName: String) {
        self.title = title
        self.message = message
        self.actionName = actionName
    }
}

public final class AutoFarmSession: ObservableObject {
    public static let shared = AutoFarmSession()

    // Handshake Alert State
    @Published public var handshakeAlertInfo: HandshakeAlertInfo? = nil
    @Published public var isToastError: Bool = false

    // MARK: - Published State
    @Published public var currentLat: Double = 25.033964
    @Published public var currentLng: Double = 121.564468
    @Published public var isSimulatingLocation: Bool = false
    @Published public var isRoutePaused: Bool = true

    @Published public var activeRouteName: String = "無路線"
    @Published public var routePoints: [RouteNode] = []
    @Published public var originalBasePoints: [RouteNode] = []
    @Published public var currentRouteIndex: Int = 0
    @Published public var routeLoopTarget: Int = 0 // 0 = 無限
    @Published public var routeCurrentLoop: Int = 0
    @Published public var cooldownRemainingSec: Int = 0
    @Published public var speedKmh: Double = {
        let saved = UserDefaults.standard.double(forKey: "AutoFarm_SpeedKmh")
        return saved > 0 ? saved : 18.0
    }() {
        didSet {
            UserDefaults.standard.set(speedKmh, forKey: "AutoFarm_SpeedKmh")
        }
    }

    @Published public var cameraCenterTrigger: Int = 0
    @Published public var cameraRouteBoundsTrigger: Int = 0

    @Published public var executionMode: Int = 0 // 0: 直線, 1: 種花, 2: 果實, 3: 同心圓
    @Published public var loopMode: LoopMode = .closedLoop
    @Published public var fruitWalkDistance: Double = 80.0
    @Published public var flowerSettings: MultiFlowerSettings = MultiFlowerSettings()

    @Published public var etaString: String = "--:--"
    @Published public var toastMessage: String? = nil

    // Joystick
    @Published public var isJoystickEnabled: Bool = false
    @Published public var joystickAngle: Double = 0.0
    @Published public var joystickIntensity: Double = 0.0
    @Published public var isJoystickLocked: Bool = false

    // 是否顯示虛擬方向盤/搖桿 (使用者設定開關，預設為 true，持久化至 UserDefaults)
    @Published public var isJoystickVisible: Bool = {
        if UserDefaults.standard.object(forKey: "AutoFarm_ShowVirtualJoystick") != nil {
            return UserDefaults.standard.bool(forKey: "AutoFarm_ShowVirtualJoystick")
        }
        return true
    }() {
        didSet {
            UserDefaults.standard.set(isJoystickVisible, forKey: "AutoFarm_ShowVirtualJoystick")
        }
    }

    // 本次啟動以來是否已成功測試/驗證過通道握手
    @Published public var hasTestedHandshake: Bool = false

    // Tuning & Pairing
    @Published public var deviceIP: String = "10.7.1.1"
    @Published public var pairingFilePath: String = ""

    // Detour & Resume (方案 A: 臨時瞬移插隊記憶)
    @Published public var detourDepartureCoord: CLLocationCoordinate2D? = nil

    // Login & Auth State
    @Published public var isLoggedIn: Bool = false
    @Published public var loggedInUsername: String = ""

    private var pushFailureCount: Int = 0

    /// 供地圖與 UI 展示用的基準航點列表 (種花模式顯示花苞點，直線模式顯示航點，杜絕幾千個點)
    public var displayWaypoints: [RouteNode] {
        if !originalBasePoints.isEmpty {
            return originalBasePoints
        }
        return routePoints
    }

    /// 當前正在行進的基準航點索引 (0-based)
    public var currentDisplayIndex: Int {
        guard !routePoints.isEmpty, currentRouteIndex < routePoints.count else { return 0 }
        if executionMode == 1 { // 種花模式：取當前節點的花苞編號
            if let flowerIdx = routePoints[currentRouteIndex].flowerIndex, flowerIdx > 0 {
                return min(max(flowerIdx - 1, 0), max(displayWaypoints.count - 1, 0))
            }
        }
        if !originalBasePoints.isEmpty && routePoints.count > originalBasePoints.count {
            let ratio = Double(currentRouteIndex) / Double(routePoints.count)
            return min(Int(ratio * Double(originalBasePoints.count)), max(originalBasePoints.count - 1, 0))
        }
        return min(currentRouteIndex, max(displayWaypoints.count - 1, 0))
    }

    private var engineTimer: DispatchSourceTimer?
    private let engineQueue = DispatchQueue(label: "com.autofarm.engine.timer", qos: .userInteractive)
    private var lastTickTime: TimeInterval = 0.0
    private var lastPushTime: TimeInterval = 0.0
    private var lastUiCoordDispatchTime: TimeInterval = 0.0
    private var waitAccumulatedMs: Double = 0.0
    private var lastAutoSaveTime: TimeInterval = 0.0
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

    // Engine State: 嚴格於 engineQueue 維護連續精確座標，杜絕因主執行緒節流更新被丟棄導致的 1/4 假性降速
    private var engineLat: Double = 25.033964
    private var engineLng: Double = 121.564468
    private var engineRouteIndex: Int = 0
    private var engineCurrentLoop: Int = 0
    private var engineCooldownSec: Int = 0

    private func syncEngineCoords(lat: Double, lng: Double, index: Int? = nil, loop: Int? = nil, cooldown: Int? = nil) {
        self.engineLat = lat
        self.engineLng = lng
        if let idx = index { self.engineRouteIndex = idx }
        if let lp = loop { self.engineCurrentLoop = lp }
        if let cd = cooldown { self.engineCooldownSec = cd }
    }

    /// 發送靜音本機通知橫幅 (即使在皮克敏介面也能看見上下點切換提示)
    public func postWaypointNotification(from: Int, to: Int, total: Int, label: String = "航點") {
        let content = UNMutableNotificationContent()
        content.title = "AutoFarm 巡航控制"
        content.body = "成功切換：第 \(from) ➔ 第 \(to) \(label) (共 \(total) \(label))"
        content.sound = nil
        let request = UNNotificationRequest(
            identifier: "autofarm_waypoint_switch",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    private init() {
        self.engineLat = currentLat
        self.engineLng = currentLng

        // Load default pairing if exists
        if let defaultPairing = PairingStore.availablePairings().first {
            self.pairingFilePath = defaultPairing.path
        } else {
            self.pairingFilePath = PairingStore.shared.pairingPath
        }
        if FlowerStationManager.shared.isStationLoggedIn {
            self.isLoggedIn = true
            let name = FlowerStationManager.shared.stationDisplayName
            self.loggedInUsername = !name.isEmpty ? name : FlowerStationManager.shared.stationEmail
        } else {
            self.isLoggedIn = UserDefaults.standard.bool(forKey: "AutoFarm_IsLoggedIn")
            self.loggedInUsername = UserDefaults.standard.string(forKey: "AutoFarm_LoggedInUser") ?? ""
        }

        setupLifecycleObservers()
    }

    private func setupLifecycleObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppWillTerminate),
            name: UIApplication.willTerminateNotification,
            object: nil
        )
    }

    @objc private func handleAppDidEnterBackground() {
        autoSaveCurrentProgress()
        guard isSimulatingLocation else { return }
        startBackgroundTask()
        pushCurrentLocation()
        SilentAudioKeepAlive.shared.ensurePlaying()
    }

    @objc private func handleAppWillResignActive() {
        autoSaveCurrentProgress()
    }

    @objc private func handleAppWillTerminate() {
        autoSaveCurrentProgress()
    }

    @objc private func handleAppWillEnterForeground() {
        endBackgroundTask()
        if isSimulatingLocation {
            pushCurrentLocation()
            SilentAudioKeepAlive.shared.ensurePlaying()
        }
    }

    private func startBackgroundTask() {
        endBackgroundTask()
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "AutoFarmEngineAnchor") { [weak self] in
            self?.endBackgroundTask()
        }
    }

    private func endBackgroundTask() {
        if backgroundTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
            backgroundTaskID = .invalid
        }
    }

    public func backgroundTickKeepAlive() {
        guard isSimulatingLocation else { return }
        let now = Date().timeIntervalSinceReferenceDate
        if now - lastPushTime >= 0.8 {
            lastPushTime = now
            pushCurrentLocation()
        }
        SilentAudioKeepAlive.shared.ensurePlaying()
    }

    // MARK: - Auth
    public func login(username: String) {
        self.isLoggedIn = true
        self.loggedInUsername = username
        UserDefaults.standard.set(true, forKey: "AutoFarm_IsLoggedIn")
        UserDefaults.standard.set(username, forKey: "AutoFarm_LoggedInUser")
        showToast("登入成功，歡迎使用 AutoFarm！")
    }

    public func logout() {
        self.isLoggedIn = false
        self.loggedInUsername = ""
        UserDefaults.standard.set(false, forKey: "AutoFarm_IsLoggedIn")
        UserDefaults.standard.removeObject(forKey: "AutoFarm_LoggedInUser")
        FlowerStationManager.shared.logoutStation()
        stopRoute()
        showToast("已登出帳號")
    }

    public func deleteAccount() {
        logout()
        UserDefaults.standard.removeObject(forKey: "com.autofarm.user_auth")
        UserDefaults.standard.removeObject(forKey: "station_user_email")
        UserDefaults.standard.removeObject(forKey: "station_user_pwd")
        UserDefaults.standard.removeObject(forKey: "AutoFarm_StationDisplayName")
        UserDefaults.standard.removeObject(forKey: "AutoFarm_StationEmail")
        FlowerStationManager.shared.logoutStation()
        showToast("已刪除並清空此帳號的所有本機憑證")
    }

    // MARK: - Route Execution Controls

    /// 啟動直線巡航
    public func startLinearRoute(name: String, basePoints: [RouteNode], loops: Int, mode: LoopMode, startLoop: Int = 0, startIndex: Int = 0) {
        guard !basePoints.isEmpty else { return }
        ensureHandshakeVerified(actionName: "直線巡航") { [weak self] in
            guard let self = self else { return }
            self.originalBasePoints = basePoints
            self.routePoints = LinearPatrolEngine.prepareRouteNodes(basePoints: basePoints, mode: mode)
            self.activeRouteName = name
            self.routeLoopTarget = loops
            self.routeCurrentLoop = max(startLoop, 0)
            self.executionMode = 0
            self.loopMode = mode

            let validIndex = min(max(startIndex, 0), self.routePoints.count - 1)
            self.currentRouteIndex = validIndex
            self.currentLat = self.routePoints[validIndex].lat
            self.currentLng = self.routePoints[validIndex].lng
            self.syncEngineCoords(lat: self.routePoints[validIndex].lat, lng: self.routePoints[validIndex].lng, index: validIndex, loop: max(startLoop, 0), cooldown: 0)
            self.isRoutePaused = false
            self.cooldownRemainingSec = 0
            self.waitAccumulatedMs = 0.0

            self.pushCurrentLocation()
            self.ensureEngineRunning()
            SavedDatabaseStore.shared.addLinearRouteHistory(name: name, basePoints: basePoints, loops: loops, mode: mode)
            self.showToast("已開始路線【\(name)】")
        }
    }

    /// 啟動多花點雙圈種花
    public func startFlowerRoute(name: String, basePoints: [RouteNode], loops: Int, settings: MultiFlowerSettings, startLoop: Int = 0, startIndex: Int = 0) {
        guard !basePoints.isEmpty else { return }
        ensureHandshakeVerified(actionName: "繞圈種花") { [weak self] in
            guard let self = self else { return }
            self.originalBasePoints = basePoints
            self.flowerSettings = settings
            self.routePoints = FlowerPlantingEngine.generateMultiFlowerNodes(basePoints: basePoints, settings: settings)
            self.activeRouteName = name
            self.routeLoopTarget = loops
            self.routeCurrentLoop = max(startLoop, 0)
            self.executionMode = 1

            let validIndex = min(max(startIndex, 0), self.routePoints.count - 1)
            self.currentRouteIndex = validIndex
            self.currentLat = self.routePoints[validIndex].lat
            self.currentLng = self.routePoints[validIndex].lng
            self.syncEngineCoords(lat: self.routePoints[validIndex].lat, lng: self.routePoints[validIndex].lng, index: validIndex, loop: max(startLoop, 0), cooldown: 0)
            self.isRoutePaused = false
            self.cooldownRemainingSec = 0
            self.waitAccumulatedMs = 0.0

            self.pushCurrentLocation()
            self.ensureEngineRunning()
            SavedDatabaseStore.shared.addFlowerRouteHistory(name: name, basePoints: basePoints, loops: loops, settings: settings)
            self.showToast("已啟動繞圈種花 (\(self.routePoints.count) 點)")
        }
    }

    /// 啟動跳收果實
    public func startFruitRoute(name: String, basePoints: [RouteNode], loops: Int, walkDistance: Double = 80.0, startLoop: Int = 0, startIndex: Int = 0) {
        guard !basePoints.isEmpty else { return }
        ensureHandshakeVerified(actionName: "跳收果實") { [weak self] in
            guard let self = self else { return }
            self.originalBasePoints = basePoints
            self.fruitWalkDistance = walkDistance
            self.routePoints = FruitHarvestEngine.prepareFruitNodes(basePoints: basePoints, walkDistanceMeters: walkDistance)
            self.activeRouteName = name
            self.routeLoopTarget = loops
            self.routeCurrentLoop = max(startLoop, 0)
            self.executionMode = 2

            let validIndex = min(max(startIndex, 0), self.routePoints.count - 1)
            self.currentRouteIndex = validIndex
            self.currentLat = self.routePoints[validIndex].lat
            self.currentLng = self.routePoints[validIndex].lng
            self.syncEngineCoords(lat: self.routePoints[validIndex].lat, lng: self.routePoints[validIndex].lng, index: validIndex, loop: max(startLoop, 0), cooldown: 0)
            self.isRoutePaused = false
            self.cooldownRemainingSec = 0
            self.waitAccumulatedMs = 0.0

            self.pushCurrentLocation()
            self.ensureEngineRunning()
            SavedDatabaseStore.shared.addFruitRouteHistory(name: name, basePoints: basePoints, loops: loops, walkDistance: walkDistance)
            self.showToast("已啟動跳收果實模式")
        }
    }

    /// 啟動獨立同心圓種花
    public func startConcentricFlower(centerLat: Double, centerLng: Double, radius: Double, step: Double, mode: ConcentricMode) {
        ensureHandshakeVerified(actionName: "同心圓種花") { [weak self] in
            guard let self = self else { return }
            let nodes = FlowerPlantingEngine.generateConcentricRoute(
                centerLat: centerLat,
                centerLng: centerLng,
                targetRadiusM: radius,
                stepWidthM: step,
                mode: mode
            )
            guard !nodes.isEmpty else { return }
            self.originalBasePoints = [RouteNode(lat: centerLat, lng: centerLng, label: "花苞中心")]
            self.routePoints = nodes
            self.activeRouteName = "同心圓種花"
            self.routeLoopTarget = 0 // 無限循環
            self.routeCurrentLoop = 0
            self.executionMode = 3
            self.currentRouteIndex = 0
            self.currentLat = nodes[0].lat
            self.currentLng = nodes[0].lng
            self.syncEngineCoords(lat: nodes[0].lat, lng: nodes[0].lng, index: 0, loop: 0, cooldown: 0)
            self.isRoutePaused = false
            self.cooldownRemainingSec = 0

            self.pushCurrentLocation()
            self.ensureEngineRunning()
            SavedDatabaseStore.shared.addConcentricRouteHistory(centerLat: centerLat, centerLng: centerLng, radius: radius, step: step, mode: mode)
            self.showToast("已啟動同心圓種花 (\(nodes.count) 點，無限循環)")
        }
    }

    /// 執行指定歷史紀錄項目 (支援單點瞬移、直線循跡、繞圈種花、跳收果實、同心圓)
    public func executeHistoryItem(_ item: LocationHistoryItem) {
        switch item.type {
        case .teleport:
            teleport(to: item.latitude, lng: item.longitude, label: item.title)
        case .linearRoute:
            if let pts = item.routeNodes, !pts.isEmpty {
                startLinearRoute(name: item.title, basePoints: pts, loops: item.loops, mode: item.loopMode)
            } else {
                teleport(to: item.latitude, lng: item.longitude, label: item.title)
            }
        case .flowerRoute:
            if let pts = item.routeNodes, !pts.isEmpty {
                startFlowerRoute(name: item.title, basePoints: pts, loops: item.loops, settings: item.flowerSettings ?? MultiFlowerSettings())
            } else {
                teleport(to: item.latitude, lng: item.longitude, label: item.title)
            }
        case .fruitRoute:
            if let pts = item.routeNodes, !pts.isEmpty {
                startFruitRoute(name: item.title, basePoints: pts, loops: item.loops, walkDistance: item.fruitWalkDistance)
            } else {
                teleport(to: item.latitude, lng: item.longitude, label: item.title)
            }
        case .concentricRoute:
            startConcentricFlower(
                centerLat: item.latitude,
                centerLng: item.longitude,
                radius: item.concentricRadius,
                step: item.concentricStep,
                mode: item.concentricMode
            )
        }
    }

    /// 暫停 / 繼續切換 (方案 A: 若有臨時瞬移插隊，按繼續自動瞬移回離開點接續巡航)
    public func toggleRoutePause() {
        if self.isRoutePaused {
            ensureHandshakeVerified(actionName: "繼續巡航") { [weak self] in
                guard let self = self else { return }
                self.isRoutePaused = false
                // 如果之前有臨時瞬移插隊，瞬移回剛才離開點接續
                if let departure = self.detourDepartureCoord {
                    self.currentLat = departure.latitude
                    self.currentLng = departure.longitude
                    self.syncEngineCoords(lat: departure.latitude, lng: departure.longitude)
                    self.detourDepartureCoord = nil
                    self.pushCurrentLocation()
                    self.showToast("已返回離開點，繼續巡航路線")
                } else {
                    self.showToast("路線繼續執行")
                }
                self.ensureEngineRunning()
            }
        } else {
            self.isRoutePaused = true
            self.waitAccumulatedMs = 0.0
            self.cooldownRemainingSec = 0
            showToast("路線已暫停")
        }
    }

    /// 跳至上一航點 / 上一朵花
    public func prevRoutePoint() {
        guard !routePoints.isEmpty else { return }
        if executionMode == 1 { // 種花模式：以花苞基準點為單位切換
            let total = max(displayWaypoints.count, 1)
            let oldIdx = currentDisplayIndex
            let prevDisplayIdx = (currentDisplayIndex - 1 + total) % total
            jumpToWaypoint(index: prevDisplayIdx)
            showToast("已跳至第 \(prevDisplayIdx + 1) / \(total) 朵花")
            postWaypointNotification(from: oldIdx + 1, to: prevDisplayIdx + 1, total: total, label: "朵花")
        } else if !originalBasePoints.isEmpty && routePoints.count > originalBasePoints.count {
            let total = originalBasePoints.count
            let oldIdx = currentDisplayIndex
            let prevDisplayIdx = (currentDisplayIndex - 1 + total) % total
            jumpToWaypoint(index: prevDisplayIdx)
            showToast("已跳至第 \(prevDisplayIdx + 1) / \(total) 航點")
            postWaypointNotification(from: oldIdx + 1, to: prevDisplayIdx + 1, total: total, label: "航點")
        } else {
            let total = routePoints.count
            let oldIdx = currentRouteIndex
            self.currentRouteIndex = (self.currentRouteIndex - 1 + total) % total
            let prev = routePoints[self.currentRouteIndex]
            self.currentLat = prev.lat
            self.currentLng = prev.lng
            self.syncEngineCoords(lat: prev.lat, lng: prev.lng, index: self.currentRouteIndex, cooldown: prev.waitTimeSec)
            self.cooldownRemainingSec = prev.waitTimeSec
            self.waitAccumulatedMs = 0.0
            pushCurrentLocation(lat: prev.lat, lng: prev.lng)
            showToast("已手動跳至第 \(self.currentRouteIndex + 1) 點")
            postWaypointNotification(from: oldIdx + 1, to: self.currentRouteIndex + 1, total: total, label: "航點")
        }
    }

    /// 跳至下一航點 / 下一朵花
    public func nextRoutePoint() {
        guard !routePoints.isEmpty else { return }
        if executionMode == 1 { // 種花模式：以花苞基準點為單位切換
            let total = max(displayWaypoints.count, 1)
            let oldIdx = currentDisplayIndex
            let nextDisplayIdx = (currentDisplayIndex + 1) % total
            jumpToWaypoint(index: nextDisplayIdx)
            showToast("已跳至第 \(nextDisplayIdx + 1) / \(total) 朵花")
            postWaypointNotification(from: oldIdx + 1, to: nextDisplayIdx + 1, total: total, label: "朵花")
        } else if !originalBasePoints.isEmpty && routePoints.count > originalBasePoints.count {
            let total = originalBasePoints.count
            let oldIdx = currentDisplayIndex
            let nextDisplayIdx = (currentDisplayIndex + 1) % total
            jumpToWaypoint(index: nextDisplayIdx)
            showToast("已跳至第 \(nextDisplayIdx + 1) / \(total) 航點")
            postWaypointNotification(from: oldIdx + 1, to: nextDisplayIdx + 1, total: total, label: "航點")
        } else {
            let total = routePoints.count
            let oldIdx = currentRouteIndex
            self.currentRouteIndex = (self.currentRouteIndex + 1) % total
            let next = routePoints[self.currentRouteIndex]
            self.currentLat = next.lat
            self.currentLng = next.lng
            self.syncEngineCoords(lat: next.lat, lng: next.lng, index: self.currentRouteIndex, cooldown: next.waitTimeSec)
            self.cooldownRemainingSec = next.waitTimeSec
            self.waitAccumulatedMs = 0.0
            pushCurrentLocation(lat: next.lat, lng: next.lng)
            showToast("已手動跳至第 \(self.currentRouteIndex + 1) 點")
            postWaypointNotification(from: oldIdx + 1, to: self.currentRouteIndex + 1, total: total, label: "航點")
        }
    }

    /// 調整巡航速度 (+ / - delta)
    public func adjustSpeed(by delta: Double) {
        let newSpeed = max(1.0, min(100.0, speedKmh + delta))
        self.speedKmh = newSpeed
        showToast("巡航速度已調整為 \(String(format: "%.1f", newSpeed)) km/h")
    }

    /// 切換暫停與繼續
    public func togglePauseResume() {
        toggleRoutePause()
    }

    /// 直接輸入點位數字跳點 (1-indexed)
    public func jumpToPoint(displayIndex: Int) {
        jumpToWaypoint(index: displayIndex - 1)
    }

    /// 跳轉至指定基準航點開始運行 (點擊數字球時觸發)
    public func jumpToWaypoint(index: Int) {
        ensureHandshakeVerified(actionName: "跳點巡航") { [weak self] in
            guard let self = self else { return }
            let validIdx = min(max(index, 0), max(self.displayWaypoints.count - 1, 0))
            var targetLat = self.currentLat
            var targetLng = self.currentLng
            var targetNodeIdx = self.currentRouteIndex

            if self.executionMode == 1 { // 種花模式：尋找對應 flowerIndex 的第一個節點
                let targetFlowerNum = validIdx + 1
                if let nodeIdx = self.routePoints.firstIndex(where: { $0.flowerIndex == targetFlowerNum }) {
                    targetNodeIdx = nodeIdx
                    targetLat = self.routePoints[nodeIdx].lat
                    targetLng = self.routePoints[nodeIdx].lng
                } else if validIdx < self.displayWaypoints.count {
                    let node = self.displayWaypoints[validIdx]
                    targetLat = node.lat
                    targetLng = node.lng
                }
            } else if !self.originalBasePoints.isEmpty && self.routePoints.count > self.originalBasePoints.count {
                let ratio = Double(validIdx) / Double(self.originalBasePoints.count)
                let nodeIdx = min(Int(ratio * Double(self.routePoints.count)), max(self.routePoints.count - 1, 0))
                targetNodeIdx = nodeIdx
                targetLat = self.routePoints[nodeIdx].lat
                targetLng = self.routePoints[nodeIdx].lng
            } else if validIdx < self.routePoints.count {
                targetNodeIdx = validIdx
                targetLat = self.routePoints[validIdx].lat
                targetLng = self.routePoints[validIdx].lng
            }

            // 原子化同步至引擎背景線程，杜絕任何時間差與舊位置覆蓋
            self.engineQueue.sync {
                self.syncEngineCoords(lat: targetLat, lng: targetLng, index: targetNodeIdx, cooldown: 0)
                self.waitAccumulatedMs = 0.0
                self.cooldownRemainingSec = 0
                self.lastTickTime = Date().timeIntervalSinceReferenceDate
            }

            self.currentLat = targetLat
            self.currentLng = targetLng
            self.currentRouteIndex = targetNodeIdx
            self.cooldownRemainingSec = 0
            self.waitAccumulatedMs = 0.0
            self.isRoutePaused = false // 從此點開始運行，保持自動巡航
            self.pushCurrentLocation(lat: targetLat, lng: targetLng)
            self.ensureEngineRunning()
            self.autoSaveCurrentProgress()
            self.showToast("已從第 \(validIdx + 1) 個航點開始巡航")
        }
    }

    /// 刪除指定索引的航點 (地圖點擊數字球刪除點位)
    public func removeWaypoint(at index: Int) {
        guard index >= 0 else { return }
        if !originalBasePoints.isEmpty && index < originalBasePoints.count {
            let removed = originalBasePoints.remove(at: index)
            // 重新準備路線點
            if executionMode == 0 {
                self.routePoints = LinearPatrolEngine.prepareRouteNodes(basePoints: originalBasePoints, mode: loopMode)
            } else if executionMode == 1 {
                self.routePoints = FlowerPlantingEngine.generateMultiFlowerNodes(basePoints: originalBasePoints, settings: flowerSettings)
            } else if executionMode == 2 {
                self.routePoints = FruitHarvestEngine.prepareFruitNodes(basePoints: originalBasePoints, walkDistanceMeters: fruitWalkDistance)
            }
            if currentRouteIndex >= routePoints.count {
                currentRouteIndex = max(routePoints.count - 1, 0)
            }
            autoSaveCurrentProgress()
            self.cameraRouteBoundsTrigger += 1
            showToast("已刪除航點【\(removed.label ?? "點位 \(index + 1)")】")
        } else if index < routePoints.count {
            let removed = routePoints.remove(at: index)
            if currentRouteIndex >= routePoints.count {
                currentRouteIndex = max(routePoints.count - 1, 0)
            }
            autoSaveCurrentProgress()
            self.cameraRouteBoundsTrigger += 1
            showToast("已刪除第 \(index + 1) 個航點")
        }
    }

    /// 自動即時保存當前巡航進度快照 (防止 App 意外退出、閃退遺失最新進度)
    public func autoSaveCurrentProgress() {
        guard !routePoints.isEmpty, !activeRouteName.isEmpty, activeRouteName != "無路線" else { return }
        let progress = RouteProgress(
            routeName: activeRouteName,
            currentLoop: routeCurrentLoop,
            loopTarget: routeLoopTarget,
            currentRouteIndex: currentRouteIndex,
            totalPoints: originalBasePoints.isEmpty ? routePoints.count : originalBasePoints.count,
            savedTimestamp: Int64(Date().timeIntervalSince1970 * 1000),
            routePoints: routePoints,
            basePoints: originalBasePoints,
            executionMode: executionMode,
            fruitWalkDistance: fruitWalkDistance,
            interruptedLat: engineLat != 0 ? engineLat : currentLat,
            interruptedLng: engineLng != 0 ? engineLng : currentLng
        )
        RouteProgressStore.saveProgress(progress)
    }

    /// 平滑移動地圖相機至當前虛擬定位
    public func centerCameraOnCurrentLocation() {
        self.cameraCenterTrigger += 1
        showToast("視角已置中至目前定位")
    }

    /// 平滑縮放地圖相機至完整路線全覽
    public func fitCameraToRouteBounds() {
        self.cameraRouteBoundsTrigger += 1
        showToast("視角已縮放至路線全覽")
    }

    /// 定位到路線幾何中心 (算術平均中心，點擊自動暫停路線並瞬移)
    public func centerOnRoute() {
        let pts = !originalBasePoints.isEmpty ? originalBasePoints : routePoints
        guard let center = EngineMath.calculateAverageCenter(points: pts) else {
            showToast("當前無有效路線點位")
            return
        }

        ensureHandshakeVerified(actionName: "路線幾何中心") { [weak self] in
            guard let self = self else { return }
            // 1. 自動暫停路線
            if !self.isRoutePaused {
                self.isRoutePaused = true
            }

            // 2. 瞬移至幾何中心點
            self.currentLat = center.lat
            self.currentLng = center.lng
            self.syncEngineCoords(lat: center.lat, lng: center.lng)
            self.pushCurrentLocation()
            self.showToast("已定位至【\(self.activeRouteName)】幾何中心 (已暫停路線)")
        }
    }

    /// 暫存路徑進度
    public func saveProgress() {
        guard !routePoints.isEmpty else {
            showToast("當前無運行中路線")
            return
        }
        let progress = RouteProgress(
            routeName: activeRouteName.isEmpty ? "自訂路線" : activeRouteName,
            currentLoop: routeCurrentLoop,
            loopTarget: routeLoopTarget,
            currentRouteIndex: currentRouteIndex,
            totalPoints: routePoints.count,
            savedTimestamp: Int64(Date().timeIntervalSince1970 * 1000),
            routePoints: routePoints,
            basePoints: originalBasePoints,
            executionMode: executionMode,
            fruitWalkDistance: fruitWalkDistance,
            interruptedLat: engineLat != 0 ? engineLat : currentLat,
            interruptedLng: engineLng != 0 ? engineLng : currentLng
        )
        RouteProgressStore.saveProgress(progress)
        showToast("已暫存【\(progress.routeName)】進度：第 \(progress.currentLoop + 1) 圈 第 \(progress.currentRouteIndex)/\(progress.totalPoints) 點")
        stopRoute()
    }

    /// 恢復暫存進度
    public func resumeProgress(_ progress: RouteProgress) {
        ensureHandshakeVerified(actionName: "接續進度") { [weak self] in
            guard let self = self else { return }
            RouteProgressStore.clearProgress(for: progress.routeName)
            RouteProgressStore.clearAll()
            self.originalBasePoints = progress.basePoints ?? []
            self.routePoints = progress.routePoints
            self.activeRouteName = progress.routeName
            self.routeLoopTarget = progress.loopTarget
            self.routeCurrentLoop = progress.currentLoop
            self.executionMode = progress.executionMode
            self.fruitWalkDistance = progress.fruitWalkDistance

            let validIndex = min(max(progress.currentRouteIndex, 0), max(self.routePoints.count - 1, 0))
            self.currentRouteIndex = validIndex

            // 優先恢復中斷時精確座標，若無則降級至目標航點座標
            let resumeLat = progress.interruptedLat ?? (self.routePoints.indices.contains(validIndex) ? self.routePoints[validIndex].lat : self.currentLat)
            let resumeLng = progress.interruptedLng ?? (self.routePoints.indices.contains(validIndex) ? self.routePoints[validIndex].lng : self.currentLng)

            self.engineQueue.sync {
                self.syncEngineCoords(lat: resumeLat, lng: resumeLng, index: validIndex, loop: progress.currentLoop, cooldown: 0)
                self.waitAccumulatedMs = 0.0
                self.cooldownRemainingSec = 0
                self.lastTickTime = Date().timeIntervalSinceReferenceDate
            }

            self.currentLat = resumeLat
            self.currentLng = resumeLng
            self.isRoutePaused = false
            self.cooldownRemainingSec = 0
            self.waitAccumulatedMs = 0.0

            self.pushCurrentLocation(lat: resumeLat, lng: resumeLng)
            self.ensureEngineRunning()
            self.showToast("已接續【\(progress.routeName)】中斷處進度 (第 \(progress.currentLoop + 1) 圈)")
        }
    }

    /// 停止路線 (僅停止自動行進，不解除虛擬定位，角色維持在當前座標)
    public func stopRoute() {
        // 檢查是否處於未開花卡位狀態，主動詢問釋放花田
        if let card = FlowerStationManager.shared.activeCard, !card.isCountdownStarted {
            DispatchQueue.main.async {
                FlowerStationManager.shared.spotToRelease = card
                FlowerStationManager.shared.shouldPromptSpotRelease = true
            }
        }

        self.routePoints = []
        self.originalBasePoints = []
        self.currentRouteIndex = 0
        self.isRoutePaused = true
        self.activeRouteName = "無路線"
        self.cooldownRemainingSec = 0
        self.waitAccumulatedMs = 0.0
        self.etaString = "--:--"
        self.detourDepartureCoord = nil
        VolumeButtonManager.shared.restoreExactVolumeOnRouteStop()
        showToast("已停止路線 (維持當前虛擬位置)")
    }

    /// 停止虛擬定位模擬 (徹底停止 DVT，重置 locationd，整機還原真實 GPS 並自動置中真實位置)
    public func stopMocking() {
        stopRoute()
        engineTimer?.cancel()
        engineTimer = nil
        _ = LocationEngine.clear(pairingPath: pairingFilePath, deviceIP: deviceIP)
        SilentAudioKeepAlive.shared.stop()
        BackgroundKeepAlive.shared.stop()
        endBackgroundTask()
        self.isSimulatingLocation = false
        self.hasTestedHandshake = false
        self.isRoutePaused = true

        RealLocationWatcher.shared.requestRealLocation { [weak self] coord in
            guard let self = self else { return }
            self.currentLat = coord.latitude
            self.currentLng = coord.longitude
            self.syncEngineCoords(lat: coord.latitude, lng: coord.longitude)
            self.centerCameraOnCurrentLocation()
        }

        showToast("已停止虛擬定位，回到現實座標！")
    }

    /// 手動瞬移至指定座標 (方案 A: 支援掛起插隊，自動記錄中斷點與瞬移歷史，按繼續自動返回接續)
    public func teleport(to coord: CLLocationCoordinate2D, label: String = "") {
        teleport(to: coord.latitude, lng: coord.longitude, label: label)
    }

    public func teleport(to lat: Double, lng: Double, label: String = "") {
        ensureHandshakeVerified(actionName: "瞬移定位") { [weak self] in
            guard let self = self else { return }
            // 若當前有排程路線且尚未記錄過插隊中斷點
            if !self.routePoints.isEmpty {
                if self.detourDepartureCoord == nil {
                    self.detourDepartureCoord = CLLocationCoordinate2D(latitude: self.currentLat, longitude: self.currentLng)
                }
                self.isRoutePaused = true
            } else if !self.isRoutePaused {
                self.isRoutePaused = true
            }

            self.engineQueue.sync {
                self.syncEngineCoords(lat: lat, lng: lng)
                self.waitAccumulatedMs = 0.0
            }
            self.cooldownRemainingSec = 0
            self.currentLat = lat
            self.currentLng = lng
            self.lastPushTime = Date().timeIntervalSinceReferenceDate
            self.pushCurrentLocation(lat: lat, lng: lng)
            self.ensureEngineRunning()

            let pointLabel = label.isEmpty ? "自訂座標" : label
            SavedDatabaseStore.shared.addTeleportHistory(lat: lat, lng: lng, label: pointLabel)

            if self.detourDepartureCoord != nil {
                self.showToast("已瞬移至【\(pointLabel)】(路線已暫停，按繼續自動返回原位接續)")
            } else {
                self.showToast("已瞬移至 \(String(format: "%.5f", lat)), \(String(format: "%.5f", lng))")
            }
        }
    }

    /// 從任意包含座標的文字中自動萃取有效經緯度 (自動過濾中文、空格、網址等雜訊，支援經緯度自動判斷)
    public static func extractCoordinates(from text: String) -> (lat: Double, lng: Double)? {
        let pattern = "(-?\\d{1,3}\\.\\d+)[^0-9.-]+(-?\\d{1,3}\\.\\d+)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let nsString = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))

        for match in matches {
            if match.numberOfRanges >= 3 {
                let s1 = nsString.substring(with: match.range(at: 1))
                let s2 = nsString.substring(with: match.range(at: 2))
                if let v1 = Double(s1), let v2 = Double(s2) {
                    if abs(v1) <= 90.0 && abs(v2) <= 180.0 {
                        // 標準 lat, lng
                        return (v1, v2)
                    } else if abs(v1) <= 180.0 && abs(v2) <= 90.0 {
                        // 顛倒輸入 lng, lat
                        return (v2, v1)
                    }
                }
            }
        }
        return nil
    }

    // MARK: - Low-Level Loop & DVT Push

    private func ensureEngineRunning() {
        SilentAudioKeepAlive.shared.start()
        BackgroundKeepAlive.shared.start()

        if engineTimer == nil {
            lastTickTime = Date().timeIntervalSinceReferenceDate
            let timer = DispatchSource.makeTimerSource(flags: .strict, queue: engineQueue)
            timer.schedule(deadline: .now(), repeating: .milliseconds(100), leeway: .milliseconds(10))
            timer.setEventHandler { [weak self] in
                self?.engineTick()
            }
            timer.resume()
            self.engineTimer = timer
        }
    }

    private func engineTick() {
        let now = Date().timeIntervalSinceReferenceDate
        let deltaSec = now - lastTickTime
        lastTickTime = now

        var isMoving = false
        var nextLat = engineLat
        var nextLng = engineLng
        var nextCooldown = engineCooldownSec
        var nextIndex = engineRouteIndex
        var nextLoop = engineCurrentLoop
        var shouldPause = isRoutePaused
        var updatedWaitAccumMs = waitAccumulatedMs

        let stepDistMeters = (speedKmh / 3.6) * deltaSec

        // 1. 處理手動虛擬方向盤
        if joystickIntensity > 0 {
            let moveDist = stepDistMeters * joystickIntensity
            let dest = EngineMath.moveLocation(lat: nextLat, lng: nextLng, distanceMeters: moveDist, bearingDegrees: joystickAngle)
            nextLat = dest.lat
            nextLng = dest.lng
            isMoving = true
        }
        // 2. 處理自動路線循跡
        else if !routePoints.isEmpty && !isRoutePaused {
            if nextIndex >= routePoints.count {
                nextIndex = max(0, routePoints.count - 1)
                shouldPause = true
            } else {
                let target = routePoints[nextIndex]
                if target.lapIndex == 2 {
                    FlowerStationManager.shared.triggerLoop2Countdown()
                }

                if target.isTeleport {
                    nextLat = target.lat
                    nextLng = target.lng
                    let targetWaitMs = Double(target.waitTimeSec * 1000)

                    if targetWaitMs > 0 && updatedWaitAccumMs < targetWaitMs {
                        let remaining = Int(ceil((targetWaitMs - updatedWaitAccumMs) / 1000.0))
                        nextCooldown = max(remaining, 1)
                        updatedWaitAccumMs += (deltaSec * 1000.0)
                    } else {
                        nextCooldown = 0
                        updatedWaitAccumMs = 0.0
                        nextIndex += 1
                        if nextIndex >= routePoints.count {
                            let shouldLoop = (routeLoopTarget == 0) || (nextLoop < routeLoopTarget - 1)
                            if shouldLoop {
                                nextLoop += 1
                                nextIndex = 0
                            } else {
                                shouldPause = true
                            }
                        }
                    }
                } else {
                    let distToTarget = EngineMath.getDistance(lat1: nextLat, lon1: nextLng, lat2: target.lat, lon2: target.lng)

                    if distToTarget <= stepDistMeters {
                        nextLat = target.lat
                        nextLng = target.lng
                        let targetWaitMs = Double(target.waitTimeSec * 1000)

                        if targetWaitMs > 0 && updatedWaitAccumMs < targetWaitMs {
                            let remaining = Int(ceil((targetWaitMs - updatedWaitAccumMs) / 1000.0))
                            nextCooldown = max(remaining, 1)
                            updatedWaitAccumMs += (deltaSec * 1000.0)
                        } else {
                            nextCooldown = 0
                            updatedWaitAccumMs = 0.0
                            nextIndex += 1
                            if nextIndex >= routePoints.count {
                                let shouldLoop = (routeLoopTarget == 0) || (nextLoop < routeLoopTarget - 1)
                                if shouldLoop {
                                    nextLoop += 1
                                    nextIndex = 0
                                    if nextLoop == 1 {
                                        FlowerStationManager.shared.triggerLoop2Countdown()
                                    }
                                } else {
                                    shouldPause = true
                                }
                            }
                        }
                    } else {
                        nextCooldown = 0
                        let bearing = EngineMath.getBearing(lat1: nextLat, lon1: nextLng, lat2: target.lat, lon2: target.lng)
                        let dest = EngineMath.moveLocation(lat: nextLat, lng: nextLng, distanceMeters: stepDistMeters, bearingDegrees: bearing)
                        nextLat = dest.lat
                        nextLng = dest.lng
                        isMoving = true
                    }
                }
            }
        }

        self.engineLat = nextLat
        self.engineLng = nextLng
        self.engineRouteIndex = nextIndex
        self.engineCurrentLoop = nextLoop
        self.engineCooldownSec = nextCooldown
        self.waitAccumulatedMs = updatedWaitAccumMs

        // 節流主執行緒 @Published 派發頻率至 2.5Hz (或在點位/圈數變化時即時派發)，杜絕每 100ms 觸發整頁重繪導致鍵盤輸入卡頓
        let shouldUpdateUiCoords = (now - lastUiCoordDispatchTime >= 0.4) || (self.currentRouteIndex != nextIndex) || (self.routeCurrentLoop != nextLoop)
        if shouldUpdateUiCoords {
            lastUiCoordDispatchTime = now
            DispatchQueue.main.async {
                // 如果此時已經暫停且沒有在手動搖桿移動，杜絕用舊 tick 運算結果覆蓋當前瞬移的新座標
                if self.isRoutePaused && !isMoving {
                    return
                }
                if self.currentLat != nextLat { self.currentLat = nextLat }
                if self.currentLng != nextLng { self.currentLng = nextLng }
                if self.cooldownRemainingSec != nextCooldown { self.cooldownRemainingSec = nextCooldown }
                if self.currentRouteIndex != nextIndex { self.currentRouteIndex = nextIndex }
                if self.routeCurrentLoop != nextLoop { self.routeCurrentLoop = nextLoop }
                if self.isRoutePaused != shouldPause {
                    self.isRoutePaused = shouldPause
                }
            }
        }

        if isMoving {
            lastPushTime = now
            pushCurrentLocation(lat: nextLat, lng: nextLng)
        } else if isSimulatingLocation {
            // 靜態錨定心跳 (Stationary Anchor Heartbeat)：每 1 秒重新向 locationd 注入當前座標
            if now - lastPushTime >= 1.0 {
                lastPushTime = now
                pushCurrentLocation(lat: self.engineLat, lng: self.engineLng)
            }
        }

        // 定期自動保存最新巡航進度快照 (每 1.5 秒自動快照，杜絕使用者隨時滑掉 App 或閃退丟失中間步進)
        if !routePoints.isEmpty && !isRoutePaused && (now - lastAutoSaveTime >= 1.5) {
            lastAutoSaveTime = now
            DispatchQueue.main.async { [weak self] in
                self?.autoSaveCurrentProgress()
            }
        }
    }

    private func advanceToNextWaypoint() {
        self.currentRouteIndex += 1
        autoSaveCurrentProgress()
        if self.currentRouteIndex >= self.routePoints.count {
            let shouldLoop = (self.routeLoopTarget == 0) || (self.routeCurrentLoop < self.routeLoopTarget - 1)
            if shouldLoop {
                self.routeCurrentLoop += 1
                if self.routeCurrentLoop == 1 {
                    FlowerStationManager.shared.triggerLoop2Countdown()
                }
                if self.executionMode == 2 { // 果實循環
                    if let first = self.routePoints.first {
                        let cdSec = EngineMath.calculateCooldownSeconds(distanceMeters: EngineMath.getDistance(lat1: currentLat, lon1: currentLng, lat2: first.lat, lon2: first.lng))
                        self.routePoints[0].waitTimeSec = cdSec
                        self.routePoints[0].isTeleport = true
                        self.currentRouteIndex = 0
                        self.currentLat = first.lat
                        self.currentLng = first.lng
                        self.syncEngineCoords(lat: first.lat, lng: first.lng, index: 0, loop: self.routeCurrentLoop, cooldown: cdSec)
                    }
                } else if self.executionMode == 0 && self.loopMode == .teleportToStart { // 直線跳回起點
                    self.currentRouteIndex = 1
                    if let first = self.routePoints.first {
                        self.currentLat = first.lat
                        self.currentLng = first.lng
                        self.syncEngineCoords(lat: first.lat, lng: first.lng, index: 1, loop: self.routeCurrentLoop, cooldown: 0)
                    }
                } else {
                    self.currentRouteIndex = 0
                    if let first = self.routePoints.first {
                        self.currentLat = first.lat
                        self.currentLng = first.lng
                        self.syncEngineCoords(lat: first.lat, lng: first.lng, index: 0, loop: self.routeCurrentLoop, cooldown: 0)
                    }
                }
                self.waitAccumulatedMs = 0.0
                autoSaveCurrentProgress()
                showToast("開始第 \(self.routeCurrentLoop + 1) 圈")
            } else {
                self.isRoutePaused = true
                RouteProgressStore.clearProgress(for: self.activeRouteName)
                showToast("已完成所有目標圈數！")
            }
        }
    }

    private func pushCurrentLocation(lat: Double? = nil, lng: Double? = nil) {
        let pPath = pairingFilePath.isEmpty ? PairingStore.shared.pairingPath : pairingFilePath
        let targetLat = lat ?? currentLat
        let targetLng = lng ?? currentLng
        let devIP = deviceIP

        DispatchQueue.global(qos: .userInitiated).async {
            let result = LocationEngine.set(
                latitude: targetLat,
                longitude: targetLng,
                pairingPath: pPath,
                deviceIP: devIP
            )
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self.pushFailureCount = 0
                    if !self.hasTestedHandshake {
                        self.hasTestedHandshake = true
                    }
                    if !self.isSimulatingLocation {
                        self.isSimulatingLocation = true
                    }
                case .failure(let err):
                    self.pushFailureCount += 1
                    if self.pushFailureCount == 15 {
                        if self.isSimulatingLocation {
                            self.isSimulatingLocation = false
                        }
                        self.showToast("通道暫時斷開，正在重新連線...")
                        print("[AutoFarmSession] LocationEngine error: \(err.localizedDescription)")
                    }
                }
            }
        }
    }

    /// 檢查通道握手狀態。若尚未握手過，嘗試智慧自動預檢；若成功則執行 action，失敗則提示使用者
    public func ensureHandshakeVerified(actionName: String = "定位", action: @escaping () -> Void) {
        if hasTestedHandshake {
            action()
            return
        }

        showToast("正在進行通道握手預檢...")
        let pPath = pairingFilePath.isEmpty ? PairingStore.shared.pairingPath : pairingFilePath
        let targetLat = currentLat
        let targetLng = currentLng
        let devIP = deviceIP

        DispatchQueue.global(qos: .userInitiated).async {
            let result = LocationEngine.set(
                latitude: targetLat,
                longitude: targetLng,
                pairingPath: pPath,
                deviceIP: devIP
            )
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self.hasTestedHandshake = true
                    self.isSimulatingLocation = true
                    self.showToast("通道握手成功，已建立定位連線！")
                    action()
                case .failure(let err):
                    self.hasTestedHandshake = false
                    self.isSimulatingLocation = false
                    let detailed = LocationEngine.lastDetailedError
                    let reason = detailed.isEmpty ? err.localizedDescription : detailed
                    self.showToast("⚠️ 通道尚未握手或連線失敗！", isError: true)

                    let alertMsg = """
在執行【\(actionName)】前檢測到調試通道尚未建立連線。

可能原因與排查方式：
1. 請確認 LocalDevVPN (10.7.1.1) 是否已連線。
2. 4G 免 Wi-Fi SOP：請下拉手機控制中心先暫時關閉「行動數據」，在 Wi-Fi 下至設定中點擊【測試通道握手】，成功後再開回行動數據。
3. 請至「設定」確認已載入有效的 RPPairing 配對憑證。

診斷資訊：
\(reason)
"""
                    self.handshakeAlertInfo = HandshakeAlertInfo(
                        title: "⚠️ 通道尚未握手 / 連線失敗",
                        message: alertMsg,
                        actionName: actionName
                    )
                    print("[AutoFarmSession] Handshake failed before \(actionName): \(reason)")
                }
            }
        }
    }

    /// 握手並準備連線 (用於在 4G/Wi-Fi 下預先驗證通道)
    public func prepareConnection() {
        showToast("正在建立調試通道握手...")
        let pPath = pairingFilePath.isEmpty ? PairingStore.shared.pairingPath : pairingFilePath
        let targetLat = currentLat
        let targetLng = currentLng
        let devIP = deviceIP

        DispatchQueue.global(qos: .userInitiated).async {
            let result = LocationEngine.set(
                latitude: targetLat,
                longitude: targetLng,
                pairingPath: pPath,
                deviceIP: devIP
            )
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self.hasTestedHandshake = true
                    self.isSimulatingLocation = true
                    self.lastPushTime = Date().timeIntervalSinceReferenceDate
                    self.ensureEngineRunning()
                    self.showToast("通道握手成功！可開回行動數據開始巡航")
                case .failure(let err):
                    self.hasTestedHandshake = false
                    self.isSimulatingLocation = false
                    let detailed = LocationEngine.lastDetailedError
                    let reason = detailed.isEmpty ? err.localizedDescription : detailed
                    self.showToast("連線未就緒: \(reason)", isError: true)
                }
            }
        }
    }

    public func showToast(_ msg: String, isError: Bool = false) {
        DispatchQueue.main.async {
            self.toastMessage = msg
            self.isToastError = isError
            let duration = isError ? 4.0 : 2.5
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                if self.toastMessage == msg {
                    self.toastMessage = nil
                    self.isToastError = false
                }
            }
        }
    }
}

// MARK: - 真實硬體 GPS 監聽器 (用於還原真實定位時立即校準視角)
public final class RealLocationWatcher: NSObject, CLLocationManagerDelegate {
    public static let shared = RealLocationWatcher()
    private let manager = CLLocationManager()
    private var completion: ((CLLocationCoordinate2D) -> Void)?

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    public func requestRealLocation(completion: @escaping (CLLocationCoordinate2D) -> Void) {
        self.completion = completion
        manager.requestWhenInUseAuthorization()
        manager.requestLocation()
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        completion?(loc.coordinate)
        completion = nil
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        completion = nil
    }
}
