import SwiftUI
import CoreLocation

public enum MushroomSortType: String, CaseIterable, Identifiable {
    case timeAsc = "即將結束 (剩餘時間少到多)"
    case timeDesc = "結束時間 (剩餘時間多到少)"
    case powerDesc = "戰力 (高到低)"
    case powerAsc = "戰力 (低到高)"
    case latest = "最新探測 (新到舊)"

    public var id: String { rawValue }
}

public struct MushroomRadarView: View {
    @ObservedObject var radar = MushroomRadarManager.shared
    @ObservedObject var session = AutoFarmSession.shared
    @Environment(\.dismiss) var dismiss

    // 定時 1 秒刷新畫面動態計算血量與倒數
    @State private var tickDate: Date = Date()
    @State private var timerSubscription: Timer? = nil

    // 搜尋與篩選條件 (使用 @AppStorage 持久化記憶上次選擇)
    @State private var searchQuery: String = ""
    @AppStorage("pref_radar_category") private var selectedCategory: String = "ALL"
    @AppStorage("pref_radar_size") private var selectedSize: String = "ALL"
    @AppStorage("pref_radar_status") private var selectedStatus: String = "ALL"
    @AppStorage("pref_radar_sort") private var selectedSortRaw: String = MushroomSortType.timeAsc.rawValue
    @AppStorage("pref_radar_show_pinned_only") private var showPinnedOnly: Bool = false

    // 分享/下載卡菇清單檔案 Sheet
    @State private var shareFileUrl: URL? = nil
    @State private var isSharePresented: Bool = false

    public init() {}

    private var selectedSort: MushroomSortType {
        MushroomSortType(rawValue: selectedSortRaw) ?? .timeAsc
    }

    public var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // 頂部搜尋列與功能按鈕
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                            .font(.system(size: 13))
                        TextField("搜尋地標名稱...", text: $searchQuery)
                            .font(.system(size: 13))
                        if !searchQuery.isEmpty {
                            Button(action: { searchQuery = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                                    .font(.system(size: 12))
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(10)

                    // 重新整理雲端數據按鈕
                    Button(action: {
                        radar.fetchMushrooms { count in
                            session.toastMessage = "已從雲端同步 \(count) 顆蘑菇！"
                        }
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.blue)
                            .frame(width: 34, height: 34)
                            .background(Color.blue.opacity(0.12))
                            .clipShape(Circle())
                    }

                    // 下載卡菇清單按鈕
                    Button(action: downloadPinnedMushrooms) {
                        HStack(spacing: 3) {
                            Image(systemName: "square.and.arrow.down.fill")
                            Text("下載卡菇")
                        }
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 7)
                        .background(Color(red: 0.9, green: 0.45, blue: 0.0))
                        .cornerRadius(8)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)

                // 篩選維度列 (種類 / 大小 / 狀態 / 排序)
                filterScrollView

                Divider()

                // 蘑菇卡片清單
                let list = filteredMushrooms
                if list.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "circle.grid.hex.fill")
                            .font(.system(size: 44))
                            .foregroundColor(.secondary.opacity(0.4))
                        Text(showPinnedOnly ? "目前尚未釘選任何卡菇。\n請點擊蘑菇卡片上的釘選圖示將其加入！" :
                             (radar.activeMushrooms.isEmpty ? "目前尚未同步到蘑菇數據。\n請點擊右上角重新整理從雲端拉取！" : "無符合篩選條件的蘑菇。\n請調整上方篩選條件。"))
                            .font(.system(size: 13))
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(list) { m in
                                mushroomCard(m: m)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                }
            }
            .navigationTitle("蘑菇雷達 (\(filteredMushrooms.count) / \(radar.activeMushrooms.count))")
            .navigationBarItems(leading: Button("關閉") { dismiss() })
            .sheet(isPresented: $isSharePresented) {
                if let url = shareFileUrl {
                    ActivityView(activityItems: [url])
                }
            }
            .onAppear {
                radar.fetchMushrooms()
                radar.startPolling()
                timerSubscription = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                    tickDate = Date()
                }
            }
            .onDisappear {
                radar.stopPolling()
                timerSubscription?.invalidate()
                timerSubscription = nil
            }
        }
    }

    // MARK: - 篩選水平滾動條
    private var filterScrollView: some View {
        VStack(spacing: 6) {
            // 第 1 列: 卡菇專屬切換 + 種類
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    // 卡菇切換 Chip
                    Button(action: {
                        showPinnedOnly.toggle()
                    }) {
                        HStack(spacing: 3) {
                            Image(systemName: showPinnedOnly ? "pin.fill" : "pin")
                            Text("卡菇 (\(radar.pinnedKeys.count))")
                        }
                        .font(.system(size: 11, weight: showPinnedOnly ? .bold : .medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(showPinnedOnly ? Color(red: 0.95, green: 0.5, blue: 0.0) : Color(UIColor.secondarySystemBackground))
                        .foregroundColor(showPinnedOnly ? .white : .primary)
                        .cornerRadius(6)
                    }

                    Text("種類:")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary)

                    let categories = [("ALL", "全部"), ("活動", "活動"), ("特殊", "特殊"), ("一般", "一般")]
                    ForEach(categories, id: \.0) { cat in
                        filterChip(title: cat.1, isSelected: selectedCategory == cat.0) {
                            selectedCategory = cat.0
                        }
                    }
                }
                .padding(.horizontal)
            }

            // 第 2 列: 大小與狀態
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    Text("大小:")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary)

                    let sizes = [("ALL", "全部"), ("巨大", "巨大"), ("大", "大"), ("一般", "一般"), ("小", "小")]
                    ForEach(sizes, id: \.0) { s in
                        filterChip(title: s.1, isSelected: selectedSize == s.0) {
                            selectedSize = s.0
                        }
                    }

                    Spacer().frame(width: 6)

                    Text("車位:")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary)

                    let statuses = [("ALL", "全部"), ("空菇", "空菇 (0人)"), ("未滿", "未滿 (<5人)"), ("已滿", "已滿 (>=5人)")]
                    ForEach(statuses, id: \.0) { st in
                        filterChip(title: st.1, isSelected: selectedStatus == st.0) {
                            selectedStatus = st.0
                        }
                    }
                }
                .padding(.horizontal)
            }

            // 第 3 列: 排序選單
            HStack {
                Menu {
                    ForEach(MushroomSortType.allCases) { opt in
                        Button(action: {
                            selectedSortRaw = opt.rawValue
                        }) {
                            HStack {
                                Text(opt.rawValue)
                                if selectedSort == opt {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.arrow.down")
                        Text(selectedSort.rawValue)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10))
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(6)
                }

                Spacer()

                Text("符合: \(filteredMushrooms.count) / 總計: \(radar.activeMushrooms.count)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .padding(.bottom, 4)
        }
    }

    private func filterChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: isSelected ? .bold : .regular))
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(isSelected ? Color.blue : Color(UIColor.secondarySystemBackground))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(5)
        }
    }

    // MARK: - 蘑菇卡片視圖
    private func mushroomCard(m: MushroomItem) -> some View {
        let nowMs = Int64(tickDate.timeIntervalSince1970 * 1000)
        let dynamicHp = m.getDynamicCurrentHp(nowMs: nowMs)
        let ratio = m.dynamicHpRatio(nowMs: nowMs)
        let slotsLeft = max(0, m.maxChallengers - m.challengerCount)
        let power = m.getEffectiveBattlePower(nowMs: nowMs)
        let isPinned = radar.isPinned(key: m.key)

        return VStack(alignment: .leading, spacing: 6) {
            // 第一列: 地標名稱、卡菇標記、種類標籤
            HStack {
                if isPinned {
                    Text("卡菇")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color(red: 0.95, green: 0.5, blue: 0.0))
                        .cornerRadius(3)
                }

                Text(m.name)
                    .font(.system(size: 14, weight: .bold))
                    .lineLimit(1)
                    .foregroundColor(.primary)

                Spacer()

                // 種類屬性膠囊
                Text(m.challengeTypeName)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(getBadgeColor(type: m.challengeType))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(getBadgeColor(type: m.challengeType).opacity(0.15))
                    .cornerRadius(4)
            }

            // 第二列: 即時扣減動態血量條
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("HP: \(dynamicHp) / \(m.totalHp)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    Spacer()
                    Text(String(format: "%.1f%%", ratio * 100.0))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(ratio < 0.3 ? .red : .blue)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 6)

                        RoundedRectangle(cornerRadius: 3)
                            .fill(getBadgeColor(type: m.challengeType))
                            .frame(width: max(0, min(geo.size.width, geo.size.width * CGFloat(ratio))), height: 6)
                    }
                }
                .frame(height: 6)
            }

            // 第三列: 車位狀況與當前戰力
            HStack {
                HStack(spacing: 3) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 11))
                        .foregroundColor(m.challengerCount >= m.maxChallengers ? .red : (m.challengerCount > 0 ? .orange : .green))
                    Text(m.challengerCount >= m.maxChallengers ? "車位: \(m.challengerCount)/\(m.maxChallengers) (已滿)" :
                         (m.challengerCount > 0 ? "車位: \(m.challengerCount)/\(m.maxChallengers) (剩 \(slotsLeft) 位)" : "空菇: 0人"))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(m.challengerCount >= m.maxChallengers ? .red : (m.challengerCount > 0 ? .orange : .green))
                }

                Spacer()

                HStack(spacing: 2) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 10))
                        .foregroundColor(power > 0 ? .orange : .secondary)
                    Text(power > 0 ? "戰力: \(power)" : "戰力: -")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(power > 0 ? .orange : .secondary)
                }
            }

            // 第四列: 倒數時間、座標、操作按鈕 (卡菇釘選、瞬移、快速複製)
            HStack {
                // 剩餘倒數
                if let ft = m.finishTimeMs, ft > 0 {
                    let remSec = max(0, (ft - nowMs) / 1000)
                    HStack(spacing: 3) {
                        Image(systemName: "timer")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Text(remSec > 0 ? "預計擊破: \(formatDuration(seconds: remSec))" : "已擊破")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(remSec > 0 ? .blue : .red)
                    }
                } else {
                    Text("野生未開打")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }

                Spacer()

                // 經緯度
                Text(String(format: "%.5f, %.5f", m.latitude, m.longitude))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)

                // 卡菇釘選按鈕
                Button(action: {
                    radar.togglePin(key: m.key)
                }) {
                    Image(systemName: isPinned ? "pin.fill" : "pin")
                        .font(.system(size: 13))
                        .foregroundColor(isPinned ? Color(red: 0.95, green: 0.5, blue: 0.0) : .secondary)
                        .padding(4)
                }
                .buttonStyle(BorderlessButtonStyle())

                // 瞬移前往
                Button(action: {
                    session.teleport(to: m.latitude, lng: m.longitude, label: m.name)
                    session.toastMessage = "已瞬移至蘑菇: \(m.name)"
                }) {
                    Text("瞬移")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.blue)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.blue.opacity(0.12))
                        .cornerRadius(4)
                }
                .buttonStyle(BorderlessButtonStyle())

                // 快速複製 (格式: 種類 -剩餘車位 緯度,經度)
                Button(action: {
                    let latStr = String(format: "%.6f", m.latitude)
                    let lngStr = String(format: "%.6f", m.longitude)
                    let copyText = "\(m.challengeTypeName) -\(slotsLeft) \(latStr),\(lngStr)"
                    UIPasteboard.general.string = copyText
                    session.toastMessage = "已複製蘑菇座標至剪貼簿！"
                }) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .padding(4)
                }
                .buttonStyle(BorderlessButtonStyle())
            }
        }
        .padding(10)
        .background(isPinned ? Color(red: 1.0, green: 0.97, blue: 0.9) : Color(UIColor.secondarySystemBackground).opacity(0.6))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isPinned ? Color(red: 0.95, green: 0.6, blue: 0.0) : Color.clear, lineWidth: 1.5)
        )
    }

    // MARK: - 下載卡菇清單 (格式: 蘑菇種類 + 預計結束時間 + 經緯度)
    private func downloadPinnedMushrooms() {
        let content = radar.exportPinnedMushroomsText()
        if content.isEmpty {
            session.toastMessage = "目前尚未釘選任何卡菇，請先在卡片點擊釘選！"
            return
        }

        // 複製到剪貼簿
        UIPasteboard.general.string = content

        // 產生檔案並呼叫系統分享
        if let fileUrl = radar.exportPinnedMushroomsFile() {
            self.shareFileUrl = fileUrl
            self.isSharePresented = true
            session.toastMessage = "已產生卡菇清單檔案並複製至剪貼簿！"
        } else {
            session.toastMessage = "已將 \(radar.pinnedKeys.count) 筆卡菇資訊複製至剪貼簿！"
        }
    }

    // MARK: - 篩選與排序計算
    private var filteredMushrooms: [MushroomItem] {
        let nowMs = Int64(tickDate.timeIntervalSince1970 * 1000)
        var list = radar.activeMushrooms.values.filter { m in
            // 0. 過期自動排除
            if m.isExpired(nowMs: nowMs) { return false }

            // 1. 卡菇專屬
            if showPinnedOnly && !radar.pinnedKeys.contains(m.key) { return false }

            // 2. 搜尋關鍵字
            if !searchQuery.isEmpty && !m.name.localizedCaseInsensitiveContains(searchQuery) {
                return false
            }

            // 3. 種類
            if selectedCategory != "ALL" {
                let isEvent = m.challengeCategory == "活動" || m.challengeType == 10 || m.challengeTypeName.contains("活動") || m.challengeTypeName.contains("萬聖節")
                let isSpecial = m.challengeCategory == "特殊" || (m.challengeType >= 11 && m.challengeType <= 18)
                let isNormal = m.challengeCategory == "一般" || (m.challengeType >= 1 && m.challengeType <= 9) || m.challengeType == 26
                let match = (selectedCategory == "活動" && isEvent) || (selectedCategory == "特殊" && isSpecial) || (selectedCategory == "一般" && isNormal)
                if !match { return false }
            }

            // 4. 大小
            if selectedSize != "ALL" {
                let match = (selectedSize == "巨大" && (m.challengeLevel == 4 || m.challengeTypeName.contains("巨大"))) ||
                            (selectedSize == "大" && (m.challengeLevel == 3 || m.challengeTypeName.contains("大")) && !m.challengeTypeName.contains("巨大")) ||
                            (selectedSize == "一般" && (m.challengeLevel == 2 || m.challengeTypeName.contains("一般")) && !m.challengeTypeName.contains("巨大")) ||
                            (selectedSize == "小" && (m.challengeLevel == 1 || m.challengeTypeName.contains("小")))
                if !match { return false }
            }

            // 5. 車位狀態
            if selectedStatus != "ALL" {
                let match = (selectedStatus == "空菇" && m.challengerCount == 0) ||
                            (selectedStatus == "未滿" && m.challengerCount > 0 && m.challengerCount < m.maxChallengers) ||
                            (selectedStatus == "已滿" && m.challengerCount >= m.maxChallengers)
                if !match { return false }
            }

            return true
        }

        return list.sorted { a, b in
            let aSec = a.remainingSeconds(nowMs: nowMs)
            let bSec = b.remainingSeconds(nowMs: nowMs)
            let aHas = a.challengerCount > 0 && a.finishTimeMs != nil && a.finishTimeMs! > nowMs
            let bHas = b.challengerCount > 0 && b.finishTimeMs != nil && b.finishTimeMs! > nowMs
            let aP = a.getEffectiveBattlePower(nowMs: nowMs)
            let bP = b.getEffectiveBattlePower(nowMs: nowMs)

            switch selectedSort {
            case .timeAsc:
                if aHas && bHas { return aSec < bSec }
                if aHas { return true }
                if bHas { return false }
                return a.updatedAt > b.updatedAt
            case .timeDesc:
                if aHas && bHas { return aSec > bSec }
                if aHas { return true }
                if bHas { return false }
                return a.updatedAt > b.updatedAt
            case .powerDesc:
                if aP != bP { return aP > bP }
                return a.updatedAt > b.updatedAt
            case .powerAsc:
                let aHasP = aP > 0
                let bHasP = bP > 0
                if aHasP && bHasP { return aP < bP }
                if aHasP { return true }
                if bHasP { return false }
                return a.updatedAt > b.updatedAt
            case .latest:
                return a.updatedAt > b.updatedAt
            }
        }
    }

    private func getBadgeColor(type: Int) -> Color {
        switch type {
        case 10: return Color.orange
        case 11: return Color.red
        case 12: return Color.blue
        case 13: return Color.cyan
        case 14: return Color.green
        case 16: return Color.indigo
        case 17: return Color.yellow
        case 18: return Color.purple
        default: return Color.green
        }
    }

    private func formatDuration(seconds: Int64) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        return h > 0 ? String(format: "%02d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }
}
