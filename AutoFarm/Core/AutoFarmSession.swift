import Foundation
import CoreLocation
import Combine
import SwiftUI

public final class AutoFarmSession: ObservableObject {
    public static let shared = AutoFarmSession()

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
    @Published public var speedKmh: Double = 18.0

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

    private var timer: Timer?
    private var lastTickTime: TimeInterval = 0.0
    private var waitAccumulatedMs: Double = 0.0

    private init() {
        // Load default pairing if exists
        if let defaultPairing = PairingStore.availablePairings().first {
            self.pairingFilePath = defaultPairing.path
        } else {
            self.pairingFilePath = PairingStore.shared.pairingPath
        }
        self.isLoggedIn = UserDefaults.standard.bool(forKey: "AutoFarm_IsLoggedIn")
        self.loggedInUsername = UserDefaults.standard.string(forKey: "AutoFarm_LoggedInUser") ?? ""
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
        stopRoute()
        showToast("已登出帳號")
    }

    // MARK: - Route Execution Controls

    /// 啟動直線巡航
    public func startLinearRoute(name: String, basePoints: [RouteNode], loops: Int, mode: LoopMode, startLoop: Int = 0, startIndex: Int = 0) {
        guard !basePoints.isEmpty else { return }
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
        self.isRoutePaused = false
        self.cooldownRemainingSec = 0
        self.waitAccumulatedMs = 0.0

        pushCurrentLocation()
        ensureEngineRunning()
        SavedDatabaseStore.shared.addLinearRouteHistory(name: name, basePoints: basePoints, loops: loops, mode: mode)
        showToast("已開始路線【\(name)】")
    }

    /// 啟動多花點雙圈種花
    public func startFlowerRoute(name: String, basePoints: [RouteNode], loops: Int, settings: MultiFlowerSettings, startLoop: Int = 0, startIndex: Int = 0) {
        guard !basePoints.isEmpty else { return }
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
        self.isRoutePaused = false
        self.cooldownRemainingSec = 0
        self.waitAccumulatedMs = 0.0

        pushCurrentLocation()
        ensureEngineRunning()
        SavedDatabaseStore.shared.addFlowerRouteHistory(name: name, basePoints: basePoints, loops: loops, settings: settings)
        showToast("已啟動繞圈種花 (\(self.routePoints.count) 點)")
    }

    /// 啟動跳收果實
    public func startFruitRoute(name: String, basePoints: [RouteNode], loops: Int, walkDistance: Double = 80.0, startLoop: Int = 0, startIndex: Int = 0) {
        guard !basePoints.isEmpty else { return }
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
        self.isRoutePaused = false
        self.cooldownRemainingSec = 0
        self.waitAccumulatedMs = 0.0

        pushCurrentLocation()
        ensureEngineRunning()
        SavedDatabaseStore.shared.addFruitRouteHistory(name: name, basePoints: basePoints, loops: loops, walkDistance: walkDistance)
        showToast("已啟動跳收果實模式")
    }

    /// 啟動獨立同心圓種花
    public func startConcentricFlower(centerLat: Double, centerLng: Double, radius: Double, step: Double, mode: ConcentricMode) {
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
        self.isRoutePaused = false
        self.cooldownRemainingSec = 0

        pushCurrentLocation()
        ensureEngineRunning()
        SavedDatabaseStore.shared.addConcentricRouteHistory(centerLat: centerLat, centerLng: centerLng, radius: radius, step: step, mode: mode)
        showToast("已啟動同心圓種花 (\(nodes.count) 點，無限循環)")
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
        self.isRoutePaused.toggle()
        if self.isRoutePaused {
            self.waitAccumulatedMs = 0.0
            self.cooldownRemainingSec = 0
            showToast("路線已暫停")
        } else {
            // 如果之前有臨時瞬移插隊，瞬移回剛才離開點接續
            if let departure = detourDepartureCoord {
                self.currentLat = departure.latitude
                self.currentLng = departure.longitude
                self.detourDepartureCoord = nil
                pushCurrentLocation()
                showToast("已返回離開點，繼續巡航路線")
            } else {
                showToast("路線繼續執行")
            }
            ensureEngineRunning()
        }
    }

    /// 跳至上一航點
    public func prevRoutePoint() {
        guard !routePoints.isEmpty else { return }
        self.currentRouteIndex = (self.currentRouteIndex - 1 + routePoints.count) % routePoints.count
        let prev = routePoints[self.currentRouteIndex]
        self.currentLat = prev.lat
        self.currentLng = prev.lng
        self.cooldownRemainingSec = prev.waitTimeSec
        self.waitAccumulatedMs = 0.0
        pushCurrentLocation()
        showToast("已手動跳至第 \(self.currentRouteIndex + 1) 點")
    }

    /// 跳至下一航點
    public func nextRoutePoint() {
        guard !routePoints.isEmpty else { return }
        self.currentRouteIndex = (self.currentRouteIndex + 1) % routePoints.count
        let next = routePoints[self.currentRouteIndex]
        self.currentLat = next.lat
        self.currentLng = next.lng
        self.cooldownRemainingSec = next.waitTimeSec
        self.waitAccumulatedMs = 0.0
        pushCurrentLocation()
        showToast("已手動跳至第 \(self.currentRouteIndex + 1) 點")
    }

    /// 跳轉至指定基準航點開始運行 (點擊數字球時觸發)
    public func jumpToWaypoint(index: Int) {
        let validIdx = min(max(index, 0), max(displayWaypoints.count - 1, 0))
        if executionMode == 1 { // 種花模式：尋找對應 flowerIndex 的第一個節點
            let targetFlowerNum = validIdx + 1
            if let nodeIdx = routePoints.firstIndex(where: { $0.flowerIndex == targetFlowerNum }) {
                self.currentRouteIndex = nodeIdx
                self.currentLat = routePoints[nodeIdx].lat
                self.currentLng = routePoints[nodeIdx].lng
            } else if validIdx < displayWaypoints.count {
                let node = displayWaypoints[validIdx]
                self.currentLat = node.lat
                self.currentLng = node.lng
            }
        } else if !originalBasePoints.isEmpty && routePoints.count > originalBasePoints.count {
            let ratio = Double(validIdx) / Double(originalBasePoints.count)
            let nodeIdx = min(Int(ratio * Double(routePoints.count)), max(routePoints.count - 1, 0))
            self.currentRouteIndex = nodeIdx
            self.currentLat = routePoints[nodeIdx].lat
            self.currentLng = routePoints[nodeIdx].lng
        } else if validIdx < routePoints.count {
            self.currentRouteIndex = validIdx
            self.currentLat = routePoints[validIdx].lat
            self.currentLng = routePoints[validIdx].lng
        }
        self.cooldownRemainingSec = 0
        self.waitAccumulatedMs = 0.0
        self.isRoutePaused = false // 從此點開始運行，保持自動巡航
        pushCurrentLocation()
        ensureEngineRunning()
        autoSaveCurrentProgress()
        showToast("已從第 \(validIdx + 1) 個航點開始巡航")
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
            fruitWalkDistance: fruitWalkDistance
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

        // 1. 自動暫停路線
        if !isRoutePaused {
            self.isRoutePaused = true
        }

        // 2. 瞬移至幾何中心點
        self.currentLat = center.lat
        self.currentLng = center.lng
        pushCurrentLocation()
        showToast("已定位至【\(activeRouteName)】幾何中心 (已暫停路線)")
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
            routePoints: routePoints,
            basePoints: originalBasePoints,
            executionMode: executionMode,
            fruitWalkDistance: fruitWalkDistance
        )
        RouteProgressStore.saveProgress(progress)
        showToast("已暫存【\(progress.routeName)】進度：第 \(progress.currentLoop + 1) 圈 第 \(progress.currentRouteIndex)/\(progress.totalPoints) 點")
        stopRoute()
    }

    /// 恢復暫存進度
    public func resumeProgress(_ progress: RouteProgress) {
        self.originalBasePoints = progress.basePoints ?? []
        self.routePoints = progress.routePoints
        self.activeRouteName = progress.routeName
        self.routeLoopTarget = progress.loopTarget
        self.routeCurrentLoop = progress.currentLoop
        self.executionMode = progress.executionMode
        self.fruitWalkDistance = progress.fruitWalkDistance

        let validIndex = min(max(progress.currentRouteIndex, 0), self.routePoints.count - 1)
        self.currentRouteIndex = validIndex
        self.currentLat = self.routePoints[validIndex].lat
        self.currentLng = self.routePoints[validIndex].lng
        self.isRoutePaused = false
        self.cooldownRemainingSec = 0
        self.waitAccumulatedMs = 0.0

        pushCurrentLocation()
        ensureEngineRunning()
        showToast("已接續【\(progress.routeName)】進度 (第 \(progress.currentLoop + 1) 圈)")
    }

    /// 停止路線 (僅停止自動行進，不解除虛擬定位，角色維持在當前座標)
    public func stopRoute() {
        self.routePoints = []
        self.originalBasePoints = []
        self.currentRouteIndex = 0
        self.isRoutePaused = true
        self.activeRouteName = "無路線"
        self.cooldownRemainingSec = 0
        self.waitAccumulatedMs = 0.0
        self.etaString = "--:--"
        self.detourDepartureCoord = nil
        showToast("已停止路線 (維持當前虛擬位置)")
    }

    /// 停止虛擬定位模擬 (徹底停止 DVT，重置 locationd，整機還原真實 GPS)
    public func stopMocking() {
        stopRoute()
        _ = LocationEngine.clear()
        SilentAudioKeepAlive.shared.stop()
        BackgroundKeepAlive.shared.stop()
        self.isSimulatingLocation = false
        showToast("已停止虛擬定位，回到現實位置")
    }

    /// 手動瞬移至指定座標 (方案 A: 支援掛起插隊，自動記錄中斷點與瞬移歷史，按繼續自動返回接續)
    public func teleport(to lat: Double, lng: Double, label: String = "") {
        // 若當前有排程路線且尚未記錄過插隊中斷點
        if !routePoints.isEmpty {
            if detourDepartureCoord == nil {
                self.detourDepartureCoord = CLLocationCoordinate2D(latitude: currentLat, longitude: currentLng)
            }
            self.isRoutePaused = true
        } else if !isRoutePaused {
            isRoutePaused = true
        }

        self.currentLat = lat
        self.currentLng = lng
        pushCurrentLocation()

        let pointLabel = label.isEmpty ? "自訂座標" : label
        SavedDatabaseStore.shared.addTeleportHistory(lat: lat, lng: lng, label: pointLabel)

        if detourDepartureCoord != nil {
            showToast("已瞬移至【\(pointLabel)】(路線已暫停，按繼續自動返回原位接續)")
        } else {
            showToast("已瞬移至 \(String(format: "%.5f", lat)), \(String(format: "%.5f", lng))")
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
        if timer == nil {
            lastTickTime = Date().timeIntervalSinceReferenceDate
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                self?.engineTick()
            }
        }
    }

    private func engineTick() {
        let now = Date().timeIntervalSinceReferenceDate
        let deltaSec = now - lastTickTime
        lastTickTime = now

        var isMoving = false
        let stepDistMeters = (speedKmh / 3.6) * deltaSec

        // 1. 處理手動虛擬方向盤
        if joystickIntensity > 0 {
            let moveDist = stepDistMeters * joystickIntensity
            let dest = EngineMath.moveLocation(lat: currentLat, lng: currentLng, distanceMeters: moveDist, bearingDegrees: joystickAngle)
            self.currentLat = dest.lat
            self.currentLng = dest.lng
            isMoving = true
        }
        // 2. 處理自動路線循跡
        else if !routePoints.isEmpty && !isRoutePaused {
            if currentRouteIndex >= routePoints.count {
                currentRouteIndex = routePoints.count - 1
                isRoutePaused = true
            } else {
                let target = routePoints[currentRouteIndex]

                if target.isTeleport {
                    self.currentLat = target.lat
                    self.currentLng = target.lng
                    let targetWaitMs = Double(target.waitTimeSec * 1000)

                    if targetWaitMs > 0 && waitAccumulatedMs < targetWaitMs {
                        let remaining = Int(ceil((targetWaitMs - waitAccumulatedMs) / 1000.0))
                        self.cooldownRemainingSec = max(remaining, 1)
                        waitAccumulatedMs += (deltaSec * 1000.0)
                    } else {
                        self.cooldownRemainingSec = 0
                        self.waitAccumulatedMs = 0.0
                        advanceToNextWaypoint()
                    }
                } else {
                    let distToTarget = EngineMath.getDistance(lat1: currentLat, lon1: currentLng, lat2: target.lat, lon2: target.lng)

                    if distToTarget <= stepDistMeters {
                        self.currentLat = target.lat
                        self.currentLng = target.lng
                        let targetWaitMs = Double(target.waitTimeSec * 1000)

                        if targetWaitMs > 0 && waitAccumulatedMs < targetWaitMs {
                            let remaining = Int(ceil((targetWaitMs - waitAccumulatedMs) / 1000.0))
                            self.cooldownRemainingSec = max(remaining, 1)
                            waitAccumulatedMs += (deltaSec * 1000.0)
                        } else {
                            self.cooldownRemainingSec = 0
                            self.waitAccumulatedMs = 0.0
                            advanceToNextWaypoint()
                        }
                    } else {
                        self.cooldownRemainingSec = 0
                        let bearing = EngineMath.getBearing(lat1: currentLat, lon1: currentLng, lat2: target.lat, lon2: target.lng)
                        let dest = EngineMath.moveLocation(lat: currentLat, lng: currentLng, distanceMeters: stepDistMeters, bearingDegrees: bearing)
                        self.currentLat = dest.lat
                        self.currentLng = dest.lng
                        isMoving = true
                    }
                }
            }
        }

        if isMoving {
            pushCurrentLocation()
        }
    }

    private func advanceToNextWaypoint() {
        self.currentRouteIndex += 1
        autoSaveCurrentProgress()
        if self.currentRouteIndex >= self.routePoints.count {
            let shouldLoop = (self.routeLoopTarget == 0) || (self.routeCurrentLoop < self.routeLoopTarget - 1)
            if shouldLoop {
                self.routeCurrentLoop += 1
                if self.executionMode == 2 { // 果實循環
                    if let first = self.routePoints.first {
                        let cdSec = EngineMath.calculateCooldownSeconds(distanceMeters: EngineMath.getDistance(lat1: currentLat, lon1: currentLng, lat2: first.lat, lon2: first.lng))
                        self.routePoints[0].waitTimeSec = cdSec
                        self.routePoints[0].isTeleport = true
                        self.currentRouteIndex = 0
                        self.currentLat = first.lat
                        self.currentLng = first.lng
                    }
                } else if self.executionMode == 0 && self.loopMode == .teleportToStart { // 直線跳回起點
                    self.currentRouteIndex = 1
                    if let first = self.routePoints.first {
                        self.currentLat = first.lat
                        self.currentLng = first.lng
                    }
                } else {
                    self.currentRouteIndex = 0
                    if let first = self.routePoints.first {
                        self.currentLat = first.lat
                        self.currentLng = first.lng
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

    private func pushCurrentLocation() {
        let pPath = pairingFilePath.isEmpty ? PairingStore.shared.pairingPath : pairingFilePath
        let result = LocationEngine.set(
            latitude: currentLat,
            longitude: currentLng,
            pairingPath: pPath,
            deviceIP: deviceIP
        )
        DispatchQueue.main.async {
            switch result {
            case .success:
                self.pushFailureCount = 0
                self.isSimulatingLocation = true
            case .failure(let err):
                self.pushFailureCount += 1
                if self.pushFailureCount == 15 {
                    self.isSimulatingLocation = false
                    self.showToast("通道暫時斷開，正在重新連線...")
                    print("[AutoFarmSession] LocationEngine error: \(err.localizedDescription)")
                }
            }
        }
    }

    /// 握手並準備連線 (用於在 4G/Wi-Fi 下預先驗證通道)
    public func prepareConnection() {
        showToast("正在建立調試通道握手...")
        let pPath = pairingFilePath.isEmpty ? PairingStore.shared.pairingPath : pairingFilePath
        let result = LocationEngine.set(
            latitude: currentLat,
            longitude: currentLng,
            pairingPath: pPath,
            deviceIP: deviceIP
        )
        DispatchQueue.main.async {
            switch result {
            case .success:
                self.isSimulatingLocation = true
                self.showToast("通道握手成功！可開回行動數據開始巡航")
            case .failure(let err):
                self.isSimulatingLocation = false
                self.showToast("連線未就緒: \(err.localizedDescription)")
            }
        }
    }

    private func showToast(_ msg: String) {
        DispatchQueue.main.async {
            self.toastMessage = msg
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                if self.toastMessage == msg {
                    self.toastMessage = nil
                }
            }
        }
    }
}
