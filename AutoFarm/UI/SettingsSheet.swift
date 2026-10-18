import SwiftUI

public struct SettingsSheet: View {
    @ObservedObject var session = AutoFarmSession.shared
    @ObservedObject var pairingMgr = RemotePairingManager.shared
    @Environment(\.dismiss) var dismiss

    @State private var isTesting: Bool = false
    @State private var testResultText: String? = nil
    @State private var isSuccess: Bool = false

    public init() {}

    public var body: some View {
        NavigationView {
            Form {
                Section(header: Text("手機免電腦配對認證 (解決 Connection Reset 54)")) {
                    VStack(alignment: .leading, spacing: 10) {
                        Button(action: {
                            pairingMgr.startPairing()
                        }) {
                            HStack {
                                Image(systemName: "key.fill")
                                Text(pairingMgr.isPairing ? "正在等待系統配對..." : "開始手機配對 (生成 6 位數碼)")
                                    .fontWeight(.bold)
                                Spacer()
                                if pairingMgr.isPairing {
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(pairingMgr.isPairing)

                        if let pin = pairingMgr.pairingPin {
                            VStack(spacing: 4) {
                                Text("一次性配對驗證碼")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.secondary)
                                Text(pin)
                                    .font(.system(size: 32, weight: .heavy, design: .monospaced))
                                    .foregroundColor(.blue)
                                    .tracking(6)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color.blue.opacity(0.08))
                            .cornerRadius(10)
                        }

                        if let status = pairingMgr.statusMessage {
                            Text(status)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(pairingMgr.isSuccess ? .green : (pairingMgr.isPairing ? .orange : .red))
                        }

                        Text("配對流程（只需做一次，永久信任）：\n1. 確認手機連上 Wi-Fi，且已開啟「開發者模式」。\n2. 點擊【開始手機配對】，記下畫面上的 6 位數配對碼。\n3. 前往 iPhone「設定 → 隱私權與安全性 → 開發者模式」，點選 AutoFarm 並輸入這組配對碼。\n4. 配對完成後回到 AutoFarm，再點下方【測試通道握手】即可順暢連線！")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Section(header: Text("本機迴圈通道 (LocalDevVPN)")) {
                    HStack {
                        Text("Tunnel IP")
                        Spacer()
                        TextField("10.7.1.1", text: $session.deviceIP)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 120)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Button(action: runHandshakeTest) {
                            HStack {
                                Image(systemName: "antenna.radiowaves.left.and.right")
                                Text(isTesting ? "正在建立連線握手..." : "測試通道握手 (準備連線)")
                                    .fontWeight(.bold)
                                Spacer()
                                if isTesting {
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(isTesting)

                        if let res = testResultText {
                            Text(res)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(isSuccess ? .green : .red)
                                .padding(.vertical, 4)
                        }
                    }

                    Text("4G 行動網路免 Wi-Fi 巡航 SOP（FreeWay 驗收秘訣）：\n1. 確認 LocalDevVPN 已連線 (Connect)。\n2. 下拉手機控制中心，暫時點一下關閉「行動數據」（或連著 Wi-Fi）。\n3. 點擊上方【測試通道握手 (準備連線)】。\n4. 握手成功後，立刻開回行動數據，即可全程使用 4G 行動網路正常巡邏打怪！")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section(header: Text("免越獄使用說明")) {
                    Text("1. iPhone 必須開啟「開發者模式」（設定 → 隱私權與安全性 → 最下方開發者模式）。\n2. 連接 LocalDevVPN (10.7.1.1) 本機迴圈。\n3. 通道握手完成後，即可隨時在單機獨立修改系統定位與巡航。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("連線設定")
            .navigationBarItems(trailing: Button("完成") { dismiss() })
        }
    }

    private func runHandshakeTest() {
        isTesting = true
        testResultText = nil

        let pPath = session.pairingFilePath.isEmpty ? PairingStore.shared.pairingPath : session.pairingFilePath
        let result = LocationEngine.set(
            latitude: session.currentLat,
            longitude: session.currentLng,
            pairingPath: pPath,
            deviceIP: session.deviceIP
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.isTesting = false
            switch result {
            case .success:
                self.isSuccess = true
                self.testResultText = "通道握手成功！底層調試服務已就緒，可開回行動數據開始巡航。"
                session.isSimulatingLocation = true
            case .failure(let err):
                self.isSuccess = false
                self.testResultText = "握手未成功: \(err.localizedDescription)"
                session.isSimulatingLocation = false
            }
        }
    }
}
