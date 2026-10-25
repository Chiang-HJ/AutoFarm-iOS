import SwiftUI
import CoreLocation

public struct PreFlightPlantingSheet: View {
    let route: SavedRoute
    let flowerSettings: MultiFlowerSettings
    let onStartRoute: () -> Void

    @Environment(\.dismiss) var dismiss
    @ObservedObject var station = FlowerStationManager.shared
    @ObservedObject var session = AutoFarmSession.shared

    @State private var selectedPointIndex: Int = -1
    @State private var planterNickname: String = ""
    @State private var selectedDurationHours: Double = 23.0
    @State private var isHiddenCountdown: Bool = false
    @State private var optionalRemark: String = ""
    @State private var isCustomDuration: Bool = false
    @State private var customHoursText: String = "23"

    // 觀測站登入表單狀態
    @State private var isLoginSectionExpanded: Bool = false
    @State private var loginEmail: String = ""
    @State private var loginPass: String = ""
    @State private var isLoggingIn: Bool = false
    @State private var loginError: String? = nil

    @State private var isSubmittingOccupy: Bool = false
    @State private var occupyError: String? = nil

    public init(route: SavedRoute, flowerSettings: MultiFlowerSettings, onStartRoute: @escaping () -> Void) {
        self.route = route
        self.flowerSettings = flowerSettings
        self.onStartRoute = onStartRoute
    }

    public var body: some View {
        NavigationView {
            Form {
                // 1. 路線與配對資訊
                Section(header: Text("【\(route.name)】共 \(route.nodes.count) 個航點")) {
                    HStack {
                        Image(systemName: "camera.macro")
                            .foregroundColor(.pink)
                        Text("巡航模式")
                        Spacer()
                        Text("繞圈種花模式")
                            .foregroundColor(.secondary)
                    }

                    if station.isStationLoggedIn {
                        HStack {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundColor(.green)
                            Text("觀測站帳號")
                            Spacer()
                            Text(station.stationDisplayName.isEmpty ? station.stationEmail : station.stationDisplayName)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.primary)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text("尚未連結觀測站帳號")
                                    .font(.system(size: 13, weight: .semibold))
                                Spacer()
                                Button(action: { isLoginSectionExpanded.toggle() }) {
                                    Text(isLoginSectionExpanded ? "收合" : "點此登入")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(.blue)
                                }
                            }

                            if isLoginSectionExpanded {
                                VStack(spacing: 8) {
                                    TextField("觀測站 Email", text: $loginEmail)
                                        .textFieldStyle(RoundedBorderTextFieldStyle())
                                        .autocapitalization(.none)
                                        .keyboardType(.emailAddress)

                                    SecureField("觀測站密碼", text: $loginPass)
                                        .textFieldStyle(RoundedBorderTextFieldStyle())

                                    if let err = loginError {
                                        Text(err)
                                            .font(.system(size: 11))
                                            .foregroundColor(.red)
                                    }

                                    Button(action: handleStationLogin) {
                                        HStack {
                                            if isLoggingIn { ProgressView() }
                                            Text(isLoggingIn ? "連線驗證中..." : "登入並綁定觀測站")
                                                .font(.system(size: 13, weight: .bold))
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                        .background(Color.blue)
                                        .foregroundColor(.white)
                                        .cornerRadius(8)
                                    }
                                    .disabled(isLoggingIn)
                                }
                                .padding(.top, 4)
                            }
                        }
                    }
                }

                // 2. 自動匹配目標花田
                Section(header: Text("目標花田配對 (卡位對象)")) {
                    if station.allPoints.isEmpty {
                        HStack {
                            ProgressView()
                            Spacer().frame(width: 8)
                            Text("正在載入觀測站花田點位...")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Picker("選擇目標花田", selection: $selectedPointIndex) {
                            Text("未指定 / 不卡位").tag(-1)
                            ForEach(station.allPoints) { pt in
                                HStack {
                                    Text("[\(pt.index)] \(pt.name)")
                                    if pt.isCounting {
                                        Text("（倒數中）").foregroundColor(.red)
                                    } else if !pt.planter.isEmpty {
                                        Text("（\(pt.planter) 卡位中）").foregroundColor(.orange)
                                    } else {
                                        Text("（空閒）").foregroundColor(.green)
                                    }
                                }
                                .tag(pt.index)
                            }
                        }
                        .pickerStyle(.menu)

                        if selectedPointIndex >= 0, let target = station.allPoints.first(where: { $0.index == selectedPointIndex }) {
                            HStack {
                                Text("花苞狀態")
                                Spacer()
                                if target.isCounting {
                                    Text("已在倒數中 (剩餘 \(target.remainingFormatted))")
                                        .foregroundColor(.red)
                                } else if !target.planter.isEmpty {
                                    Text("已有其他花友卡位 (\(target.planter))")
                                        .foregroundColor(.orange)
                                } else {
                                    Text("🟢 空閒無人卡位 (可安全鎖定)")
                                        .foregroundColor(.green)
                                }
                            }
                            .font(.system(size: 12))
                        }
                    }
                }

                // 3. 卡位與倒數參數設定
                if selectedPointIndex >= 0 {
                    Section(header: Text("觀測站卡位與開花倒數設定")) {
                        // 種花者暱稱
                        HStack {
                            Text("種花者帳號")
                                .font(.system(size: 14))
                            Spacer()
                            TextField("輸入種花者姓名", text: $planterNickname)
                                .font(.system(size: 14, weight: .bold))
                                .multilineTextAlignment(.trailing)
                                .foregroundColor(.blue)
                        }

                        // 倒數時長選擇
                        Picker("開花倒數時長", selection: $selectedDurationHours) {
                            Text("23 小時 (一般平日)").tag(23.0)
                            Text("3 小時 (社群日)").tag(3.0)
                            Text("6 小時 (社群週)").tag(6.0)
                            Text("自訂時長").tag(-1.0)
                        }
                        .pickerStyle(.menu)
                        .onChange(of: selectedDurationHours) { val in
                            isCustomDuration = (val == -1.0)
                        }

                        if isCustomDuration {
                            HStack {
                                Text("自訂小時數")
                                Spacer()
                                TextField("例如 12.5", text: $customHoursText)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                Text("小時")
                            }
                        }

                        // 隱藏倒數開關
                        Toggle(isOn: $isHiddenCountdown) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("隱藏倒數計時")
                                    .font(.system(size: 14))
                                Text("開啟後於前段時間內在公眾地圖隱藏倒數")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        }

                        // 備註輸入
                        HStack {
                            Text("預約備註")
                                .font(.system(size: 14))
                            Spacer()
                            TextField("選填，例如：預計明天開", text: $optionalRemark)
                                .font(.system(size: 14))
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }

                if let err = occupyError {
                    Section {
                        Text(err)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.red)
                    }
                }

                // 4. 操作動作按鈕群
                Section {
                    // 主按鈕：確認啟動並立即卡位
                    if selectedPointIndex >= 0 {
                        Button(action: handleConfirmAndOccupy) {
                            HStack {
                                Spacer()
                                if isSubmittingOccupy {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                } else {
                                    Image(systemName: "lock.shield.fill")
                                }
                                Text(isSubmittingOccupy ? "正在卡位..." : "確認啟動並立即卡位")
                                    .fontWeight(.bold)
                                Spacer()
                            }
                        }
                        .foregroundColor(.white)
                        .listRowBackground(Color.green)
                        .disabled(isSubmittingOccupy)
                    }

                    // 僅本地種花按鈕
                    Button(action: handleLocalOnly) {
                        HStack {
                            Spacer()
                            Image(systemName: "play.circle")
                            Text("僅本地種花 (不連動觀測站)")
                                .fontWeight(.medium)
                            Spacer()
                        }
                    }
                    .foregroundColor(.blue)

                    Button("取消") {
                        dismiss()
                    }
                    .foregroundColor(.secondary)
                }
            }
            .navigationTitle("花田觀測站連動設定")
            .navigationBarItems(trailing: Button("關閉") { dismiss() })
            .onAppear(perform: setupInitialData)
        }
    }

    private func setupInitialData() {
        // 自動帶入種花者名稱
        if !station.stationDisplayName.isEmpty {
            self.planterNickname = station.stationDisplayName
        } else if !session.loggedInUsername.isEmpty {
            self.planterNickname = session.loggedInUsername
        } else {
            self.planterNickname = "花友"
        }

        // 自動比對目標花苞
        let firstCoord: CLLocationCoordinate2D? = route.nodes.first.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) }
        if let match = station.findMatchingFlower(for: route.name, firstPointCoord: firstCoord) {
            self.selectedPointIndex = match.index
        } else if let firstPt = station.allPoints.first {
            self.selectedPointIndex = firstPt.index
        }
    }

    private func handleStationLogin() {
        guard !loginEmail.isEmpty, !loginPass.isEmpty else {
            loginError = "請輸入 Email 與密碼"
            return
        }
        isLoggingIn = true
        loginError = nil
        station.loginToStation(email: loginEmail, pass: loginPass) { success, msg in
            self.isLoggingIn = false
            if success {
                self.isLoginSectionExpanded = false
                if self.planterNickname.isEmpty || self.planterNickname == "花友" {
                    self.planterNickname = self.station.stationDisplayName
                }
            } else {
                self.loginError = msg
            }
        }
    }

    private func handleConfirmAndOccupy() {
        guard selectedPointIndex >= 0 else {
            handleLocalOnly()
            return
        }

        let target = station.allPoints.first(where: { $0.index == selectedPointIndex })
        let pName = target?.name ?? "花田 #\(selectedPointIndex)"
        let duration: Double = isCustomDuration ? (Double(customHoursText) ?? 23.0) : selectedDurationHours

        isSubmittingOccupy = true
        occupyError = nil

        station.occupySpot(
            pointIndex: selectedPointIndex,
            pointName: pName,
            planterNickname: planterNickname.isEmpty ? "花友" : planterNickname,
            durationHours: duration,
            isHidden: isHiddenCountdown,
            remark: optionalRemark
        ) { success, msg in
            self.isSubmittingOccupy = false
            if success {
                dismiss()
                onStartRoute()
                session.showToast("已成功鎖定觀測站【\(pName)】！進入第二圈時將自動倒數")
            } else {
                self.occupyError = msg
            }
        }
    }

    private func handleLocalOnly() {
        dismiss()
        onStartRoute()
    }
}
