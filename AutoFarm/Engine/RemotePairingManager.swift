import Foundation
import UIKit
import idevice

public final class RemotePairingManager: NSObject, ObservableObject, NetServiceDelegate {
    public static let shared = RemotePairingManager()

    @Published public var isPairing: Bool = false
    @Published public var pairingPin: String? = nil
    @Published public var statusMessage: String? = nil
    @Published public var isSuccess: Bool = false

    private var netService: NetService?

    public func startPairing() {
        guard !isPairing else { return }
        isPairing = true
        pairingPin = nil
        statusMessage = "正在啟動配對廣播，請稍候..."
        isSuccess = false

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let contextPtr = Unmanaged.passUnretained(self).toOpaque()

            let pinCb: @convention(c) (UnsafePointer<CChar>?, UnsafeMutableRawPointer?) -> Void = { pinPtr, ctx in
                guard let pinPtr = pinPtr, let ctx = ctx else { return }
                let mgr = Unmanaged<RemotePairingManager>.fromOpaque(ctx).takeUnretainedValue()
                let pin = String(cString: pinPtr)
                DispatchQueue.main.async {
                    mgr.pairingPin = pin
                    mgr.statusMessage = "請記下配對碼，前往 iPhone「設定 → 隱私權與安全性 → 開發者模式」選取 AutoFarm 並輸入！"
                }
            }

            let listenCb: @convention(c) (UInt16, UnsafePointer<CChar>?, UnsafePointer<CChar>?, UnsafePointer<CChar>?, UnsafePointer<CChar>?, UnsafePointer<CChar>?, UnsafePointer<CChar>?, UnsafeMutableRawPointer?) -> Void = { port, sId, name, model, authTag, ver, minVer, ctx in
                guard let ctx = ctx else { return }
                let mgr = Unmanaged<RemotePairingManager>.fromOpaque(ctx).takeUnretainedValue()
                let portNum = port
                let sIdStr = sId != nil ? String(cString: sId!) : ""
                let nameStr = name != nil ? String(cString: name!) : "AutoFarm"
                let modelStr = model != nil ? String(cString: model!) : "Mac"
                let authTagStr = authTag != nil ? String(cString: authTag!) : ""
                let verStr = ver != nil ? String(cString: ver!) : "1"
                let minVerStr = minVer != nil ? String(cString: minVer!) : "1"

                DispatchQueue.main.async {
                    mgr.publishBonjour(port: portNum, name: nameStr, serviceId: sIdStr, model: modelStr, authTag: authTagStr, ver: verStr, minVer: minVerStr)
                }
            }

            let connCb: @convention(c) (UnsafeMutableRawPointer?) -> Void = { ctx in
                guard let ctx = ctx else { return }
                let mgr = Unmanaged<RemotePairingManager>.fromOpaque(ctx).takeUnretainedValue()
                DispatchQueue.main.async {
                    mgr.statusMessage = "已偵測到手機連入，正在交換安全金鑰..."
                }
            }

            var altIrk = [UInt8](repeating: 0, count: 16)
            var pairingHandle: OpaquePointer?

            let err = "AutoFarm".withCString { nameC in
                "Mac".withCString { modelC in
                    pairable_host_accept(
                        nameC,
                        modelC,
                        0,
                        pinCb,
                        contextPtr,
                        listenCb,
                        contextPtr,
                        connCb,
                        contextPtr,
                        &altIrk,
                        &pairingHandle
                    )
                }
            }

            DispatchQueue.main.async {
                self.stopBonjour()
                self.isPairing = false

                if let err = err {
                    let msg = err.pointee.message != nil ? String(cString: err.pointee.message) : "未知錯誤"
                    idevice_error_free(err)
                    self.isSuccess = false
                    self.statusMessage = "配對失敗: \(msg)"
                } else if let handle = pairingHandle {
                    defer { rp_pairing_file_free(handle) }
                    let savePath = PairingStore.shared.pairingPath
                    let writeErr = savePath.withCString { rp_pairing_file_write(handle, $0) }
                    if writeErr == nil {
                        self.isSuccess = true
                        self.statusMessage = "手機配對成功！已保存授權金鑰，現在可進行通道握手與巡航。"
                        AutoFarmSession.shared.toastMessage = "配對成功！已就緒。"
                    } else {
                        idevice_error_free(writeErr)
                        self.isSuccess = false
                        self.statusMessage = "保存配對憑證檔案失敗"
                    }
                } else {
                    self.isSuccess = false
                    self.statusMessage = "未能取得配對金鑰"
                }
            }
        }
    }

    private func publishBonjour(port: UInt16, name: String, serviceId: String, model: String, authTag: String, ver: String, minVer: String) {
        let service = NetService(domain: "", type: "_remotepairing-pairable-host._tcp.", name: name, port: Int32(port))
        service.delegate = self

        var txtDict: [String: Data] = [:]
        if let d = serviceId.data(using: .utf8) { txtDict["serviceIdentifier"] = d }
        if let d = model.data(using: .utf8) { txtDict["model"] = d }
        if let d = authTag.data(using: .utf8) { txtDict["authTag"] = d }
        if let d = ver.data(using: .utf8) { txtDict["ver"] = d }
        if let d = minVer.data(using: .utf8) { txtDict["minVer"] = d }

        service.setTXTRecord(NetService.data(fromTXTRecord: txtDict))
        service.publish()
        self.netService = service
    }

    private func stopBonjour() {
        netService?.stop()
        netService = nil
    }
}
