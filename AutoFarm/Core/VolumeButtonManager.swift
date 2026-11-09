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
        UserDefaults.standard.bool(forKey: "AutoFarm_EnableVolumeControl")
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
    private var volumeView: MPVolumeView?
    private var lastTriggerTime: TimeInterval = 0
    private var isResettingVolume: Bool = false

    private var volumeSlider: UISlider? {
        volumeView?.subviews.first(where: { $0 is UISlider }) as? UISlider
    }

    private override init() {
        super.init()
        if isEnabled {
            startMonitoring()
        }
    }

    public func startMonitoring() {
        guard !isObserving else { return }
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Audio session active error: \(error)")
        }

        AVAudioSession.sharedInstance().addObserver(self, forKeyPath: "outputVolume", options: [.new, .old], context: nil)
        isObserving = true

        DispatchQueue.main.async {
            if self.volumeView == nil {
                let v = MPVolumeView(frame: CGRect(x: -1000, y: -1000, width: 1, height: 1))
                v.clipsToBounds = true
                v.alpha = 0.01
                if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let window = scene.windows.first {
                    window.addSubview(v)
                    self.volumeView = v
                }
            }

            // 初始化時將系統音量調至 0.5 中點
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.isResettingVolume = true
                self.volumeSlider?.setValue(0.5, animated: false)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    self.isResettingVolume = false
                }
            }
        }
    }

    public func stopMonitoring() {
        guard isObserving else { return }
        AVAudioSession.sharedInstance().removeObserver(self, forKeyPath: "outputVolume")
        isObserving = false
        volumeView?.removeFromSuperview()
        volumeView = nil
    }

    public override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        guard keyPath == "outputVolume", let change = change else { return }
        if isResettingVolume { return }

        guard let newVolume = change[.newKey] as? Float, let oldVolume = change[.oldKey] as? Float else { return }
        if abs(newVolume - oldVolume) < 0.0005 { return }

        let now = Date().timeIntervalSinceReferenceDate
        // 防抖閥值 0.35 秒，杜絕硬體一次按壓重複觸發 (+2)
        guard now - lastTriggerTime > 0.35 else { return }
        lastTriggerTime = now

        let isUp = (newVolume > oldVolume) || (newVolume >= 0.99)
        let isDown = (newVolume < oldVolume) || (newVolume <= 0.01)

        DispatchQueue.main.async {
            if isUp {
                self.executeAction(self.volumeUpAction)
            } else if isDown {
                self.executeAction(self.volumeDownAction)
            }

            // 將滑桿重設回 0.5，讓音量鍵 (+) 與 (-) 永遠處於可感測區間
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                self.isResettingVolume = true
                self.volumeSlider?.setValue(0.5, animated: false)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    self.isResettingVolume = false
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
