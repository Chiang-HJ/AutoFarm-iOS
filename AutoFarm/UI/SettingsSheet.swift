import SwiftUI
import UniformTypeIdentifiers

public struct SettingsSheet: View {
    @ObservedObject var session = AutoFarmSession.shared
    @Environment(\.dismiss) var dismiss

    @State private var isDocumentPickerPresented: Bool = false
    @State private var pairingList: [URL] = []

    public init() {}

    public var body: some View {
        NavigationView {
            Form {
                Section(header: Text("配對憑證 (Pairing File)")) {
                    if pairingList.isEmpty {
                        Text("尚未匯入配對憑證 (RPPairing)")
                            .font(.subheadline)
                            .foregroundColor(.orange)
                    } else {
                        ForEach(pairingList, id: \.self) { url in
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(session.pairingFilePath == url.path ? .green : .gray)
                                VStack(alignment: .leading) {
                                    Text(url.lastPathComponent)
                                        .font(.system(size: 13, weight: .medium))
                                    Text(url.path)
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                if session.pairingFilePath == url.path {
                                    Text("使用中")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                session.pairingFilePath = url.path
                            }
                        }
                    }

                    Button(action: {
                        if let newUrl = PairingStore.shared.generateNewRemotePairing() {
                            session.pairingFilePath = newUrl.path
                            loadPairings()
                        }
                    }) {
                        HStack {
                            Image(systemName: "key.fill")
                            Text("免電腦一鍵生成/重設本機配對憑證")
                        }
                    }

                    Button(action: { isDocumentPickerPresented = true }) {
                        HStack {
                            Image(systemName: "doc.badge.plus")
                            Text("從「檔案」手動匯入憑證 (.plist)")
                        }
                    }
                }

                Section(header: Text("本機迴圈通道 (LocalDevVPN)")) {
                    HStack {
                        Text("Tunnel IP")
                        Spacer()
                        TextField("10.7.0.1", text: $session.deviceIP)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 120)
                    }

                    Button(action: { session.prepareConnection() }) {
                        HStack {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                            Text("測試通道握手 (準備連線)")
                                .fontWeight(.bold)
                        }
                    }

                    Text("4G 行動網路免 Wi-Fi 巡航 SOP（FreeWay 驗收秘訣）：\n1. 確認 LocalDevVPN 已連線 (Connect)。\n2. 下拉手機控制中心，暫時點一下關閉「行動數據」（或連著 Wi-Fi）。\n3. 點擊上方【測試通道握手 (準備連線)】。\n4. 握手成功後，立刻開回行動數據，即可全程使用 4G 行動網路正常巡邏打怪！")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section(header: Text("免越獄使用說明")) {
                    Text("1. iPhone 必須開啟「開發者模式」（設定 → 隱私權與安全性 → 最下方開發者模式）。\n2. 本版已支援免電腦自動生成 RemotePairing 配對金鑰。\n3. 連接 LocalDevVPN 後，完成握手即可獨立修改系統定位。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("設定與配對")
            .navigationBarItems(trailing: Button("完成") { dismiss() })
            .onAppear(perform: loadPairings)
            .sheet(isPresented: $isDocumentPickerPresented) {
                DocumentPickerView { url in
                    if let savedUrl = try? PairingStore.savePairing(from: url) {
                        session.pairingFilePath = savedUrl.path
                        loadPairings()
                    }
                }
            }
        }
    }

    private func loadPairings() {
        self.pairingList = PairingStore.availablePairings()
        if session.pairingFilePath.isEmpty, let first = pairingList.first {
            session.pairingFilePath = first.path
        }
    }
}

struct DocumentPickerView: UIViewControllerRepresentable {
    var onPick: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.data, .propertyList], asCopy: true)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        var parent: DocumentPickerView

        init(_ parent: DocumentPickerView) {
            self.parent = parent
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if let first = urls.first {
                parent.onPick(first)
            }
        }
    }
}
