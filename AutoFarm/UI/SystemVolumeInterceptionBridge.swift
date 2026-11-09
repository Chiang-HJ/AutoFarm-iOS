import SwiftUI
import MediaPlayer

/// 隱形掛載於主視窗的 MPVolumeView，保證 100% 隱藏系統音量 HUD 並提供實體音量加減鍵雙向精確感測
public struct SystemVolumeInterceptionBridge: UIViewRepresentable {
    public init() {}

    public func makeUIView(context: Context) -> MPVolumeView {
        let v = MPVolumeView(frame: CGRect(x: -100, y: -100, width: 1, height: 1))
        v.alpha = 0.001
        v.clipsToBounds = true
        v.showsRouteButton = false
        VolumeButtonManager.shared.setupVolumeView(v)
        return v
    }

    public func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}
