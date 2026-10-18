import SwiftUI

public struct LoginView: View {
    @ObservedObject var session = AutoFarmSession.shared

    @State private var usernameInput: String = "user"
    @State private var passwordInput: String = "123456"
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

                    Text("請先登入以解鎖虛擬定位與巡航功能")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }

                // 登入表單卡片
                VStack(spacing: 16) {
                    // 帳號輸入框
                    VStack(alignment: .leading, spacing: 6) {
                        Text("使用者帳號")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                        HStack(spacing: 8) {
                            Image(systemName: "person.fill")
                                .foregroundColor(.blue)
                                .font(.system(size: 14))
                            TextField("輸入帳號或電子郵件", text: $usernameInput)
                                .font(.system(size: 14))
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
                            SecureField("輸入密碼", text: $passwordInput)
                                .font(.system(size: 14))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color(UIColor.tertiarySystemBackground))
                        .cornerRadius(10)
                    }

                    // 記住我選項
                    Toggle(isOn: $rememberMe) {
                        Text("保持登入狀態")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 2)

                    // 錯誤訊息提示
                    if let err = errorMessage {
                        Text(err)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // 登入按鈕
                    Button(action: handleLogin) {
                        HStack(spacing: 6) {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            }
                            Text(isLoading ? "驗證中..." : "登入 App")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.white)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.blue)
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
                Text("AutoFarm iOS Client v1.0.0")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.bottom, 20)
            }
        }
    }

    private func handleLogin() {
        hideKeyboard()
        let user = usernameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let pass = passwordInput.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !user.isEmpty else {
            errorMessage = "請輸入使用者帳號"
            return
        }
        guard !pass.isEmpty else {
            errorMessage = "請輸入登入密碼"
            return
        }

        isLoading = true
        errorMessage = nil

        // 模擬驗證並成功登入
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.isLoading = false
            self.session.login(username: user)
        }
    }
}
