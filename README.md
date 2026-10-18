# AutoFarm iOS 虛擬定位與智能巡航系統 (AutoFarm-iOS-GPS)

免越獄、免修改遊戲客戶端、單機原生 SwiftUI 運行的系統級虛擬定位與自動巡航應用程式。完整 1:1 對齊 Android 版 AutoFarm 之各項演算法與業務邏輯。

---

## 核心功能特色

1. **直線行走巡航**：
   - 支援【跳回起點】（終點瞬移回起點開始下一輪）與【閉合路線】（自動追加起點步行返航成封閉環路）。
   - 支援設定自訂輪數或無限循環（0 = ∞）。
2. **繞圈種花引擎**：
   - 多花苞雙圈巡迴：支援花點間【瞬移】或【直線移動】；第一圈/第二圈獨立半徑（28m / 24m）、圈數、前後等待秒數；內建「圓周軌跡微擾（±0.5m）」與「正反轉交替」防封鎖機制。
   - 獨立同心圓/阿基米德螺旋：支援階梯多環與連續平滑螺旋展開。
3. **跳收果實模式**：
   - 依花心劃半徑 40m 圓，走由南向北 80m 直徑。
   - 走完直徑瞬間傳送下一點，並嚴格套用寶可夢短距瞬移冷卻階梯表（上限 7 秒），每輪循環銜接點自動套用冷卻。
4. **路徑分享與匯出**：
   - 支援 5 種主流 GPX 格式（JoyStick, AnyTo, iTools, Flashman, FakeGPS）。
   - 支援模擬真人碎步插點（densifyRoute，100~150m 步幅防直飛偵測）。
   - 支援免登入上傳至 Gofile 雲端產生公開下載短網址。
5. **斷點續跑與狀態暫存**：
   - 儲存進度時自動寫入本地快存並停止路線；開啟或重新載入時主動提示「是否接續上次進度」。
6. **定位到路線中心**：
   - 計算路線基準點之算術平均幾何中心，自動暫停行進並將虛擬 GPS 傳送至中心點。
7. **雙層停止機制**：
   - **停止路線**：僅終止自動循跡排程，角色保持在當前虛擬座標，方便虛擬方向盤無縫接管。
   - **停止虛擬定位**：徹底終止 DVT 通道，重置系統 locationd，整機即刻還原回真實實體 GPS。
8. **360 度螢幕虛擬方向盤**：
   - 支援連續平滑推盤、強度速度感知與方向鎖定開關。

---

## GitHub Actions 自動編譯打包 IPA

本專案配置了 `.github/workflows/build-ipa.yml`，推送到 GitHub 即可由 GitHub 雲端 macOS 虛擬機自動打包產出未簽名之 `.ipa` 檔案。

### 步驟 1：推送到你的 GitHub 儲存庫

在本地終端機（或本目錄）執行以下指令：

```bash
cd AutoFarm-iOS
git init
git add .
git commit -m "Initial commit for AutoFarm-iOS"
git branch -M main
git remote add origin https://github.com/<你的GitHub帳號>/AutoFarm-iOS.git
git push -u origin main
```

### 步驟 2：下載編譯完成的 IPA

1. 進入你的 GitHub 儲存庫頁面，點選頂部 **Actions** 標籤。
2. 點選最新一次的 **Build iOS IPA (Unsigned)** 構建工作流。
3. 在頁面底部的 **Artifacts** 區塊，點擊下載 `AutoFarm-iOS-unsigned.zip`，解壓縮後即可取得 `AutoFarm-iOS-unsigned.ipa`。

---

## 7 天免費個人自簽安裝指南

下載 `.ipa` 檔案後，可任選以下免越獄工具安裝至 iPhone：

### 推薦工具一：Sideloadly (Windows / macOS 電腦)
1. 下載並安裝 [Sideloadly](https://sideloadly.io/)。
2. 使用傳輸線將 iPhone 連接至電腦。
3. 將 `AutoFarm-iOS-unsigned.ipa` 拖曳至 Sideloadly 視窗中。
4. 輸入個人的 Apple ID 帳號密碼（僅向 Apple 伺服器申請 7 天個人開發者憑證），點選 **Start** 開始簽名與安裝。
5. 安裝完成後，在 iPhone 前往「設定」→「一般」→「VPN 與裝置管理」，點選你的 Apple ID 並選擇「信任」。

### 推薦工具二：SideStore / AltStore (手機免電腦常駐自簽)
- 透過 SideStore 可每 7 天於手機本機連線 Wi-Fi 自動重新簽名續期。

---

## iPhone 單機免電腦虛擬定位前置步驟

1. **開啟開發者模式**：前往 iPhone「設定」→「隱私權與安全性」→ 滑至最下方開啟「開發者模式」（需重開機並確認）。
2. **安裝 LocalDevVPN**：確保本地迴圈 VPN 已安裝並處於連線狀態（Tunnel IP 預設為 `10.7.0.1`）。
3. **匯入 Pairing 憑證**：在 App 頂部點選「設定」，匯入透過電腦配對產生的 `.plist` / `RPPairing` 檔案（只需匯入一次）。
4. 點選地圖或啟動路線，整台 iPhone 即刻全域模擬真實行走！
