import SwiftUI

public struct SettingsSheet: View {
    @ObservedObject var session = AutoFarmSession.shared
    @ObservedObject var pairService = PairOnDeviceService.shared
    @ObservedObject var pairingStore = PairingStore.shared
    @Environment(\.dismiss) var dismiss

    @State private var isTesting: Bool = false
    @State private var testResultText: String? = nil
    @State private var isSuccess: Bool = false

    public init() {}

    public var body: some View {
        NavigationView {
            Form {
                Section(header: Text("手機免電腦配對認證 (解決 Connection Reset 54)")) {
                    VStack(alignment: .leading, spacing: 12) {
                        switch pairService.phase {
                        case .idle:
                            if pairingStore.hasPairingFile {
                                HStack {
                                    Image(systemName: "checkmark.seal.fill")
                                        .foregroundColor(.green)
                                    Text("已存在信任憑證文件")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.green)
                                }
                            }

                            Button(action: {
                                pairService.start(pairingStore: pairingStore)
                            }) {
                                HStack {
                                    Image(systemName: "key.fill")
                                    Text(pairingStore.hasPairingFile ? "重新進行手機配對" : "開始手機免電腦配對")
                                        .fontWeight(.bold)
                                }
                            }

                        case .advertising:
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    ProgressView()
                                        .padding(.trailing, 4)
                                    Text("正在區域網路廣播等候 iPhone 連線...")
                                        .font(.headline)
                                        .foregroundColor(.orange)
                                }

                                Text("重要提醒：請不要停在此畫面等待！\n請立刻切換至 iPhone「設定 → 隱私權與安全性 → 開發者模式」，在下方配對裝置點選【AutoFarm】並輸入手機密碼。點選後 6 位數碼才會即時生成！")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                                    .padding(8)
                                    .background(Color.orange.opacity(0.12))
                                    .cornerRadius(8)

                                Button("取消配對廣播") {
                                    pairService.resetToIdle()
                                }
                                .font(.footnote)
                                .foregroundColor(.red)
                            }

                        case .deviceConnected:
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    ProgressView()
                                    Text("已偵測到 iPhone 開發者連線，正在生成驗證碼...")
                                        .font(.subheadline)
                                        .foregroundColor(.blue)
                                }
                            }

                        case .awaitingPIN(let pin):
                            VStack(spacing: 6) {
                                Text("請在 iPhone 彈出的「配對要求」中輸入：")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.primary)

                                Text(pin)
                                    .font(.system(size: 38, weight: .heavy, design: .monospaced))
                                    .foregroundColor(.blue)
                                    .tracking(8)

                                Text("（頂部橫幅通知亦已送達此驗證碼）")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(12)

                        case .succeeded:
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                    Text("手機免電腦配對成功！")
                                        .font(.headline)
                                        .foregroundColor(.green)
                                }

                                Text("已成功在設備本機建立 RPPairing 信任證書。請開啟 LocalDevVPN 並點擊下方【測試通道握手】。")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                Button("重新配對") {
                                    pairService.resetToIdle()
                                }
                                .font(.footnote)
                            }

                        case .failed(let err):
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.red)
                                    Text("配對未完成")
                                        .font(.headline)
                                        .foregroundColor(.red)
                                }

                                Text(err)
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                Button("重試配對") {
                                    pairService.acknowledgeFailure()
                                }
                                .font(.footnote)
                            }
                        }

                        Divider()

                        Text("配對標準步驟（只需做一次，永久信任）：\n1. 確認手機連上 Wi-Fi，且已開啟「開發者模式」。\n2. 點擊上方【開始手機免電腦配對】。\n3. 切換至 iPhone「設定 → 隱私權與安全性 → 開發者模式」。\n4. 在最下方配對裝置點選【AutoFarm】，輸入手機螢幕鎖定密碼。\n5. 螢幕頂部通知（或切回此處）會顯示「6 位數驗證碼」，在系統框輸入該碼即完成配對！\n6. 配對完成後，連上 LocalDevVPN 即可暢通連線！")
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

                    Text("4G 行動網路免 Wi-Fi 巡航 SOP（FreeWay 驗收秘訣）：\n1. 確認 LocalDevVPN 已連線 (Connect)。\n2. 下拉手機控制中心，暫時點一下關閉「行動數據」（或連著 Wi-Fi）。\n3. 點擊上方【測試通道握手 (準備連線)】。\n4. 握手成功後，立刻開回行動數據，即可全程使用 4G 行動網路正常巡航打怪！")
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
