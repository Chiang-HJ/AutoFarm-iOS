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
    @Published public var speedKmh: Double = 9.0

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
        showToast("已啟動同心圓種花 (\(nodes.count) 點，無限循環)")
    }

    /// 暫停 / 繼續切換
    public func toggleRoutePause() {
        self.isRoutePaused.toggle()
        if self.isRoutePaused {
            self.waitAccumulatedMs = 0.0
            self.cooldownRemainingSec = 0
            showToast("路線已暫停")
        } else {
            showToast("路線繼續執行")
        }
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

    /// 手動瞬移至指定座標
    public func teleport(to lat: Double, lng: Double) {
        if !isRoutePaused {
            isRoutePaused = true
        }
        self.currentLat = lat
        self.currentLng = lng
        pushCurrentLocation()
        showToast("已瞬移至 \(String(format: "%.5f", lat)), \(String(format: "%.5f", lng))")
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
                self.isSimulatingLocation = true
            case .failure(let err):
                self.isSimulatingLocation = false
                self.showToast("定位失敗: \(err.localizedDescription)")
                print("[AutoFarmSession] LocationEngine error: \(err.localizedDescription)")
            }
        }
    }

    /// 借鏡 FreeWay: 握手並準備連線 (用於在 4G/Wi-Fi 下預先驗證通道)
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
