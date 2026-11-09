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
    private var volumeWindow: UIWindow?
    private var volumeView: MPVolumeView?
    private var lastTriggerTime: TimeInterval = 0
    private var userOriginalVolume: Float = 0.0
    private var userBaselineVolume: Float = 0.05

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

        // 設置為 ambient + mixWithOthers，保證 100% 靜音且不打擾其他正在播放的聲音
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Audio session active error: \(error)")
        }

        let sysVol = AVAudioSession.sharedInstance().outputVolume
        self.userOriginalVolume = sysVol

        // 計算基準點：
        // 若使用者原本為 0 音量，使用 0.005 (極微量、DAC 無聲音輸出，但足以讓硬體音量減鍵產生下降至 0.000 之感測)
        // 若使用者原本為滿音量 1.0，使用 0.995 (使音量加鍵足以產生上升至 1.000 之感測)
        // 其餘皆完美維持使用者原設定之音量
        if sysVol < 0.02 {
            self.userBaselineVolume = 0.005
        } else if sysVol > 0.98 {
            self.userBaselineVolume = 0.995
        } else {
            self.userBaselineVolume = sysVol
        }

        AVAudioSession.sharedInstance().addObserver(self, forKeyPath: "outputVolume", options: [.new, .old], context: nil)
        isObserving = true

        DispatchQueue.main.async {
            if self.volumeWindow == nil {
                let win = UIWindow(frame: CGRect(x: -200, y: -200, width: 1, height: 1))
                win.isHidden = false
                win.windowLevel = .alert + 1
                let v = MPVolumeView(frame: win.bounds)
                v.clipsToBounds = true
                v.alpha = 0.01
                win.addSubview(v)
                self.volumeWindow = win
                self.volumeView = v
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.volumeSlider?.setValue(self.userBaselineVolume, animated: false)
            }
        }
    }

    public func stopMonitoring() {
        guard isObserving else { return }
        AVAudioSession.sharedInstance().removeObserver(self, forKeyPath: "outputVolume")
        isObserving = false

        // 停止時將音量百分之百精確還原至使用者進入前的原始音量 (包括 0 音量)
        self.volumeSlider?.setValue(self.userOriginalVolume, animated: false)

        volumeView?.removeFromSuperview()
        volumeView = nil
        volumeWindow?.isHidden = true
        volumeWindow = nil
    }

    public override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        guard keyPath == "outputVolume", let change = change else { return }
        guard let newVolume = change[.newKey] as? Float else { return }

        // 若音量等於基準點（重設時觸發之回調），完全忽略
        if abs(newVolume - userBaselineVolume) < 0.012 { return }

        let now = Date().timeIntervalSinceReferenceDate
        // 硬體防抖閥值 0.45 秒，杜絕硬體一次按壓重複觸發 (+2)
        guard now - lastTriggerTime > 0.45 else { return }
        lastTriggerTime = now

        let isUp = (newVolume > userBaselineVolume)
        let isDown = (newVolume < userBaselineVolume)

        DispatchQueue.main.async {
            if isUp {
                self.executeAction(self.volumeUpAction)
            } else if isDown {
                self.executeAction(self.volumeDownAction)
            }

            // 重設回基準點，使加減鍵永遠可持續感測，且保持使用者原音量
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self.volumeSlider?.setValue(self.userBaselineVolume, animated: false)
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
