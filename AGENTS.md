# AutoFarm iOS (專屬專案規範與架構指南)

本專案為 **AutoFarm iOS 原生版本**，專注於 iOS 模擬器與實機之巡航控制、懸浮抽屜及路徑自動化。

---

## 🚨 0. 實機操作鐵律 (CRITICAL)
- **嚴禁自動代點真實遊戲資產**：所有介面點擊、實機功能測試 100% 必須由使用者親自操作與驗證。

---

## 1. 專案基本資訊與目錄架構
- **專案路徑**：`C:\Users\user\Documents\AutoFarm-iOS`
- **專案類型**：Swift 原生 Xcode 專案 (iOS)
- **目標產物**：`C:\Users\user\Desktop\AutoFarm-iOS.ipa`
- **核心架構**：
  - `AutoFarm/`：Swift 核心程式碼、浮動抽屜 UI、GPS 模擬控制
  - `project.yml`：XcodeGen 專案設定檔
  - `Vendor/`：依賴庫與輔助元件

---

## 2. 功能與設計規範
- **設定記憶（Persistence）**：
  使用者調整的任何參數（巡航速度、間隔時間、繞圈參數等），必須即時保存至 `UserDefaults`。重啟 App 必須正確回讀。
- **純淨性**：未經討論，嚴禁擅自新增非使用者要求的複雜功能或破壞原有穩定邏輯。
- **UI 風格**：遵循 iOS Human Interface Guidelines，支援深淺色主題切換。

---

## 3. 專案隔離防護
- 本專案代碼**嚴格與 Android AutoFarm (`C:\Users\user\Documents\AutoFarm`) 及 BloomGo (`C:\Users\user\Documents\BloomGo`) 隔離**。
- 不得引用或混淆 Android 的 Kotlin/Gradle 構建邏輯。
