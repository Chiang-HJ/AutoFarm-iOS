import SwiftUI

public struct RouteModeConfigSheet: View {
    let route: SavedRoute
    let onStart: (Int, LoopMode, Int, MultiFlowerSettings, Double) -> Void
    @Environment(\.dismiss) var dismiss

    // 0: 直線, 1: 種花, 2: 果實
    @State private var selectedMode: Int = 0

    // 直線參數
    @State private var linearLoopMode: LoopMode = .closedLoop
    @State private var linearLoops: Int = 0

    // 種花參數
    @State private var flowerTeleport: Bool = true
    @State private var circle1Radius: Double = 28.0
    @State private var circle1Loops: Double = 1.0
    @State private var circle1WaitBefore: Int = 1
    @State private var circle1WaitAfter: Int = 7
    @State private var enableCircle2: Bool = true
    @State private var circle2Radius: Double = 24.0
    @State private var circle2Loops: Double = 1.0
    @State private var circle2WaitBefore: Int = 1
    @State private var circle2WaitAfter: Int = 7
    @State private var flowerJitter: Bool = true
    @State private var flowerAlternate: Bool = true

    // 果實參數
    @State private var fruitWalkDistance: Double = 80.0
    @State private var fruitLoops: Int = 0

    public init(route: SavedRoute, onStart: @escaping (Int, LoopMode, Int, MultiFlowerSettings, Double) -> Void) {
        self.route = route
        self.onStart = onStart
    }

    public var body: some View {
        NavigationView {
            Form {
                Section(header: Text("【\(route.name)】共 \(route.nodes.count) 個航點")) {
                    Picker("巡航模式", selection: $selectedMode) {
                        Text("直線循跡").tag(0)
                        Text("繞圈種花").tag(1)
                        Text("跳收果實").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .padding(.vertical, 4)
                }

                if selectedMode == 0 {
                    linearSection
                } else if selectedMode == 1 {
                    flowerSection
                } else {
                    fruitSection
                }

                Section {
                    Button(action: confirmAndStart) {
                        HStack {
                            Spacer()
                            Image(systemName: "play.fill")
                            Text("確認啟動此路線")
                                .fontWeight(.bold)
                            Spacer()
                        }
                    }
                    .foregroundColor(.white)
                    .listRowBackground(Color.blue)
                }
            }
            .navigationTitle("模式參數設定")
            .navigationBarItems(leading: Button("取消") { dismiss() })
            .onAppear(perform: loadSavedPreferences)
        }
    }

    // MARK: - 直線巡航設定
    private var linearSection: some View {
        Group {
            Section(header: Text("終點處理模式")) {
                Picker("路線循環方式", selection: $linearLoopMode) {
                    Text("閉合路線 (原速返航)").tag(LoopMode.closedLoop)
                    Text("跳回起點 (瞬移下一輪)").tag(LoopMode.teleportToStart)
                }
            }

            Section(header: Text("循環圈數 (0 為無限循環)")) {
                Stepper(value: $linearLoops, in: 0...99) {
                    HStack {
                        Text("目標輪數")
                        Spacer()
                        Text(linearLoops == 0 ? "無限循環 (∞)" : "\(linearLoops) 輪")
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - 繞圈種花設定
    private var flowerSection: some View {
        Group {
            Section(header: Text("花點間移動方式")) {
                Picker("前往下一花苞", selection: $flowerTeleport) {
                    Text("瞬間傳送 (Teleport)").tag(true)
                    Text("直線步行 (Walk)").tag(false)
                }
            }

            Section(header: Text("第一圈 (Circle 1)")) {
                HStack {
                    Text("繞圈半徑")
                    Spacer()
                    TextField("28", value: $circle1Radius, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 70)
                    Text("公尺")
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("繞圈數")
                    Spacer()
                    TextField("1.0", value: $circle1Loops, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 70)
                    Text("圈")
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("出發前等待")
                    Spacer()
                    TextField("1", value: $circle1WaitBefore, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 70)
                    Text("秒")
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("繞完後等待")
                    Spacer()
                    TextField("7", value: $circle1WaitAfter, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 70)
                    Text("秒")
                        .foregroundColor(.secondary)
                }
            }

            Section(header: Text("第二圈 (Circle 2)")) {
                Toggle("啟用第二圈", isOn: $enableCircle2)

                if enableCircle2 {
                    HStack {
                        Text("繞圈半徑")
                        Spacer()
                        TextField("24", value: $circle2Radius, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 70)
                        Text("公尺")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("繞圈數")
                        Spacer()
                        TextField("1.0", value: $circle2Loops, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 70)
                        Text("圈")
                            .foregroundColor(.secondary)
                    }
                }
            }

            Section(header: Text("防封鎖機制")) {
                Toggle("軌跡微擾 (±0.5m 徑向擾動)", isOn: $flowerJitter)
                Toggle("順逆時針交替旋轉", isOn: $flowerAlternate)
            }
        }
    }

    // MARK: - 跳收果實設定
    private var fruitSection: some View {
        Group {
            Section(header: Text("果實直徑採集距離")) {
                HStack {
                    Text("南北直徑行走")
                    Spacer()
                    TextField("80", value: $fruitWalkDistance, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 70)
                    Text("公尺")
                        .foregroundColor(.secondary)
                }
                Text("說明：角色將瞬移至每顆果實南端 40m 處，依時速向北步行 80m 直徑穿過果實中心完成採集。")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Section(header: Text("循環圈數 (0 為無限循環)")) {
                Stepper(value: $fruitLoops, in: 0...99) {
                    HStack {
                        Text("目標輪數")
                        Spacer()
                        Text(fruitLoops == 0 ? "無限循環 (∞)" : "\(fruitLoops) 輪")
                            .foregroundColor(.secondary)
                    }
                }
            }

            Section(header: Text("防封鎖短距冷卻")) {
                Text("系統自動套用寶可夢短距離冷卻階梯 (0~7秒)，跳點之間自動倒數防風控。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - 儲存並出發
    private func confirmAndStart() {
        savePreferences()

        let flowerConfig = MultiFlowerSettings(
            enableCircle2: enableCircle2,
            circle1: FlowerCircleParam(radius: circle1Radius, loops: circle1Loops, waitBeforeSec: circle1WaitBefore, waitAfterSec: circle1WaitAfter),
            circle2: FlowerCircleParam(radius: circle2Radius, loops: circle2Loops, waitBeforeSec: circle2WaitBefore, waitAfterSec: circle2WaitAfter),
            flowerTeleport: flowerTeleport,
            flowerJitter: flowerJitter,
            flowerAlternate: flowerAlternate
        )

        let targetLoops = (selectedMode == 0) ? linearLoops : (selectedMode == 1 ? 0 : fruitLoops)
        onStart(selectedMode, linearLoopMode, targetLoops, flowerConfig, fruitWalkDistance)
        dismiss()
    }

    // MARK: - 記憶偏好設定 (UserDefaults)
    private func savePreferences() {
        let ud = UserDefaults.standard
        ud.set(selectedMode, forKey: "cfg_selectedMode")
        ud.set(linearLoopMode == .closedLoop ? 1 : 0, forKey: "cfg_linearLoopMode")
        ud.set(linearLoops, forKey: "cfg_linearLoops")
        ud.set(flowerTeleport, forKey: "cfg_flowerTeleport")
        ud.set(circle1Radius, forKey: "cfg_circle1Radius")
        ud.set(circle1Loops, forKey: "cfg_circle1Loops")
        ud.set(circle1WaitBefore, forKey: "cfg_circle1WaitBefore")
        ud.set(circle1WaitAfter, forKey: "cfg_circle1WaitAfter")
        ud.set(enableCircle2, forKey: "cfg_enableCircle2")
        ud.set(circle2Radius, forKey: "cfg_circle2Radius")
        ud.set(circle2Loops, forKey: "cfg_circle2Loops")
        ud.set(circle2WaitBefore, forKey: "cfg_circle2WaitBefore")
        ud.set(circle2WaitAfter, forKey: "cfg_circle2WaitAfter")
        ud.set(flowerJitter, forKey: "cfg_flowerJitter")
        ud.set(flowerAlternate, forKey: "cfg_flowerAlternate")
        ud.set(fruitWalkDistance, forKey: "cfg_fruitWalkDistance")
        ud.set(fruitLoops, forKey: "cfg_fruitLoops")
    }

    private func loadSavedPreferences() {
        let ud = UserDefaults.standard
        if ud.object(forKey: "cfg_selectedMode") != nil {
            selectedMode = ud.integer(forKey: "cfg_selectedMode")
            linearLoopMode = ud.integer(forKey: "cfg_linearLoopMode") == 1 ? .closedLoop : .teleportToStart
            linearLoops = ud.integer(forKey: "cfg_linearLoops")
            flowerTeleport = ud.bool(forKey: "cfg_flowerTeleport")
            circle1Radius = ud.double(forKey: "cfg_circle1Radius") > 0 ? ud.double(forKey: "cfg_circle1Radius") : 28.0
            circle1Loops = ud.double(forKey: "cfg_circle1Loops") > 0 ? ud.double(forKey: "cfg_circle1Loops") : 1.0
            circle1WaitBefore = ud.integer(forKey: "cfg_circle1WaitBefore")
            circle1WaitAfter = ud.integer(forKey: "cfg_circle1WaitAfter")
            enableCircle2 = ud.bool(forKey: "cfg_enableCircle2")
            circle2Radius = ud.double(forKey: "cfg_circle2Radius") > 0 ? ud.double(forKey: "cfg_circle2Radius") : 24.0
            circle2Loops = ud.double(forKey: "cfg_circle2Loops") > 0 ? ud.double(forKey: "cfg_circle2Loops") : 1.0
            circle2WaitBefore = ud.integer(forKey: "cfg_circle2WaitBefore")
            circle2WaitAfter = ud.integer(forKey: "cfg_circle2WaitAfter")
            flowerJitter = ud.bool(forKey: "cfg_flowerJitter")
            flowerAlternate = ud.bool(forKey: "cfg_flowerAlternate")
            fruitWalkDistance = ud.double(forKey: "cfg_fruitWalkDistance") > 0 ? ud.double(forKey: "cfg_fruitWalkDistance") : 80.0
            fruitLoops = ud.integer(forKey: "cfg_fruitLoops")
        }
    }
}
