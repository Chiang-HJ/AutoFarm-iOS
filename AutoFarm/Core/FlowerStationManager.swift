import Foundation
import Combine
import CoreLocation
import SwiftUI

// MARK: - 花田觀測站點位模型
public struct FlowerStationPoint: Identifiable, Codable, Equatable {
    public var id: String { String(index) }
    public var index: Int
    public var name: String
    public var coordsString: String
    public var latitude: Double?
    public var longitude: Double?
    public var isCounting: Bool
    public var endTime: Double
    public var duration: Double?
    public var cooldown: String?
    public var isHidden: Bool
    public var unhideTime: Double?
    public var planter: String
    public var occupierUid: String?
    public var remark: String
    public var customHours: Double?

    public init(
        index: Int,
        name: String,
        coordsString: String = "",
        latitude: Double? = nil,
        longitude: Double? = nil,
        isCounting: Bool = false,
        endTime: Double = 0,
        duration: Double? = nil,
        cooldown: String? = "23",
        isHidden: Bool = false,
        unhideTime: Double? = nil,
        planter: String = "",
        occupierUid: String? = nil,
        remark: String = "",
        customHours: Double? = nil
    ) {
        self.index = index
        self.name = name
        self.coordsString = coordsString
        self.latitude = latitude
        self.longitude = longitude
        self.isCounting = isCounting
        self.endTime = endTime
        self.duration = duration
        self.cooldown = cooldown
        self.isHidden = isHidden
        self.unhideTime = unhideTime
        self.planter = planter
        self.occupierUid = occupierUid
        self.remark = remark
        self.customHours = customHours
    }

    /// 判斷目前是否處於「大果實已生成成熟」狀態（花開首小時內）
    public var isFruitMature: Bool {
        guard isCounting else { return false }
        let now = Date().timeIntervalSince1970 * 1000
        let distance = endTime - now
        let isExpired = distance < 0
        if isExpired { return false }

        let cdStr = cooldown ?? "23"
        if cdStr == "custom" {
            let fruitMinMs = 22.0 * 3600.0 * 1000.0
            return distance >= fruitMinMs
        } else {
            let hrs = Double(cdStr) ?? 23.0
            let durationMs = hrs * 3600.0 * 1000.0
            let elapsedTime = durationMs - distance
            return elapsedTime >= 0 && elapsedTime <= 3600000.0
        }
    }

    /// 剩餘倒數秒數
    public var remainingSeconds: Int {
        guard isCounting else { return 0 }
        let now = Date().timeIntervalSince1970 * 1000
        let rem = (endTime - now) / 1000.0
        return max(0, Int(rem))
    }

    /// 剩餘格式化時間 (e.g. 22h 50m)
    public var remainingFormatted: String {
        let sec = remainingSeconds
        let h = sec / 3600
        let m = (sec % 3600) / 60
        return "\(h)h \(m)m"
    }

    /// 坐標物件
    public var coordinate: CLLocationCoordinate2D? {
        if let lat = latitude, let lng = longitude, abs(lat) > 0.001 && abs(lng) > 0.001 {
            return CLLocationCoordinate2D(latitude: lat, longitude: lng)
        }
        return nil
    }
}

// MARK: - 當前活躍種花卡位卡片
public struct ActivePlantingCard: Codable, Equatable {
    public var pointIndex: Int
    public var pointName: String
    public var planterNickname: String
    public var durationHours: Double
    public var isHidden: Bool
    public var remark: String
    public var isCountdownStarted: Bool
    public var occupiedAt: Date

    public init(
        pointIndex: Int,
        pointName: String,
        planterNickname: String,
        durationHours: Double,
        isHidden: Bool,
        remark: String,
        isCountdownStarted: Bool = false,
        occupiedAt: Date = Date()
    ) {
        self.pointIndex = pointIndex
        self.pointName = pointName
        self.planterNickname = planterNickname
        self.durationHours = durationHours
        self.isHidden = isHidden
        self.remark = remark
        self.isCountdownStarted = isCountdownStarted
        self.occupiedAt = occupiedAt
    }
}

// MARK: - 路線匹配結果項目
public struct StationRouteMatch: Identifiable, Equatable {
    public var id: UUID { route.id }
    public var route: SavedRoute
    public var isHarvestRecommended: Bool // 是否含有「收」、「果」推薦
    public var matchScore: Int
}

// MARK: - 花田觀測站核心連動管理員
public final class FlowerStationManager: ObservableObject {
    public static let shared = FlowerStationManager()

    // Firebase 連線常數
    public let apiKey = "AIzaSyDzhox-KgwVbbt3wI2MNPXujT7obOjjqHA"
    public let databaseBaseUrl = "https://pikmin-bloom-flower-default-rtdb.asia-southeast1.firebasedatabase.app"
    public let refererHeader = "https://cc123pikmin.vercel.app/"

    // Published 狀態
    @Published public var allPoints: [FlowerStationPoint] = []
    @Published public var matureFlowers: [FlowerStationPoint] = []
    @Published public var activeCard: ActivePlantingCard? = nil
    @Published public var isSyncing: Bool = false
    @Published public var lastSyncTime: Date? = nil
    @Published public var stationAuthError: String? = nil

    // 觀測站登入憑證
    @Published public var stationEmail: String = ""
    @Published public var stationUid: String = ""
    @Published public var stationDisplayName: String = ""
    @Published public var isStationLoggedIn: Bool = false

    // 中途終止釋放提示
    @Published public var shouldPromptSpotRelease: Bool = false
    @Published public var spotToRelease: ActivePlantingCard? = nil

    private var idToken: String = ""
    private var refreshToken: String = ""
    private var tokenExpiresAt: Date = Date.distantPast
    private var pollTimer: Timer?

    private let userDefaults = UserDefaults.standard
    private let kActiveCardKey = "FlowerStation_ActiveCard"
    private let kStationEmailKey = "FlowerStation_Email"
    private let kStationPasswordKey = "FlowerStation_Password"
    private let kStationUidKey = "FlowerStation_Uid"
    private let kStationTokenKey = "FlowerStation_IdToken"
    private let kStationRefreshTokenKey = "FlowerStation_RefreshToken"
    private let kStationExpiresKey = "FlowerStation_TokenExpires"
    private let kStationNicknameKey = "FlowerStation_Nickname"

    private init() {
        loadStoredCredentials()
        loadActiveCard()
        startPeriodicPolling()
    }

    deinit {
        pollTimer?.invalidate()
    }

    // MARK: - 憑證與持久化
    private func loadStoredCredentials() {
        self.stationEmail = userDefaults.string(forKey: kStationEmailKey) ?? ""
        self.stationUid = userDefaults.string(forKey: kStationUidKey) ?? ""
        self.idToken = userDefaults.string(forKey: kStationTokenKey) ?? ""
        self.refreshToken = userDefaults.string(forKey: kStationRefreshTokenKey) ?? ""
        self.stationDisplayName = userDefaults.string(forKey: kStationNicknameKey) ?? ""
        let exp = userDefaults.double(forKey: kStationExpiresKey)
        if exp > 0 {
            self.tokenExpiresAt = Date(timeIntervalSince1970: exp)
        }
        self.isStationLoggedIn = !self.idToken.isEmpty && !self.stationUid.isEmpty
    }

    private func saveCredentials(email: String, uid: String, token: String, refreshToken: String, expiresInSec: Double, nickname: String) {
        self.stationEmail = email
        self.stationUid = uid
        self.idToken = token
        self.refreshToken = refreshToken
        self.tokenExpiresAt = Date().addingTimeInterval(expiresInSec)
        self.stationDisplayName = nickname
        self.isStationLoggedIn = true

        userDefaults.set(email, forKey: kStationEmailKey)
        userDefaults.set(uid, forKey: kStationUidKey)
        userDefaults.set(token, forKey: kStationTokenKey)
        userDefaults.set(refreshToken, forKey: kStationRefreshTokenKey)
        userDefaults.set(self.tokenExpiresAt.timeIntervalSince1970, forKey: kStationExpiresKey)
        userDefaults.set(nickname, forKey: kStationNicknameKey)
    }

    public func saveActiveCard(_ card: ActivePlantingCard?) {
        self.activeCard = card
        if let card = card {
            if let data = try? JSONEncoder().encode(card) {
                userDefaults.set(data, forKey: kActiveCardKey)
            }
        } else {
            userDefaults.removeObject(forKey: kActiveCardKey)
        }
    }

    private func loadActiveCard() {
        if let data = userDefaults.data(forKey: kActiveCardKey),
           let card = try? JSONDecoder().decode(ActivePlantingCard.self, from: data) {
            self.activeCard = card
        }
    }

    // MARK: - Firebase 認證與登入
    public func loginToStation(email: String, pass: String, completion: @escaping (Bool, String) -> Void) {
        guard let url = URL(string: "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=\(apiKey)") else {
            completion(false, "網址解析錯誤")
            return
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(refererHeader, forHTTPHeaderField: "Referer")

        let body: [String: Any] = [
            "email": email.trimmingCharacters(in: .whitespacesAndNewlines),
            "password": pass,
            "returnSecureToken": true
        ]

        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else {
            completion(false, "資料封包錯誤")
            return
        }
        req.httpBody = httpBody

        URLSession.shared.dataTask(with: req) { [weak self] data, response, error in
            guard let self = self else { return }
            if let error = error {
                DispatchQueue.main.async { completion(false, error.localizedDescription) }
                return
            }
            guard let data = data else {
                DispatchQueue.main.async { completion(false, "無回應資料") }
                return
            }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let err = json["error"] as? [String: Any], let msg = err["message"] as? String {
                    DispatchQueue.main.async { completion(false, msg) }
                    return
                }

                if let token = json["idToken"] as? String,
                   let uid = json["localId"] as? String,
                   let refToken = json["refreshToken"] as? String {
                    let expStr = json["expiresIn"] as? String ?? "3600"
                    let expSec = Double(expStr) ?? 3600.0

                    // 抓取 RegisteredUsers 上的暱稱
                    self.fetchUserNickname(uid: uid, token: token) { nickname in
                        let finalName = nickname.isEmpty ? (email.components(separatedBy: "@").first ?? "花友") : nickname
                        self.saveCredentials(email: email, uid: uid, token: token, refreshToken: refToken, expiresInSec: expSec, nickname: finalName)
                        self.fetchFlowerPoints()
                        DispatchQueue.main.async {
                            completion(true, "登入成功！")
                        }
                    }
                    return
                }
            }
            DispatchQueue.main.async { completion(false, "登入資料解析失敗") }
        }.resume()
    }

    private func fetchUserNickname(uid: String, token: String, completion: @escaping (String) -> Void) {
        guard let url = URL(string: "\(databaseBaseUrl)/RegisteredUsers/\(uid)/groupName.json?auth=\(token)") else {
            completion("")
            return
        }
        var req = URLRequest(url: url)
        req.setValue(refererHeader, forHTTPHeaderField: "Referer")
        URLSession.shared.dataTask(with: req) { data, _, _ in
            if let data = data, let name = try? JSONSerialization.jsonObject(with: data) as? String {
                completion(name)
            } else {
                completion("")
            }
        }.resume()
    }

    public func logoutStation() {
        self.stationEmail = ""
        self.stationUid = ""
        self.idToken = ""
        self.refreshToken = ""
        self.stationDisplayName = ""
        self.isStationLoggedIn = false
        userDefaults.removeObject(forKey: kStationEmailKey)
        userDefaults.removeObject(forKey: kStationUidKey)
        userDefaults.removeObject(forKey: kStationTokenKey)
        userDefaults.removeObject(forKey: kStationRefreshTokenKey)
        userDefaults.removeObject(forKey: kStationExpiresKey)
        userDefaults.removeObject(forKey: kStationNicknameKey)
    }

    // MARK: - Token 自動展期 (確保請求時 Token 永不過期)
    public func ensureValidToken(completion: @escaping (String?) -> Void) {
        if !idToken.isEmpty && Date().addingTimeInterval(120) < tokenExpiresAt {
            completion(idToken)
            return
        }
        guard !refreshToken.isEmpty else {
            completion(idToken.isEmpty ? nil : idToken)
            return
        }

        guard let url = URL(string: "https://securetoken.googleapis.com/v1/token?key=\(apiKey)") else {
            completion(idToken)
            return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue(refererHeader, forHTTPHeaderField: "Referer")
        let postString = "grant_type=refresh_token&refresh_token=\(refreshToken)"
        req.httpBody = postString.data(using: .utf8)

        URLSession.shared.dataTask(with: req) { [weak self] data, _, error in
            guard let self = self, let data = data, error == nil,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let newToken = json["id_token"] as? String else {
                completion(self?.idToken)
                return
            }
            let newRef = json["refresh_token"] as? String ?? self.refreshToken
            let expStr = json["expires_in"] as? String ?? "3600"
            let expSec = Double(expStr) ?? 3600.0

            DispatchQueue.main.async {
                self.idToken = newToken
                self.refreshToken = newRef
                self.tokenExpiresAt = Date().addingTimeInterval(expSec)
                self.userDefaults.set(newToken, forKey: self.kStationTokenKey)
                self.userDefaults.set(newRef, forKey: self.kStationRefreshTokenKey)
                self.userDefaults.set(self.tokenExpiresAt.timeIntervalSince1970, forKey: self.kStationExpiresKey)
                completion(newToken)
            }
        }.resume()
    }

    // MARK: - 定時輪詢與花田成熟監聽
    public func startPeriodicPolling() {
        pollTimer?.invalidate()
        fetchFlowerPoints()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 40.0, repeats: true) { [weak self] _ in
            self?.fetchFlowerPoints()
        }
    }

    public func fetchFlowerPoints(completion: (([FlowerStationPoint]) -> Void)? = nil) {
        ensureValidToken { [weak self] token in
            guard let self = self else { return }
            var urlString = "\(self.databaseBaseUrl)/flowerPoints.json"
            if let token = token, !token.isEmpty {
                urlString += "?auth=\(token)"
            }
            guard let url = URL(string: urlString) else { return }

            var req = URLRequest(url: url)
            req.setValue(self.refererHeader, forHTTPHeaderField: "Referer")
            req.timeoutInterval = 12.0

            DispatchQueue.main.async { self.isSyncing = true }

            URLSession.shared.dataTask(with: req) { data, _, error in
                DispatchQueue.main.async { self.isSyncing = false }
                guard let data = data, error == nil else {
                    DispatchQueue.main.async { completion?(self.allPoints) }
                    return
                }

                var parsed: [FlowerStationPoint] = []
                if let root = try? JSONSerialization.jsonObject(with: data) {
                    if let list = root as? [Any] {
                        for (idx, item) in list.enumerated() {
                            if let dict = item as? [String: Any] {
                                parsed.append(self.parsePointItem(index: idx, raw: dict))
                            }
                        }
                    } else if let dict = root as? [String: Any] {
                        for (k, val) in dict {
                            if let idx = Int(k), let pointDict = val as? [String: Any] {
                                parsed.append(self.parsePointItem(index: idx, raw: pointDict))
                            }
                        }
                        parsed.sort { $0.index < $1.index }
                    }
                }

                let mature = parsed.filter { $0.isFruitMature }

                DispatchQueue.main.async {
                    self.allPoints = parsed
                    self.matureFlowers = mature
                    self.lastSyncTime = Date()
                    completion?(parsed)
                }
            }.resume()
        }
    }

    private func parsePointItem(index: Int, raw: [String: Any]) -> FlowerStationPoint {
        let name = raw["name"] as? String ?? "花田 \(index)"
        let coordsStr = raw["coords"] as? String ?? ""
        var lat: Double? = nil
        var lng: Double? = nil

        if !coordsStr.isEmpty {
            let cleaned = coordsStr
                .replacingOccurrences(of: "VIRTUAL:", with: "", options: .caseInsensitive)
                .replacingOccurrences(of: "[", with: "")
                .replacingOccurrences(of: "]", with: "")
                .replacingOccurrences(of: "(", with: "")
                .replacingOccurrences(of: ")", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let parts = cleaned.components(separatedBy: CharacterSet(charactersIn: ",; \t\r\n")).filter { !$0.isEmpty }
            if parts.count >= 2 {
                if let p0 = Double(parts[0]), let p1 = Double(parts[1]), (-90.0...90.0).contains(p0) && (-180.0...180.0).contains(p1) {
                    lat = p0
                    lng = p1
                }
            }
        }

        let isCounting = raw["isCounting"] as? Bool ?? false
        let endTime = raw["endTime"] as? Double ?? (raw["endTime"] as? Int64).map { Double($0) } ?? 0.0
        let duration = raw["duration"] as? Double ?? (raw["duration"] as? Int64).map { Double($0) }
        let cooldown = raw["cooldown"] as? String ?? (raw["cooldown"] as? Int).map { String($0) } ?? "23"
        let isHidden = raw["isHidden"] as? Bool ?? false
        let unhideTime = raw["unhideTime"] as? Double
        let planter = raw["planter"] as? String ?? ""
        let occupierUid = raw["occupierUid"] as? String
        let remark = raw["remark"] as? String ?? ""
        let customHours = raw["customHours"] as? Double

        return FlowerStationPoint(
            index: index,
            name: name,
            coordsString: coordsStr,
            latitude: lat,
            longitude: lng,
            isCounting: isCounting,
            endTime: endTime,
            duration: duration,
            cooldown: cooldown,
            isHidden: isHidden,
            unhideTime: unhideTime,
            planter: planter,
            occupierUid: occupierUid,
            remark: remark,
            customHours: customHours
        )
    }

    // MARK: - 核心動作 1：前置立即卡位 (寫入 planter，讓其他人看不到此花田)
    public func occupySpot(
        pointIndex: Int,
        pointName: String,
        planterNickname: String,
        durationHours: Double,
        isHidden: Bool,
        remark: String = "",
        completion: @escaping (Bool, String) -> Void
    ) {
        ensureValidToken { [weak self] token in
            guard let self = self else { return }
            guard let token = token, !token.isEmpty else {
                completion(false, "尚未登入花田觀測站帳號，請先登入")
                return
            }

            let urlStr = "\(self.databaseBaseUrl)/flowerPoints/\(pointIndex).json?auth=\(token)"
            guard let url = URL(string: urlStr) else {
                completion(false, "點位網址無效")
                return
            }

            var req = URLRequest(url: url)
            req.httpMethod = "PATCH"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue(self.refererHeader, forHTTPHeaderField: "Referer")

            let effectiveUid = self.stationUid.isEmpty ? "autofarm_user" : self.stationUid

            let patchData: [String: Any] = [
                "planter": planterNickname,
                "occupierUid": effectiveUid,
                "isCounting": false,
                "remark": remark
            ]

            guard let body = try? JSONSerialization.data(withJSONObject: patchData) else {
                completion(false, "資料序列化失敗")
                return
            }
            req.httpBody = body

            URLSession.shared.dataTask(with: req) { _, response, error in
                if let error = error {
                    DispatchQueue.main.async { completion(false, error.localizedDescription) }
                    return
                }
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if status == 200 || status == 204 {
                    let card = ActivePlantingCard(
                        pointIndex: pointIndex,
                        pointName: pointName,
                        planterNickname: planterNickname,
                        durationHours: durationHours,
                        isHidden: isHidden,
                        remark: remark,
                        isCountdownStarted: false
                    )
                    DispatchQueue.main.async {
                        self.saveActiveCard(card)
                        self.fetchFlowerPoints()
                        completion(true, "卡位成功！已在觀測站鎖定【\(pointName)】")
                    }
                } else {
                    DispatchQueue.main.async {
                        completion(false, "伺服器回應異常碼: \(status)")
                    }
                }
            }.resume()
        }
    }

    // MARK: - 核心動作 2：第二圈起跑時自動啟動開花倒數計時
    public func triggerLoop2Countdown(completion: ((Bool) -> Void)? = nil) {
        guard let card = self.activeCard, !card.isCountdownStarted else {
            completion?(false)
            return
        }

        let syncedNow = Date().timeIntervalSince1970 * 1000
        let durationMs = card.durationHours * 3600.0 * 1000.0
        let endTime = syncedNow + durationMs

        var unhideTime: Double? = nil
        if card.isHidden {
            let t1 = (22.0 * 60.0 + 10.0) * 60000.0
            let t2 = (5.0 * 60.0 + 10.0) * 60000.0
            let t3 = (2.0 * 60.0 + 10.0) * 60000.0
            var targetRemaining = 0.0
            if durationMs >= t1 { targetRemaining = t1 }
            else if durationMs >= t2 { targetRemaining = t2 }
            else if durationMs >= t3 { targetRemaining = t3 }
            else { targetRemaining = max(0.0, durationMs - 50.0 * 60000.0) }
            unhideTime = endTime - targetRemaining
        }

        ensureValidToken { [weak self] token in
            guard let self = self, let token = token else {
                completion?(false)
                return
            }

            let urlStr = "\(self.databaseBaseUrl)/flowerPoints/\(card.pointIndex).json?auth=\(token)"
            guard let url = URL(string: urlStr) else {
                completion?(false)
                return
            }

            var req = URLRequest(url: url)
            req.httpMethod = "PATCH"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue(self.refererHeader, forHTTPHeaderField: "Referer")

            var patchData: [String: Any] = [
                "isCounting": true,
                "endTime": endTime,
                "duration": durationMs,
                "cooldown": "\(card.durationHours)",
                "isHidden": card.isHidden,
                "planter": card.planterNickname,
                "occupierUid": self.stationUid.isEmpty ? "autofarm_user" : self.stationUid
            ]
            if let uh = unhideTime {
                patchData["unhideTime"] = uh
            }

            guard let body = try? JSONSerialization.data(withJSONObject: patchData) else {
                completion?(false)
                return
            }
            req.httpBody = body

            URLSession.shared.dataTask(with: req) { _, response, error in
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if error == nil && (status == 200 || status == 204) {
                    var updatedCard = card
                    updatedCard.isCountdownStarted = true
                    DispatchQueue.main.async {
                        self.saveActiveCard(updatedCard)
                        self.fetchFlowerPoints()
                        AutoFarmSession.shared.showToast("🌸 觀測站【\(card.pointName)】已自動開始開花倒數！")
                        completion?(true)
                    }
                } else {
                    DispatchQueue.main.async {
                        completion?(false)
                    }
                }
            }.resume()
        }
    }

    // MARK: - 核心動作 3：中途終止清空卡位以釋放花田
    public func releaseSpot(pointIndex: Int, completion: ((Bool) -> Void)? = nil) {
        ensureValidToken { [weak self] token in
            guard let self = self, let token = token else {
                completion?(false)
                return
            }

            let urlStr = "\(self.databaseBaseUrl)/flowerPoints/\(pointIndex).json?auth=\(token)"
            guard let url = URL(string: urlStr) else {
                completion?(false)
                return
            }

            var req = URLRequest(url: url)
            req.httpMethod = "PATCH"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue(self.refererHeader, forHTTPHeaderField: "Referer")

            let patchData: [String: Any?] = [
                "planter": "",
                "occupierUid": nil,
                "remark": ""
            ]

            guard let body = try? JSONSerialization.data(withJSONObject: patchData.compactMapValues { $0 }) else {
                completion?(false)
                return
            }
            req.httpBody = body

            URLSession.shared.dataTask(with: req) { _, response, error in
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                DispatchQueue.main.async {
                    if error == nil && (status == 200 || status == 204) {
                        self.saveActiveCard(nil)
                        self.fetchFlowerPoints()
                        AutoFarmSession.shared.showToast("已清空觀測站卡位，釋放花田！")
                        completion?(true)
                    } else {
                        completion?(false)
                    }
                }
            }.resume()
        }
    }

    // MARK: - 路線與花田智慧匹配
    public func findMatchingFlower(for routeName: String, firstPointCoord: CLLocationCoordinate2D? = nil) -> FlowerStationPoint? {
        let cleanRouteName = cleanNameTokens(routeName)

        // 1. 第一階：乾淨名稱完全一致
        if !cleanRouteName.isEmpty {
            for pt in allPoints {
                let cleanPt = cleanNameTokens(pt.name)
                if !cleanPt.isEmpty && cleanRouteName == cleanPt {
                    return pt
                }
            }
        }

        // 2. 第二階：乾淨名稱互相包含 (字數 >= 2)
        if cleanRouteName.count >= 2 {
            for pt in allPoints {
                let cleanPt = cleanNameTokens(pt.name)
                if cleanPt.count >= 2 && (cleanRouteName.contains(cleanPt) || cleanPt.contains(cleanRouteName)) {
                    return pt
                }
            }
        }

        // 3. 第三階：原始名稱包含比對
        let rawTrimmed = routeName.trimmingCharacters(in: .whitespacesAndNewlines)
        if rawTrimmed.count >= 2 {
            for pt in allPoints {
                if pt.name.count >= 2 && (rawTrimmed.contains(pt.name) || pt.name.contains(rawTrimmed)) {
                    return pt
                }
            }
        }

        // 4. 第四階：空間距離比對 (250 公尺內最近花苞)
        if let target = firstPointCoord {
            var closest: FlowerStationPoint? = nil
            var minDist = 250.0 // 門檻 250 公尺
            for pt in allPoints {
                if let ptCoord = pt.coordinate {
                    let d = EngineMath.getDistance(lat1: target.latitude, lon1: target.longitude, lat2: ptCoord.latitude, lon2: ptCoord.longitude)
                    if d < minDist {
                        minDist = d
                        closest = pt
                    }
                }
            }
            if let c = closest { return c }
        }

        return nil
    }

    public func findMatchingRoutes(for flower: FlowerStationPoint) -> [StationRouteMatch] {
        let cleanPt = cleanNameTokens(flower.name)
        let allRoutes = SavedDatabaseStore.shared.savedRoutes
        var matches: [StationRouteMatch] = []

        for r in allRoutes {
            let cleanR = cleanNameTokens(r.name)
            let isNameMatch = (!cleanPt.isEmpty && cleanR.contains(cleanPt)) ||
                              (!cleanR.isEmpty && cleanPt.contains(cleanR)) ||
                              r.name.contains(flower.name) || flower.name.contains(r.name)
            
            // 空間近距離比對 (門檻 1500 公尺)
            var isCoordMatch = false
            var dist = Double.infinity
            if let fCoord = flower.coordinate, let first = r.nodes.first {
                dist = EngineMath.getDistance(lat1: fCoord.latitude, lon1: fCoord.longitude, lat2: first.lat, lon2: first.lng)
                if dist < 1500.0 { isCoordMatch = true }
            }

            if isNameMatch || isCoordMatch {
                let isHarvest = r.name.contains("收") || r.name.contains("果") || r.name.contains("80") || r.name.contains("80m")
                var score = 0
                if isHarvest { score += 50 }
                if cleanR == cleanPt { score += 40 }
                else if isNameMatch { score += 25 }
                if isCoordMatch {
                    score += dist < 300.0 ? 30 : (dist < 800.0 ? 20 : 10)
                }
                matches.append(StationRouteMatch(route: r, isHarvestRecommended: isHarvest, matchScore: score))
            }
        }

        // 推薦收果實排最前面
        matches.sort { (a, b) -> Bool in
            if a.isHarvestRecommended != b.isHarvestRecommended {
                return a.isHarvestRecommended && !b.isHarvestRecommended
            }
            return a.matchScore > b.matchScore
        }

        return matches
    }

    public func cleanNameTokens(_ str: String) -> String {
        var s = str.trimmingCharacters(in: .whitespacesAndNewlines)
        let removes = [
            "路線:", "路徑:", "執行路線:", "路線：", "路徑：", "執行路線：",
            "[", "]", "【", "】", "(", ")", "（", "）", " ", "-", "_",
            "種花", "採果", "大花", "模式", "80米", "80m", "80", "28m", "24m",
            "巡航", "路線", "路徑", "種", "收", "花", "果", "循環", "雙圈", "單圈",
            "逆時針", "順時針", "定點", "自動"
        ]
        for r in removes {
            s = s.replacingOccurrences(of: r, with: "")
        }
        return s.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
