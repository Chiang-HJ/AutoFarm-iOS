import AVFoundation
import Foundation
import UIKit

/// 播放靜音音訊以在背景維持 AutoFarm 存活與 TCP 網路連線 (處理中斷、App狀態與長時間背景防休眠)
public final class SilentAudioKeepAlive: NSObject, AVAudioPlayerDelegate {
    public static let shared = SilentAudioKeepAlive()

    private var player: AVAudioPlayer?
    private var wasActive = false

    public override init() {
        super.init()
        setupNotifications()
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMediaReset),
            name: AVAudioSession.mediaServicesWereResetNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
    }

    public func start() {
        wasActive = true
        ensurePlaying()
    }

    public func stop() {
        wasActive = false
        player?.stop()
        player = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    public func ensurePlaying() {
        guard wasActive else { return }
        if let p = player, p.isPlaying {
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers, .duckOthers])
            try session.setActive(true)

            let url = try Self.writeSilentWAV()
            let p = try AVAudioPlayer(contentsOf: url)
            p.delegate = self
            p.numberOfLoops = -1
            p.volume = 0.01
            p.prepareToPlay()
            p.play()
            self.player = p
            NSLog("[AutoFarm] Silent audio keep-alive active")
        } catch {
            NSLog("[AutoFarm] Silent audio start failed: %@", error.localizedDescription)
        }
    }

    @objc private func handleInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        switch type {
        case .began:
            NSLog("[AutoFarm] Audio interruption began")
        case .ended:
            NSLog("[AutoFarm] Audio interruption ended, restoring keep-alive...")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.ensurePlaying()
            }
        @unknown default:
            break
        }
    }

    @objc private func handleMediaReset() {
        NSLog("[AutoFarm] Media services reset, rebuilding audio keep-alive...")
        player = nil
        ensurePlaying()
    }

    @objc private func handleAppDidBecomeActive() {
        if wasActive {
            ensurePlaying()
        }
    }

    @objc private func handleAppDidEnterBackground() {
        if wasActive {
            ensurePlaying()
        }
    }

    private static func writeSilentWAV() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("autofarm-silence-v2.wav")
        if FileManager.default.fileExists(atPath: url.path) { return url }

        let sampleRate: Int = 16000
        let durationSamples = sampleRate * 2 // 2.0s
        var data = Data()

        func appendUInt32(_ v: UInt32) {
            var le = v.littleEndian
            withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
        }
        func appendUInt16(_ v: UInt16) {
            var le = v.littleEndian
            withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
        }

        let dataSize = UInt32(durationSamples * 2)
        data.append(contentsOf: Array("RIFF".utf8))
        appendUInt32(36 + dataSize)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        appendUInt32(16)
        appendUInt16(1) // PCM
        appendUInt16(1) // mono
        appendUInt32(UInt32(sampleRate))
        appendUInt32(UInt32(sampleRate * 2))
        appendUInt16(2)
        appendUInt16(16)
        data.append(contentsOf: Array("data".utf8))
        appendUInt32(dataSize)
        data.append(Data(count: Int(dataSize))) // zeros = silence

        try data.write(to: url, options: .atomic)
        return url
    }
}
