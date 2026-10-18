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

                    Button(action: { isDocumentPickerPresented = true }) {
                        HStack {
                            Image(systemName: "doc.badge.plus")
                            Text("從「檔案」匯入配對憑證 (.plist)")
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
                    Text("預設為 10.7.0.1。請確保 LocalDevVPN 已連線，方可建立底層調試通訊通道。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section(header: Text("免越獄使用說明")) {
                    Text("1. iPhone 必須開啟「開發者模式」（設定 → 隱私權與安全性 → 開發者模式）。\n2. 匯入透過電腦生成的 pairing plist 憑證。\n3. 連接 LocalDevVPN 後，即可免電腦獨立修改系統定位。")
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
