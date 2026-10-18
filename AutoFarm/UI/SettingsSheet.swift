import SwiftUI

public struct SettingsSheet: View {
    @ObservedObject var session = AutoFarmSession.shared
    @Environment(\.dismiss) var dismiss

    @State private var isTesting: Bool = false
    @State private var testResultText: String? = nil
    @State private var isSuccess: Bool = false

    public init() {}

    public var body: some View {
        NavigationView {
            Form {
                Section(header: Text("本機迴圈通道 (LocalDevVPN)")) {
                    HStack {
                        Text("Tunnel IP")
                        Spacer()
                        TextField("10.7.0.1", text: $session.deviceIP)
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

                Section(header: Text("調試憑證狀態")) {
                    HStack {
                        Image(systemName: "checkmark.shield.fill")
                            .foregroundColor(.green)
                        Text("免電腦本機 RemotePairing 金鑰")
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                        Text("已就緒")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                    Text("本版已全面在系統底層自動管理調試金鑰，免除手動匯入或從電腦複製 plist 的困擾。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section(header: Text("免越獄使用說明")) {
                    Text("1. iPhone 必須開啟「開發者模式」（設定 → 隱私權與安全性 → 最下方開發者模式）。\n2. 連接 LocalDevVPN (10.7.0.1) 本機迴圈。\n3. 通道握手完成後，即可隨時在單機獨立修改系統定位與巡航。")
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
