import Foundation
import MediaPlayer
import AVFoundation
import UIKit

public enum VolumeKeyAction: String, CaseIterable, Identifiable {
    case nextPoint = "NEXT_POINT"
    case prevPoint = "PREV_POINT"
    case togglePause = "TOGGLE_PAUSE"
    case speedUp = "SPEED_UP"
    case speedDown = "SPEED_DOWN"
    case none = "NONE"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .nextPoint: return "下一點 / 下一朵花"
        case .prevPoint: return "上一點 / 上一朵花"
        case .togglePause: return "暫停 / 繼續巡航"
        case .speedUp: return "增加速度 (+1 km/h)"
        case .speedDown: return "減少速度 (-1 km/h)"
        case .none: return "無動作 (停用)"
        }
    }

    public var systemIcon: String {
        switch self {
        case .nextPoint: return "forward.fill"
        case .prevPoint: return "backward.fill"
        case .togglePause: return "playpause.fill"
        case .speedUp: return "speedometer"
        case .speedDown: return "gauge.with.dots.needle.bottom.0percent"
        case .none: return "slash.circle"
        }
    }
}

public final class VolumeButtonManager: NSObject, ObservableObject {
    public static let shared = VolumeButtonManager()

    @Published public var isEnabled: Bool = {
        if UserDefaults.standard.object(forKey: "AutoFarm_EnableVolumeControl") == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: "AutoFarm_EnableVolumeControl")
    }() {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "AutoFarm_EnableVolumeControl")
            if isEnabled {
                startMonitoring()
            } else {
                stopMonitoring()
            }
        }
    }

    @Published public var volumeUpAction: VolumeKeyAction = {
        if let raw = UserDefaults.standard.string(forKey: "AutoFarm_VolumeUpAction"),
           let act = VolumeKeyAction(rawValue: raw) {
            return act
        }
        return .nextPoint
    }() {
        didSet {
            UserDefaults.standard.set(volumeUpAction.rawValue, forKey: "AutoFarm_VolumeUpAction")
        }
    }

    @Published public var volumeDownAction: VolumeKeyAction = {
        if let raw = UserDefaults.standard.string(forKey: "AutoFarm_VolumeDownAction"),
           let act = VolumeKeyAction(rawValue: raw) {
            return act
        }
        return .prevPoint
    }() {
        didSet {
            UserDefaults.standard.set(volumeDownAction.rawValue, forKey: "AutoFarm_VolumeDownAction")
        }
    }

    private var isObserving = false
    private weak var volumeView: MPVolumeView?
    private weak var volumeSlider: UISlider?
    private var lastTriggerTime: TimeInterval = 0
    private var lastVolumeChangeTime: TimeInterval = 0
    private var consecutivePressCount: Int = 0
    private var lastDirectionIsUp: Bool = false
    private var currentUserVolume: Float = 0.5
    private var isResetting: Bool = false

    private override init() {
        super.init()
        if isEnabled {
            startMonitoring()
        }
    }

    /// 由 SwiftUI 視圖層級直接注入已掛載至真實 Window 的 MPVolumeView
    public func setupVolumeView(_ view: MPVolumeView) {
        self.volumeView = view
        findAndCacheSlider(in: view)
        if isEnabled {
            startMonitoring()
        }
    }

    private func searchSlider(in root: UIView) -> UISlider? {
        if let s = root as? UISlider { return s }
        for sub in root.subviews {
            if let s = searchSlider(in: sub) { return s }
        }
        return nil
    }

    private func findAndCacheSlider(in root: UIView) {
        if let s = searchSlider(in: root) {
            self.volumeSlider = s
        } else {
            // MPVolumeView 可能在首次渲染時非同步建構 subviews
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self, weak root] in
                guard let self = self, let r = root else { return }
                self.volumeSlider = self.searchSlider(in: r)
            }
        }
    }

    private var activeSlider: UISlider? {
        if let s = volumeSlider { return s }
        if let v = volumeView, let s = searchSlider(in: v) {
            self.volumeSlider = s
            return s
        }
        return nil
    }

    /// 真正透過 MPVolumeSlider 與 valueChanged 事件變更系統音量
    private func setSystemVolume(_ val: Float) {
        let work = {
            guard let slider = self.activeSlider else { return }
            slider.setValue(val, animated: false)
            slider.sendActions(for: .valueChanged)
        }

        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    public func startMonitoring() {
        guard !isObserving else { return }

        // 使用 .playback + .mixWithOthers，與 SilentAudioKeepAlive 保持一致，確保在背景進入皮克敏畫面時仍可接收音量事件
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            print("[VolumeButtonManager] Audio session active error: \(error)")
        }

        let current = AVAudioSession.sharedInstance().outputVolume
        // 邊界微調保護：若為純 0，維持微小 0.005 使音量減鍵可觸發；若為純 1.0，維持 0.995 使音量加鍵可觸發
        if current <= 0.005 {
            self.currentUserVolume = 0.005
            setSystemVolume(0.005)
        } else if current >= 0.995 {
            self.currentUserVolume = 0.995
            setSystemVolume(0.995)
        } else {
            self.currentUserVolume = current
        }

        AVAudioSession.sharedInstance().addObserver(self, forKeyPath: "outputVolume", options: [.new, .old], context: nil)
        isObserving = true
    }

    public func stopMonitoring() {
        guard isObserving else { return }
        AVAudioSession.sharedInstance().removeObserver(self, forKeyPath: "outputVolume")
        isObserving = false
        restoreExactVolumeOnRouteStop()
    }

    /// 在路線停止時將微調邊界還原至純粹 0.0 或 1.0
    public func restoreExactVolumeOnRouteStop() {
        let current = AVAudioSession.sharedInstance().outputVolume
        if current <= 0.01 {
            setSystemVolume(0.0)
        } else if current >= 0.99 {
            setSystemVolume(1.0)
        }
    }

    public override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        guard keyPath == "outputVolume", let change = change else { return }
        if isResetting { return }
        guard let newVolume = change[.newKey] as? Float else { return }

        let now = Date().timeIntervalSinceReferenceDate
        let session = AutoFarmSession.shared

        // 1. 條件過濾：若未開啟音量控制、無運行中路線或處於暫停/未模擬狀態，完全不攔截，正常調整音量
        let isRouteActive = isEnabled && session.isSimulatingLocation && !session.isRoutePaused && !session.routePoints.isEmpty
        guard isRouteActive else {
            self.currentUserVolume = newVolume
            return
        }

        let delta = abs(newVolume - currentUserVolume)

        // 2. 忽略極微小抖動 (低於 0.003)
        if delta < 0.003 { return }

        // 3. 若滑動控制中心或設定滑桿 (變化量超過 0.09)，屬於手動調整音量，直接接受新音量，不重設也不跳點
        if delta > 0.09 {
            self.currentUserVolume = newVolume
            return
        }

        let isUp = (newVolume > currentUserVolume)
        let isDown = (newVolume < currentUserVolume)

        // 4. 連續按壓偵測：若在 0.45 秒內朝同一方向連續按壓，代表使用者正在主畫面或其他 App 連續調整音量，放行並更新基準
        let timeSinceLastPress = now - lastVolumeChangeTime
        lastVolumeChangeTime = now

        if timeSinceLastPress < 0.45 && (isUp == lastDirectionIsUp) {
            consecutivePressCount += 1
        } else {
            consecutivePressCount = 1
            lastDirectionIsUp = isUp
        }

        if consecutivePressCount >= 2 {
            self.currentUserVolume = newVolume
            return
        }

        // 5. 硬體按鍵防抖：0.35 秒內不重複觸發動作 (杜絕硬體一次按壓產生 +2 點位跳躍)
        guard now - lastTriggerTime > 0.35 else { return }
        lastTriggerTime = now

        let targetVolumeToRestore = self.currentUserVolume

        DispatchQueue.main.async {
            // 執行跳點動作 (下一點 / 上一點)
            if isUp {
                self.executeAction(self.volumeUpAction)
            } else if isDown {
                self.executeAction(self.volumeDownAction)
            }

            // 保持使用者原音量：將音量精確還原回按鍵前的原數值，絕不強制固定特定音量
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
                self.isResetting = true

                // 特殊邊界保護：若原音量為 0 (靜音)，維持極微小 0.005 (DAC 靜音無聲，但可使下次音量減鍵產生 0.00 之下降事件)
                // 若原音量為 1.0 (滿格)，維持 0.995 (可使下次音量加鍵產生 1.00 之上升事件)
                let restoreVal: Float
                if targetVolumeToRestore <= 0.005 {
                    restoreVal = 0.005
                } else if targetVolumeToRestore >= 0.995 {
                    restoreVal = 0.995
                } else {
                    restoreVal = targetVolumeToRestore
                }

                self.setSystemVolume(restoreVal)

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
                    self.isResetting = false
                }
            }
        }
    }

    private func executeAction(_ action: VolumeKeyAction) {
        let session = AutoFarmSession.shared
        switch action {
        case .nextPoint:
            session.nextRoutePoint()
        case .prevPoint:
            session.prevRoutePoint()
        case .togglePause:
            session.togglePauseResume()
        case .speedUp:
            session.adjustSpeed(by: 1.0)
        case .speedDown:
            session.adjustSpeed(by: -1.0)
        case .none:
            break
        }
    }
}
