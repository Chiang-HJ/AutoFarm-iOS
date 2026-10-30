import SwiftUI
import UIKit
import Photos
import PhotosUI

public struct BlockedMushroomView: View {
    @ObservedObject var manager = BlockedMushroomManager.shared
    @ObservedObject var session = AutoFarmSession.shared
    @ObservedObject var db = SavedDatabaseStore.shared
    @Environment(\.dismiss) var dismiss

    @State private var selectedGroup: String = "主帳號"
    @State private var timerTick: Int = 0

    // 新增/重新命名分組彈窗
    @State private var isAddGroupAlertPresented: Bool = false
    @State private var newGroupNameInput: String = ""

    @State private var isRenameGroupAlertPresented: Bool = false
    @State private var groupToRename: String = ""
    @State private var renameGroupNameInput: String = ""

    // 編輯/新增卡菇彈窗
    @State private var editingItem: BlockedMushroomItem? = nil

    // 相簿選取器
    @State private var isPhotoPickerPresented: Bool = false

    // 截圖跳轉等候回歸自動辨識狀態
    @State private var waitingForScreenshotReturn: Bool = false
    @State private var isOcrProcessing: Bool = false

    private let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    public init() {}

    public var body: some View {
        NavigationView {
            VStack(spacing: 10) {
                // 1. 多帳號水平切換分頁標籤欄
                accountGroupTabs

                // 2. 核心操作按鈕群 (卡菇截圖、相簿辨識、手動新增、匯出清單)
                actionToolbar

                Divider()

                // 3. 卡菇動態倒數清單
                mushroomCardsList
            }
            .padding(.top, 8)
            .navigationTitle("卡菇清單")
            .navigationBarItems(
                leading: Button("關閉") { dismiss() },
                trailing: trailingClearButton
            )
            .sheet(item: $editingItem) { item in
                BlockedMushroomEditSheet(item: item) { saved in
                    if let _ = manager.items.firstIndex(where: { $0.id == saved.id }) {
                        manager.updateItem(saved)
                    } else {
                        manager.addItem(saved)
                    }
                    editingItem = nil
                }
            }
            .sheet(isPresented: $isPhotoPickerPresented) {
                PhotoPickerView { selectedImage in
                    processSelectedScreenshot(selectedImage)
                }
            }
            .onReceive(timer) { _ in
                timerTick += 1
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                handleAppForegroundReturn()
            }
            .onAppear {
                if !manager.groups.contains(selectedGroup) {
                    selectedGroup = manager.groups.first ?? "主帳號"
                }
            }
        }
    }

    // MARK: - 多帳號分頁標籤欄
    private var accountGroupTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(manager.groups, id: \.self) { grp in
                    let isSelected = (grp == selectedGroup)
                    HStack(spacing: 6) {
                        Text(grp)
                            .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                            .foregroundColor(isSelected ? .white : .primary)

                        if isSelected && manager.groups.count > 1 {
                            Menu {
                                Button("重新命名此帳號") {
                                    groupToRename = grp
                                    renameGroupNameInput = grp
                                    isRenameGroupAlertPresented = true
                                }
                                Button("刪除此帳號分頁", role: .destructive) {
                                    manager.deleteGroup(name: grp)
                                    selectedGroup = manager.groups.first ?? "主帳號"
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(isSelected ? Color.blue : Color(UIColor.secondarySystemBackground))
                    .cornerRadius(16)
                    .onTapGesture {
                        selectedGroup = grp
                    }
                }

                // 新增帳號按鈕
                Button(action: {
                    newGroupNameInput = ""
                    isAddGroupAlertPresented = true
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                        Text("新增帳號")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundColor(.blue)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.blue.opacity(0.12))
                    .cornerRadius(16)
                }
            }
            .padding(.horizontal, 16)
        }
        .alert("新增帳號分組", isPresented: $isAddGroupAlertPresented) {
            TextField("例如：小號2", text: $newGroupNameInput)
            Button("確定") {
                if manager.addGroup(name: newGroupNameInput) {
                    selectedGroup = newGroupNameInput.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            Button("取消", role: .cancel) {}
        }
        .alert("重新命名帳號", isPresented: $isRenameGroupAlertPresented) {
            TextField("輸入新名稱", text: $renameGroupNameInput)
            Button("確定") {
                if manager.renameGroup(oldName: groupToRename, newName: renameGroupNameInput) {
                    selectedGroup = renameGroupNameInput.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            Button("取消", role: .cancel) {}
        }
    }

    // MARK: - 核心操作工具列 (對齊安卓一鍵截圖辨識)
    private var actionToolbar: some View {
        HStack(spacing: 8) {
            // 1. 卡菇截圖 (核心主按鈕：直接開啟皮克敏 Bloom，截圖返回自動辨識)
            Button(action: launchPikminForScreenshot) {
                HStack(spacing: 6) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 13))
                    Text(isOcrProcessing ? "正在辨識..." : "卡菇截圖")
                        .font(.system(size: 13, weight: .bold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .disabled(isOcrProcessing)

            // 2. 相簿辨識
            Button(action: { isPhotoPickerPresented = true }) {
                HStack(spacing: 4) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 12))
                    Text("相簿辨識")
                        .font(.system(size: 12, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(Color(UIColor.secondarySystemBackground))
                .foregroundColor(.primary)
                .cornerRadius(10)
            }

            // 3. 手動新增
            Button(action: {
                editingItem = BlockedMushroomItem(
                    groupName: selectedGroup,
                    lat: session.currentLat,
                    lng: session.currentLng
                )
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                    Text("手動")
                        .font(.system(size: 12, weight: .semibold))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .background(Color(UIColor.secondarySystemBackground))
                .foregroundColor(.primary)
                .cornerRadius(10)
            }

            // 4. 匯出清單 (對齊安卓複製卡菇清單至剪貼簿)
            Button(action: exportCurrentGroupList) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 12, weight: .bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .background(Color(UIColor.secondarySystemBackground))
                    .foregroundColor(.primary)
                    .cornerRadius(10)
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - 匯出當前分組清單
    private func exportCurrentGroupList() {
        let items = manager.getItems(for: selectedGroup)
        guard !items.isEmpty else {
            session.showToast("【\(selectedGroup)】目前無任何卡菇紀錄可匯出")
            return
        }

        var lines: [String] = ["=== 【\(selectedGroup)】卡菇清單 ==="]
        for (idx, item) in items.enumerated() {
            let status = item.isFinished() ? "已結束" : "戰鬥中 (\(item.formatRemaining()))"
            let lm = item.landmark.isEmpty ? "" : " - \(item.landmark)"
            lines.append("\(idx + 1). \(item.mushroomType)\(lm) [\(status)] 座標: \(String(format: "%.6f", item.lat)), \(String(format: "%.6f", item.lng))")
        }
        let text = lines.joined(separator: "\n")
        UIPasteboard.general.string = text
        session.showToast("已將【\(selectedGroup)】卡菇清單複製至剪貼簿！")
    }

    // MARK: - 卡菇動態清單
    private var mushroomCardsList: some View {
        let items = manager.getItems(for: selectedGroup)

        return Group {
            if items.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "clock.badge.checkmark")
                        .font(.system(size: 38))
                        .foregroundColor(.secondary.opacity(0.4))
                    Text("【\(selectedGroup)】目前尚無卡菇紀錄")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)
                    Text("點擊上方【卡菇截圖】開啟遊戲，截圖返回後系統將自動純文字 OCR 辨識蘑菇種類、倒數時間與地標。")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(items) { item in
                            mushroomCard(item: item)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                }
            }
        }
    }

    // 單張卡菇卡片
    private func mushroomCard(item: BlockedMushroomItem) -> some View {
        let _ = timerTick // 觸發即時秒級更新
        let isFinished = item.isFinished()

        return VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(item.mushroomType)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.primary)

                        if isFinished {
                            Text("已結束")
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.gray.opacity(0.2))
                                .foregroundColor(.secondary)
                                .cornerRadius(4)
                        } else {
                            Text("戰鬥中")
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.15))
                                .foregroundColor(.green)
                                .cornerRadius(4)
                        }
                    }

                    if !item.landmark.isEmpty {
                        Text(item.landmark)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                // 即時動態倒數時間
                VStack(alignment: .trailing, spacing: 2) {
                    Text(item.formatRemaining())
                        .font(.system(size: 13, weight: .heavy, design: .monospaced))
                        .foregroundColor(isFinished ? .secondary : .orange)

                    Text("結束: \(item.formatFinishTime())")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }

            if !item.note.isEmpty {
                HStack {
                    Text("備註: \(item.note)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }

            Divider()

            // 功能按鈕：瞬移、加常用、複製、編輯、刪除
            HStack(spacing: 8) {
                Text("\(String(format: "%.5f", item.lat)), \(String(format: "%.5f", item.lng))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)

                Spacer()

                // 瞬移至該蘑菇座標
                Button(action: {
                    session.teleport(to: item.lat, lng: item.lng, label: item.mushroomType)
                    session.showToast("已瞬移至【\(item.mushroomType)】")
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: "location.fill")
                        Text("瞬移")
                    }
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.blue)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.blue.opacity(0.12))
                    .cornerRadius(6)
                }

                // 儲存至常用地點
                Button(action: {
                    let label = item.landmark.isEmpty ? item.mushroomType : "\(item.landmark) (\(item.mushroomType))"
                    db.addLocation(name: label, latitude: item.lat, longitude: item.lng)
                    session.showToast("已加入常用座標庫")
                }) {
                    Image(systemName: "bookmark")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .padding(6)
                        .background(Color(UIColor.secondarySystemBackground))
                        .clipShape(Circle())
                }

                // 複製座標
                Button(action: {
                    UIPasteboard.general.string = "\(item.lat), \(item.lng)"
                    session.showToast("已複製卡菇座標")
                }) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .padding(6)
                        .background(Color(UIColor.secondarySystemBackground))
                        .clipShape(Circle())
                }

                // 編輯
                Button(action: {
                    editingItem = item
                }) {
                    Image(systemName: "pencil")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .padding(6)
                        .background(Color(UIColor.secondarySystemBackground))
                        .clipShape(Circle())
                }

                // 刪除
                Button(action: {
                    manager.deleteItem(id: item.id)
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundColor(.red.opacity(0.8))
                        .padding(6)
                        .background(Color.red.opacity(0.1))
                        .clipShape(Circle())
                }
            }
        }
        .padding(12)
        .background(Color(UIColor.secondarySystemBackground).opacity(0.75))
        .cornerRadius(12)
    }

    private var trailingClearButton: some View {
        Button(action: {
            manager.clearFinished(for: selectedGroup)
            session.showToast("已清除【\(selectedGroup)】結束項目")
        }) {
            Text("清除已結束")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - 跳轉皮克敏 Bloom (精準調用官方 URL Scheme)
    private func launchPikminForScreenshot() {
        let schemes = [
            "pikminbloom://",
            "com.nianticlabs.pikmin://"
        ]

        var launched = false
        for s in schemes {
            if let url = URL(string: s), UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
                launched = true
                break
            }
        }

        if launched {
            self.waitingForScreenshotReturn = true
            session.showToast("已開啟皮克敏 Bloom，請在蘑菇畫面截圖後切回 AutoFarm")
        } else {
            session.showToast("未偵測到皮克敏 Bloom，請手動切換至遊戲")
            self.waitingForScreenshotReturn = true
        }
    }

    // MARK: - 前景回歸自動偵測最新相簿截圖
    private func handleAppForegroundReturn() {
        guard waitingForScreenshotReturn else { return }
        self.waitingForScreenshotReturn = false
        self.isOcrProcessing = true

        PHPhotoLibrary.requestAuthorization { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async {
                    self.isOcrProcessing = false
                    self.session.showToast("未取得相簿權限，請手動點選相簿辨識")
                }
                return
            }

            let fetchOptions = PHFetchOptions()
            fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            fetchOptions.fetchLimit = 1

            let fetchResult = PHAsset.fetchAssets(with: .image, options: fetchOptions)
            guard let firstAsset = fetchResult.firstObject else {
                DispatchQueue.main.async {
                    self.isOcrProcessing = false
                }
                return
            }

            // 確保該相片是在過去 5 分鐘內建立的截圖
            if let createDate = firstAsset.creationDate, Date().timeIntervalSince(createDate) < 300 {
                let imageManager = PHImageManager.default()
                let reqOpt = PHImageRequestOptions()
                reqOpt.isSynchronous = false
                reqOpt.deliveryMode = .highQualityFormat

                imageManager.requestImage(for: firstAsset, targetSize: CGSize(width: 1080, height: 1920), contentMode: .aspectFit, options: reqOpt) { image, _ in
                    DispatchQueue.main.async {
                        self.isOcrProcessing = false
                        if let img = image {
                            self.processSelectedScreenshot(img)
                        }
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self.isOcrProcessing = false
                }
            }
        }
    }

    // MARK: - 調用純文字 OCR 解析截圖
    private func processSelectedScreenshot(_ image: UIImage) {
        self.isOcrProcessing = true

        MushroomOcrEngine.recognize(image: image) { result in
            DispatchQueue.main.async {
                self.isOcrProcessing = false

                let currentLat = session.currentLat
                let currentLng = session.currentLng
                let nowMs = Int64(Date().timeIntervalSince1970 * 1000)

                let newItem = BlockedMushroomItem(
                    groupName: selectedGroup,
                    mushroomType: result.mushroomName,
                    landmark: result.landmark,
                    lat: currentLat,
                    lng: currentLng,
                    capturedTimestamp: nowMs,
                    remainingMillisAtCapture: result.totalMillis,
                    targetFinishTimestamp: nowMs + result.totalMillis,
                    note: ""
                )

                self.editingItem = newItem
                session.showToast("已完成文字 OCR 辨識，請確認卡菇資料")
            }
        }
    }
}

// MARK: - 卡菇編輯彈窗 (對齊安卓 BlockedMushroomEditDialog.kt)
public struct BlockedMushroomEditSheet: View {
    @State private var item: BlockedMushroomItem
    let onSave: (BlockedMushroomItem) -> Void
    @Environment(\.dismiss) var dismiss

    @State private var inputDays: Int = 0
    @State private var inputHours: Int = 0
    @State private var inputMinutes: Int = 0
    @State private var inputSeconds: Int = 0
    @State private var latString: String = ""
    @State private var lngString: String = ""

    public init(item: BlockedMushroomItem, onSave: @escaping (BlockedMushroomItem) -> Void) {
        self._item = State(initialValue: item)
        self.onSave = onSave
    }

    public var body: some View {
        NavigationView {
            Form {
                Section(header: Text("基本資料")) {
                    TextField("蘑菇種類 (例：巨大活動蘑菇、大火蘑菇)", text: $item.mushroomType)
                    TextField("地標名稱 (例：大安森林公園溜冰場)", text: $item.landmark)
                }

                Section(header: Text("剩餘倒數時間")) {
                    HStack {
                        Stepper("天: \(inputDays)", value: $inputDays, in: 0...30)
                    }
                    HStack {
                        Stepper("小時: \(inputHours)", value: $inputHours, in: 0...23)
                    }
                    HStack {
                        Stepper("分鐘: \(inputMinutes)", value: $inputMinutes, in: 0...59)
                    }
                    HStack {
                        Stepper("秒數: \(inputSeconds)", value: $inputSeconds, in: 0...59)
                    }
                }

                Section(header: Text("GPS 座標")) {
                    TextField("緯度 (Latitude)", text: $latString)
                        .keyboardType(.numbersAndPunctuation)
                    TextField("經度 (Longitude)", text: $lngString)
                        .keyboardType(.numbersAndPunctuation)
                }

                Section(header: Text("備註")) {
                    TextField("例如：主帳已進、等小號", text: $item.note)
                }

                Section {
                    Button(action: saveAction) {
                        HStack {
                            Spacer()
                            Text("儲存卡菇資料")
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                            Spacer()
                        }
                    }
                    .listRowBackground(Color.blue)
                }
            }
            .navigationTitle("編輯卡菇")
            .navigationBarItems(leading: Button("取消") { dismiss() })
            .onAppear(perform: setupInitialInputs)
        }
    }

    private func setupInitialInputs() {
        let sec = item.getRemainingSeconds()
        inputDays = Int(sec / 86400)
        inputHours = Int((sec % 86400) / 3600)
        inputMinutes = Int((sec % 3600) / 60)
        inputSeconds = Int(sec % 60)
        latString = String(format: "%.6f", item.lat)
        lngString = String(format: "%.6f", item.lng)
    }

    private func saveAction() {
        if let lat = Double(latString), let lng = Double(lngString) {
            item.lat = lat
            item.lng = lng
        }
        let totalSec = Int64(inputDays) * 86400 + Int64(inputHours) * 3600 + Int64(inputMinutes) * 60 + Int64(inputSeconds)
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        item.remainingMillisAtCapture = totalSec * 1000
        item.targetFinishTimestamp = nowMs + item.remainingMillisAtCapture
        onSave(item)
        dismiss()
    }
}

// MARK: - 相簿照片選取器 Representable
public struct PhotoPickerView: UIViewControllerRepresentable {
    let onImageSelected: (UIImage) -> Void
    @Environment(\.presentationMode) var presentationMode

    public func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    public func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoPickerView

        init(_ parent: PhotoPickerView) {
            self.parent = parent
        }

        public func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.presentationMode.wrappedValue.dismiss()
            guard let provider = results.first?.itemProvider, provider.canLoadObject(ofClass: UIImage.self) else { return }

            provider.loadObject(ofClass: UIImage.self) { image, _ in
                if let uiImage = image as? UIImage {
                    DispatchQueue.main.async {
                        self.parent.onImageSelected(uiImage)
                    }
                }
            }
        }
    }
}
