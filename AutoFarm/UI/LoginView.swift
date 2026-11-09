import SwiftUI

public struct LoginView: View {
    @ObservedObject var session = AutoFarmSession.shared

    @State private var emailInput: String = UserDefaults.standard.string(forKey: "AutoFarm_SavedLoginEmail") ?? ""
    @State private var passwordInput: String = ""
    @State private var rememberMe: Bool = true
    @State private var errorMessage: String? = nil
    @State private var isLoading: Bool = false

    public init() {}

    public var body: some View {
        ZStack {
            // 背景漸層
            LinearGradient(
                colors: [Color(UIColor.systemBackground), Color.blue.opacity(0.08)],
                startPoint: .top,
                endPoint: .bottom
            )
            .edgesIgnoringSafeArea(.all)
            .onTapGesture {
                hideKeyboard()
            }

            VStack(spacing: 24) {
                Spacer()

                // App 標誌與標題
                VStack(spacing: 10) {
                    Image(systemName: "location.north.circle.fill")
                        .font(.system(size: 64))
                        .foregroundColor(.blue)

                    Text("AutoFarm GPS")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(.primary)

                    Text("請使用花田觀測站帳號登入以啟用巡航功能")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }

                // 登入表單卡片
                VStack(spacing: 16) {
                    // 電子信箱輸入框
                    VStack(alignment: .leading, spacing: 6) {
                        Text("觀測站帳號 (電子信箱)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                        HStack(spacing: 8) {
                            Image(systemName: "envelope.fill")
                                .foregroundColor(.blue)
                                .font(.system(size: 14))
                            TextField("例如：user@gmail.com", text: $emailInput)
                                .font(.system(size: 14))
                                .keyboardType(.emailAddress)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color(UIColor.tertiarySystemBackground))
                        .cornerRadius(10)
                    }

                    // 密碼輸入框
                    VStack(alignment: .leading, spacing: 6) {
                        Text("登入密碼")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                        HStack(spacing: 8) {
                            Image(systemName: "lock.fill")
                                .foregroundColor(.blue)
                                .font(.system(size: 14))
                            SecureField("輸入觀測站密碼", text: $passwordInput)
                                .font(.system(size: 14))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color(UIColor.tertiarySystemBackground))
                        .cornerRadius(10)
                    }

                    // 記住帳號選項
                    Toggle(isOn: $rememberMe) {
                        Text("記住此信箱帳號")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 2)

                    // 錯誤訊息提示
                    if let err = errorMessage {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 13))
                                .foregroundColor(.red)
                            Text(err)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // 登入按鈕
                    Button(action: handleLogin) {
                        HStack(spacing: 8) {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            }
                            Text(isLoading ? "正在連線驗證..." : "登入觀測站帳號")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.white)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(isLoading ? Color.blue.opacity(0.6) : Color.blue)
                        .cornerRadius(10)
                    }
                    .disabled(isLoading)
                }
                .padding(20)
                .background(Color(UIColor.secondarySystemBackground).opacity(0.95))
                .cornerRadius(18)
                .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 4)
                .padding(.horizontal, 24)

                Spacer()

                // 底部版權宣告
                Text("AutoFarm iOS Client v1.0.0 (Pikmin Tracker Online)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.bottom, 20)
            }
        }
    }

    private func handleLogin() {
        hideKeyboard()
        let email = emailInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let pass = passwordInput.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !email.isEmpty else {
            errorMessage = "請輸入觀測站電子信箱帳號"
            return
        }
        guard email.contains("@") else {
            errorMessage = "請輸入有效的電子信箱格式（例如：user@gmail.com）"
            return
        }
        guard !pass.isEmpty else {
            errorMessage = "請輸入登入密碼"
            return
        }

        isLoading = true
        errorMessage = nil

        FlowerStationManager.shared.loginToStation(email: email, pass: pass) { success, message in
            self.isLoading = false
            if success {
                if self.rememberMe {
                    UserDefaults.standard.set(email, forKey: "AutoFarm_SavedLoginEmail")
                } else {
                    UserDefaults.standard.removeObject(forKey: "AutoFarm_SavedLoginEmail")
                }
                let name = FlowerStationManager.shared.stationDisplayName.isEmpty ?
                    (email.components(separatedBy: "@").first ?? "花友") :
                    FlowerStationManager.shared.stationDisplayName
                self.session.login(username: name)
            } else {
                self.errorMessage = message
            }
        }
    }
}
