import Foundation
import idevice

enum LocationEngineError: LocalizedError {
    case invalidIP
    case pairingRead
    case tunnelCreate
    case remoteServer
    case simulationCreate
    case locationSet
    case locationClear
    case notActive

    var errorDescription: String? {
        switch self {
        case .invalidIP: return "Tunnel IP 無效 (預設為 10.7.1.1 或 10.7.0.1)"
        case .pairingRead: return "無法讀取配對憑證檔 (.plist)"
        case .tunnelCreate: return "無法建立通道 (請確認 LocalDevVPN 已連線)：\(LocationEngine.lastDetailedError)"
        case .remoteServer: return "通道已連線但 RemoteXPC 握手失敗：\(LocationEngine.lastDetailedError)"
        case .simulationCreate: return "無法啟動模擬服務 (請確認 iPhone 開發者模式已開啟)：\(LocationEngine.lastDetailedError)"
        case .locationSet: return "寫入虛擬座標失敗：\(LocationEngine.lastDetailedError)"
        case .locationClear: return "清除虛擬定位失敗"
        case .notActive: return "無作用中的定位模擬"
        }
    }

    static func from(code: Int32) -> LocationEngineError {
        switch code {
        case 1: return .invalidIP
        case 2: return .pairingRead
        case 3: return .tunnelCreate
        case 9: return .remoteServer
        case 10: return .simulationCreate
        case 11: return .locationSet
        case 12: return .locationClear
        default: return .locationSet
        }
    }
}

/// Thin Swift wrapper around idevice’s DVT location simulation (injects into locationd).
enum LocationEngine {
    private static let queue = DispatchQueue(label: "com.chrismack.locus.location", qos: .userInitiated)

    private static var adapter: OpaquePointer?
    private static var handshake: OpaquePointer?
    private static var remoteServer: OpaquePointer?
    private static var locationSimulation: OpaquePointer?

    private static let ok: Int32 = 0
    private static let invalidIP: Int32 = 1
    private static let pairingRead: Int32 = 2
    private static let tunnelCreate: Int32 = 3
    private static let remoteServerCode: Int32 = 9
    private static let simulationCreate: Int32 = 10
    private static let locationSet: Int32 = 11
    private static let locationClear: Int32 = 12

    static var isSessionActive: Bool { locationSimulation != nil }

    static func set(latitude: Double, longitude: Double, pairingPath: String, deviceIP: String) -> Result<Void, LocationEngineError> {
        var result: Result<Void, LocationEngineError> = .failure(.locationSet)
        queue.sync {
            let code = setLocked(latitude: latitude, longitude: longitude, pairingPath: pairingPath, deviceIP: deviceIP)
            result = code == ok ? .success(()) : .failure(.from(code: code))
        }
        return result
    }

    static func clear(pairingPath: String = "", deviceIP: String = "") -> Result<Void, LocationEngineError> {
        var result: Result<Void, LocationEngineError> = .failure(.notActive)
        queue.sync {
            let code = clearLocked(pairingPath: pairingPath, deviceIP: deviceIP)
            result = code == ok ? .success(()) : .failure(.from(code: code))
        }
        return result
    }

    private static func cleanup() {
        if let locationSimulation {
            location_simulation_free(locationSimulation)
            self.locationSimulation = nil
        }
        if let remoteServer {
            remote_server_free(remoteServer)
            self.remoteServer = nil
        }
        if let handshake {
            rsd_handshake_free(handshake)
            self.handshake = nil
        }
        if let adapter {
            adapter_free(adapter)
            self.adapter = nil
        }
    }

    public static var lastDetailedError: String = ""

    private static func extractError(_ err: UnsafeMutablePointer<IdeviceFfiError>?) -> String {
        guard let err = err else { return "未知錯誤" }
        let code = err.pointee.code
        let subCode = err.pointee.sub_code
        let msg = err.pointee.message != nil ? String(cString: err.pointee.message) : "無詳細訊息"
        return "代碼(\(code), \(subCode)): \(msg)"
    }

    private static func setLocked(latitude: Double, longitude: Double, pairingPath: String, deviceIP: String) -> Int32 {
        if let locationSimulation {
            if let err = location_simulation_set(locationSimulation, latitude, longitude) {
                idevice_error_free(err)
                cleanup()
            } else {
                return ok
            }
        }

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(49152).bigEndian
        let inetResult = deviceIP.withCString { inet_pton(AF_INET, $0, &address.sin_addr) }
        guard inetResult == 1 else { return invalidIP }

        var pairingHandle: OpaquePointer?
        var readSuccess = false
        if !pairingPath.isEmpty && FileManager.default.fileExists(atPath: pairingPath) {
            if let pairingError = pairingPath.withCString({ rp_pairing_file_read($0, &pairingHandle) }) {
                idevice_error_free(pairingError)
                pairingHandle = nil
            } else if pairingHandle != nil {
                readSuccess = true
            }
        }

        if !readSuccess {
            LocationEngine.lastDetailedError = "找不到有效的 RPPairing 憑證檔案（請先在設定中點擊「剪貼簿貼上憑證」或「匯入配對檔案」）"
            return pairingRead
        }

        guard let pairingHandle else { return pairingRead }
        defer { rp_pairing_file_free(pairingHandle) }

        var targetIP = deviceIP
        var providerError = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                tunnel_create_rppairing(
                    $0,
                    socklen_t(MemoryLayout<sockaddr_in>.stride),
                    "AutoFarm",
                    pairingHandle,
                    nil,
                    nil,
                    &adapter,
                    &handshake
                )
            }
        }

        // 自動嘗試備用 IP (10.7.1.1 <-> 10.7.0.1 雙向容錯)
        if providerError != nil {
            let altIP = (targetIP == "10.7.1.1") ? "10.7.0.1" : (targetIP == "10.7.0.1" ? "10.7.1.1" : "")
            if !altIP.isEmpty {
                var altAddress = sockaddr_in()
                altAddress.sin_family = sa_family_t(AF_INET)
                altAddress.sin_port = in_port_t(49152).bigEndian
                if altIP.withCString({ inet_pton(AF_INET, $0, &altAddress.sin_addr) }) == 1 {
                    idevice_error_free(providerError)
                    cleanup()
                    let retryError = withUnsafePointer(to: &altAddress) { pointer in
                        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                            tunnel_create_rppairing(
                                $0,
                                socklen_t(MemoryLayout<sockaddr_in>.stride),
                                "AutoFarm",
                                pairingHandle,
                                nil,
                                nil,
                                &adapter,
                                &handshake
                            )
                        }
                    }
                    if retryError == nil {
                        targetIP = altIP
                        DispatchQueue.main.async {
                            AutoFarmSession.shared.deviceIP = altIP
                        }
                        providerError = nil
                    } else {
                        providerError = retryError
                    }
                }
            }
        }

        if let providerError {
            let detail = extractError(providerError)
            idevice_error_free(providerError)
            cleanup()
            lastDetailedError = "\(targetIP): \(detail)"
            return tunnelCreate
        }

        if let remoteServerError = remote_server_connect_rsd(adapter, handshake, &remoteServer) {
            let detail = extractError(remoteServerError)
            idevice_error_free(remoteServerError)
            cleanup()
            lastDetailedError = "RemoteXPC 握手失敗: \(detail)"
            return remoteServerCode
        }
        // 連線成功後儲存更新後的配對資料
        let savePath = pairingPath.isEmpty ? PairingStore.shared.pairingPath : pairingPath
        _ = savePath.withCString { rp_pairing_file_write(pairingHandle, $0) }

        if let simError = location_simulation_new(remoteServer, &locationSimulation) {
            let detail = extractError(simError)
            idevice_error_free(simError)
            cleanup()
            lastDetailedError = "模擬服務建立失敗 (請確認開發者模式): \(detail)"
            return simulationCreate
        }
        // location_simulation_new consumes/owns remote server lifecycle alongside handle
        remoteServer = nil

        if let setError = location_simulation_set(locationSimulation, latitude, longitude) {
            let detail = extractError(setError)
            idevice_error_free(setError)
            cleanup()
            lastDetailedError = "寫入座標失敗: \(detail)"
            return locationSet
        }
        return ok
    }

    private static func clearLocked(pairingPath: String = "", deviceIP: String = "") -> Int32 {
        if let sim = locationSimulation {
            let err = location_simulation_clear(sim)
            cleanup()
            if let err {
                idevice_error_free(err)
                return locationClear
            }
            return ok
        }

        // 若記憶體中無活躍句柄，嘗試透過 DVT 通道重新握手並發送 clear，徹底清除系統 locationd 殘留鎖定
        let actualPairing = !pairingPath.isEmpty ? pairingPath : PairingStore.shared.pairingPath
        let actualIP = !deviceIP.isEmpty ? deviceIP : "10.7.1.1"
        guard !actualPairing.isEmpty, FileManager.default.fileExists(atPath: actualPairing) else {
            return ok
        }

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(49152).bigEndian
        let inetResult = actualIP.withCString { inet_pton(AF_INET, $0, &address.sin_addr) }
        guard inetResult == 1 else { return ok }

        var pairingHandle: OpaquePointer?
        if let pairingError = actualPairing.withCString({ rp_pairing_file_read($0, &pairingHandle) }) {
            idevice_error_free(pairingError)
            return ok
        }
        guard let pairingHandle else { return ok }
        defer { rp_pairing_file_free(pairingHandle) }

        var tempAdapter: OpaquePointer?
        var tempHandshake: OpaquePointer?
        let providerError = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                tunnel_create_rppairing(
                    $0,
                    socklen_t(MemoryLayout<sockaddr_in>.stride),
                    "AutoFarm",
                    pairingHandle,
                    nil,
                    nil,
                    &tempAdapter,
                    &tempHandshake
                )
            }
        }
        guard providerError == nil, let tempAdapter, let tempHandshake else { return ok }

        var tempServer: OpaquePointer?
        if let remoteServerError = remote_server_connect_rsd(tempAdapter, tempHandshake, &tempServer) {
            idevice_error_free(remoteServerError)
            rsd_handshake_free(tempHandshake)
            adapter_free(tempAdapter)
            return ok
        }
        guard let tempServer else {
            rsd_handshake_free(tempHandshake)
            adapter_free(tempAdapter)
            return ok
        }

        var tempSim: OpaquePointer?
        if let simError = location_simulation_new(tempServer, &tempSim) {
            idevice_error_free(simError)
            remote_server_free(tempServer)
            rsd_handshake_free(tempHandshake)
            adapter_free(tempAdapter)
            return ok
        }

        if let tempSim {
            let err = location_simulation_clear(tempSim)
            if let err { idevice_error_free(err) }
            location_simulation_free(tempSim)
        }
        rsd_handshake_free(tempHandshake)
        adapter_free(tempAdapter)
        return ok
    }
}
