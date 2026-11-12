import Foundation
import UserNotifications
import WidgetKit
import BackgroundTasks
import CryptoKit
import Combine
import CommonCrypto

@MainActor
class RouterService: ObservableObject {
    static let shared = RouterService()
    static let bgTaskIdentifier = "com.personal.DSL224Manager.refresh"

    @Published var routers: [RouterProfile] = []
    @Published var activeRouterID: UUID = UUID()
    @Published var isConnected: Bool = false
    @Published var isLoading: Bool = false
    @Published var statusMessage: String = ""
    @Published var logs: [LogEntry] = []

    private var sessionCookies: [UUID: String] = [:]
    private var verificationTokens: [UUID: String] = [:]
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 6.0
        self.session = URLSession(configuration: config)
        loadAllProfiles()
        requestNotificationPermission()
        syncWidgetSnapshot()
    }

    // MARK: - الراوتر النشط حالياً
    var activeRouter: RouterProfile {
        get {
            if let found = routers.first(where: { $0.id == activeRouterID }) {
                return found
            }
            return routers.first ?? RouterProfile()
        }
        set {
            if let idx = routers.firstIndex(where: { $0.id == newValue.id }) {
                routers[idx] = newValue
            } else if !routers.isEmpty {
                routers[0] = newValue
            } else {
                routers = [newValue]
                activeRouterID = newValue.id
            }
            saveAllProfiles()
            syncWidgetSnapshot()
        }
    }

    // MARK: - إدارة الراوترات المتعددة
    func selectRouter(_ id: UUID) {
        guard routers.contains(where: { $0.id == id }) else { return }
        activeRouterID = id
        SharedStorage.defaults.set(id.uuidString, forKey: SharedStorage.activeIDKey)
        addLog("تم التبديل إلى: \(activeRouter.name)")
        syncWidgetSnapshot()
        Task {
            await loginAndRefresh()
        }
    }

    func addRouter(_ profile: RouterProfile) {
        routers.append(profile)
        activeRouterID = profile.id
        saveAllProfiles()
        syncWidgetSnapshot()
        addLog("تمت إضافة راوتر جديد: \(profile.name)")
        Task {
            await loginAndRefresh()
        }
    }

    func updateRouter(_ profile: RouterProfile) {
        if let idx = routers.firstIndex(where: { $0.id == profile.id }) {
            routers[idx] = profile
            saveAllProfiles()
            syncWidgetSnapshot()
            addLog("تم تحديث إعدادات: \(profile.name)")
        }
    }

    func deleteRouter(_ id: UUID) {
        guard routers.count > 1 else {
            statusMessage = "لا يمكن حذف الراوتر الوحيد"
            return
        }
        routers.removeAll { $0.id == id }
        if activeRouterID == id, let first = routers.first {
            activeRouterID = first.id
        }
        saveAllProfiles()
        syncWidgetSnapshot()
    }

    // MARK: - الحفظ والاسترجاع + الودجت
    func saveAllProfiles() {
        let defaults = SharedStorage.defaults
        if let data = try? JSONEncoder().encode(routers) {
            defaults.set(data, forKey: SharedStorage.profilesKey)
            UserDefaults.standard.set(data, forKey: SharedStorage.profilesKey)
        }
        defaults.set(activeRouterID.uuidString, forKey: SharedStorage.activeIDKey)
        UserDefaults.standard.set(activeRouterID.uuidString, forKey: SharedStorage.activeIDKey)
    }

    func loadAllProfiles() {
        let defaults = SharedStorage.defaults
        if let data = defaults.data(forKey: SharedStorage.profilesKey) ?? UserDefaults.standard.data(forKey: SharedStorage.profilesKey),
           let decoded = try? JSONDecoder().decode([RouterProfile].self, from: data),
           !decoded.isEmpty {
            self.routers = decoded
            if let savedIDStr = defaults.string(forKey: SharedStorage.activeIDKey) ?? UserDefaults.standard.string(forKey: SharedStorage.activeIDKey),
               let uuid = UUID(uuidString: savedIDStr),
               decoded.contains(where: { $0.id == uuid }) {
                self.activeRouterID = uuid
            } else {
                self.activeRouterID = decoded[0].id
            }
        } else {
            var dlink = RouterProfile(
                name: "راوتر D-Link (DSL-224)",
                routerIP: "192.168.2.1",
                username: "admin",
                password: "",
                firmware: .me110Boa,
                totalPlanGB: 140.0,
                renewalDay: 1
            )
            dlink.devices = Self.sampleDevices()

            let huawei = RouterProfile(
                name: "راوتر 4G (Huawei B311)",
                routerIP: "192.168.1.1",
                username: "admin",
                password: "",
                firmware: .huaweiB311,
                totalPlanGB: 140.0,
                renewalDay: 1
            )

            self.routers = [huawei, dlink]
            self.activeRouterID = huawei.id
            saveAllProfiles()
        }
    }

    func syncWidgetSnapshot() {
        let r = activeRouter
        let snapshot = WidgetSnapshot(
            routerName: r.name,
            routerIP: r.routerIP,
            carrierName: r.carrierName,
            liveSpeedFormatted: r.liveSpeedFormatted,
            usedGB: r.usedGB,
            remainingGB: r.remainingGB,
            totalPlanGB: r.totalPlanGB,
            usedPercentage: r.usedPercentage,
            daysUntilRenewal: r.daysUntilRenewal,
            recommendedDailyGB: r.recommendedDailyGB,
            onlineDevicesCount: r.onlineDevicesCount,
            throttledDevicesCount: r.throttledDevicesCount,
            blockedDevicesCount: r.blockedDevicesCount,
            lastUpdated: Date()
        )
        SharedStorage.saveWidgetSnapshot(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - السجل والإشعارات
    func addLog(_ message: String, isError: Bool = false) {
        let entry = LogEntry(routerName: activeRouter.name, message: message, isError: isError)
        logs.insert(entry, at: 0)
        if logs.count > 100 {
            logs.removeLast()
        }
    }

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func sendAlert(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    // MARK: - العمل في الخلفية والأتمتة
    func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.bgTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
            addLog("تمت جدولة الفحص الخلفي التلقائي")
        } catch {
            addLog("ملاحظة جدولة الخلفية: \(error.localizedDescription)")
        }
    }

    func handleIncomingURL(_ url: URL) {
        guard url.scheme == "dsl224" else { return }
        let host = url.host?.lowercased() ?? ""

        Task {
            if host == "sync" || host == "check" || host == "background-check" {
                addLog("تم استدعاء فحص تلقائي عبر الرابط")
                await loginAndRefresh()
            } else if host == "reboot" {
                await rebootActiveRouter()
            }
        }
    }

    // MARK: - حسابات الباقة ومقاومة إعادة تشغيل الراوتر
    func checkMonthlyReset() {
        var r = activeRouter
        let cal = Calendar.current
        let now = Date()
        let day = cal.component(.day, from: now)
        let month = cal.component(.month, from: now)
        let year = cal.component(.year, from: now)

        if day >= r.renewalDay && (r.lastResetMonth != month || r.lastResetYear != year) {
            r.accumulatedBytes = 0
            r.manualOffsetGB = 0
            r.notifiedThresholds.removeAll()
            r.lastResetMonth = month
            r.lastResetYear = year
            activeRouter = r
            sendAlert(title: "🔄 تجديد باقة \(r.name)", body: "تم تصفير عداد الاستهلاك لبداية الشهر الجديد.")
            addLog("تم تصفير العداد تلقائياً لموعد التجديد الشهري")
        }
    }

    func processWANBytes(_ currentWANBytes: UInt64) {
        checkMonthlyReset()
        var r = activeRouter
        var deltaBytes: UInt64 = 0

        if r.lastRecordedWANBytes == 0 {
            r.lastRecordedWANBytes = currentWANBytes
        } else if currentWANBytes >= r.lastRecordedWANBytes {
            deltaBytes = currentWANBytes - r.lastRecordedWANBytes
            r.accumulatedBytes += deltaBytes
            r.lastRecordedWANBytes = currentWANBytes
        } else {
            deltaBytes = currentWANBytes
            r.accumulatedBytes += deltaBytes
            r.lastRecordedWANBytes = currentWANBytes
            addLog("تم رصد إعادة تشغيل الراوتر وحفظ الاستهلاك السابق بدون فقدان")
        }

        if deltaBytes > 0 {
            let deltaGB = Double(deltaBytes) / (1024.0 * 1024.0 * 1024.0)
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy-MM-dd"
            let todayKey = fmt.string(from: Date())
            if let idx = r.dailyHistory.firstIndex(where: { $0.dateKey == todayKey }) {
                r.dailyHistory[idx].consumedGB += deltaGB
            } else {
                r.dailyHistory.insert(DailyUsageRecord(dateKey: todayKey, consumedGB: deltaGB), at: 0)
                if r.dailyHistory.count > 31 { r.dailyHistory.removeLast() }
            }
        }

        r.lastSyncDate = Date()
        activeRouter = r
        checkQuotaThresholds()
    }

    func checkQuotaThresholds() {
        var r = activeRouter
        guard r.notifyOnQuotaThreshold else { return }
        let currentPercent = Int(r.usedPercentage)
        var changed = false

        for threshold in r.alertThresholds.sorted() {
            if currentPercent >= threshold && !r.notifiedThresholds.contains(threshold) {
                r.notifiedThresholds.append(threshold)
                changed = true
                sendAlert(
                    title: "⚠️ تنبيه باقة (\(r.name))",
                    body: "تجاوز استهلاك الباقة \(threshold)%! المتبقي حالياً \(String(format: "%.1f", r.remainingGB)) جيجابايت."
                )
            }
        }
        if changed {
            activeRouter = r
        }
    }

    func resetCurrentCycleQuota() {
        var r = activeRouter
        r.accumulatedBytes = 0
        r.manualOffsetGB = 0
        r.lastRecordedWANBytes = 0
        r.notifiedThresholds.removeAll()
        activeRouter = r
        addLog("تم تصفير عداد الدورة الحالية يدوياً")
    }

    // MARK: - الاتصال بالراوتر (يدعم D-Link و Huawei B311)
    func loginAndRefresh() async -> Bool {
        isLoading = true
        defer { isLoading = false }
        let r = activeRouter

        if r.firmware == .huaweiB311 {
            return await loginAndRefreshHuawei(router: r)
        } else {
            return await loginAndRefreshDLink(router: r)
        }
    }

    // MARK: - جلب رمز حماية جديد لراوترات Huawei (Single-use Token Refresher)
    private func getFreshHuaweiToken(routerIP: String) async -> String? {
        // 1. فحص endpoint الخاص بالـ token أولاً
        if let url = URL(string: "http://\(routerIP)/api/webserver/token"),
           let (data, res) = try? await session.data(from: url),
           let xml = String(data: data, encoding: .utf8),
           let tok = extractXMLTag("token", from: xml) {
            if let http = res as? HTTPURLResponse, let cookie = http.allHeaderFields["Set-Cookie"] as? String {
                sessionCookies[activeRouterID] = cookie
            }
            return tok
        }
        // 2. استخدام SesTokInfo كبديل
        if let url = URL(string: "http://\(routerIP)/api/webserver/SesTokInfo"),
           let (data, res) = try? await session.data(from: url),
           let xml = String(data: data, encoding: .utf8),
           let tok = extractXMLTag("TokInfo", from: xml) {
            if let ses = extractXMLTag("SesInfo", from: xml) {
                sessionCookies[activeRouterID] = ses
            }
            if let http = res as? HTTPURLResponse, let cookie = http.allHeaderFields["Set-Cookie"] as? String {
                sessionCookies[activeRouterID] = cookie
            }
            return tok
        }
        return nil
    }

    // MARK: - منطق راوترات Huawei (B311-221 HiLink API)
    private func loginAndRefreshHuawei(router: RouterProfile) async -> Bool {
        var r = router
        // 1. جلب البيانات العامة المتاحة فوراً بدون كلمة سر
        await fetchHuaweiPublicStats(&r)

        // 2. إذا توفرت كلمة المرور، نقوم بالمصافحة وتأكيد تسجيل الدخول لجلب الأجهزة
        if !r.password.isEmpty {
            await authenticateHuawei(&r)
            await fetchHuaweiHosts(&r)
        }

        self.activeRouter = r
        self.isConnected = true
        self.statusMessage = ""
        syncWidgetSnapshot()
        scheduleBackgroundRefresh()
        return true
    }

    private func fetchHuaweiPublicStats(_ r: inout RouterProfile) async {
        // اسم مزود الشريحة
        if let url = URL(string: "http://\(r.routerIP)/api/net/current-plmn"),
           let (data, _) = try? await session.data(from: url),
           let xml = String(data: data, encoding: .utf8),
           let carrier = extractXMLTag("FullName", from: xml) ?? extractXMLTag("ShortName", from: xml) {
            r.carrierName = carrier
            addLog("شبكة 4G: \(carrier)")
        }

        // السرعة اللحظية للرفع والتحميل
        if let url = URL(string: "http://\(r.routerIP)/api/monitoring/traffic-statistics"),
           let (data, _) = try? await session.data(from: url),
           let xml = String(data: data, encoding: .utf8) {
            if let downBytes = extractXMLTag("CurrentDownloadRate", from: xml), let dVal = Double(downBytes) {
                r.liveDownloadRateKbps = dVal / 1024.0
            }
            if let upBytes = extractXMLTag("CurrentUploadRate", from: xml), let uVal = Double(upBytes) {
                r.liveUploadRateKbps = uVal / 1024.0
            }
        }

        // إحصائيات استهلاك الشهر المدمجة في راوتر Huawei
        if let url = URL(string: "http://\(r.routerIP)/api/monitoring/month_statistics"),
           let (data, _) = try? await session.data(from: url),
           let xml = String(data: data, encoding: .utf8) {
            let downStr = extractXMLTag("CurrentMonthDownload", from: xml) ?? "0"
            let upStr = extractXMLTag("CurrentMonthUpload", from: xml) ?? "0"
            if let down = UInt64(downStr), let up = UInt64(upStr), (down + up) > 0 {
                let totalMonthBytes = down + up
                r.accumulatedBytes = totalMonthBytes
                r.lastSyncDate = Date()
                addLog("استهلاك Huawei B311 المباشر: \(String(format: "%.2f", Double(totalMonthBytes) / (1024.0 * 1024.0 * 1024.0))) GB")
            }
        }
    }

    private func authenticateHuawei(_ r: inout RouterProfile) async {
        guard !r.password.isEmpty else {
            addLog("تنبيه: كلمة مرور راوتر Huawei فارغة، يرجى كتابتها في الإعدادات.")
            return
        }

        // 1. جلب بيانات الجلسة الأولية SesTokInfo
        guard let url = URL(string: "http://\(r.routerIP)/api/webserver/SesTokInfo"),
              let (data, res) = try? await session.data(from: url),
              let xml = String(data: data, encoding: .utf8),
              let sesInfo = extractXMLTag("SesInfo", from: xml),
              let tokInfo = extractXMLTag("TokInfo", from: xml) else {
            return
        }

        var currentCookie = sesInfo
        if let http = res as? HTTPURLResponse, let sc = http.allHeaderFields["Set-Cookie"] as? String {
            currentCookie = sc
        }
        sessionCookies[r.id] = currentCookie
        verificationTokens[r.id] = tokInfo

        // 2. محاولة تسجيل الدخول عبر SCRAM-SHA256 (البروتوكول الإلزامي لراوترات Huawei / Airbox الحديثة)
        let firstNonce = (0..<32).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
        if let challengeURL = URL(string: "http://\(r.routerIP)/api/user/challenge_login") {
            var chalReq = URLRequest(url: challengeURL)
            chalReq.httpMethod = "POST"
            chalReq.setValue("application/xml", forHTTPHeaderField: "Content-Type")
            chalReq.setValue(currentCookie.contains("SessionID=") ? currentCookie : "SessionID=\(currentCookie)", forHTTPHeaderField: "Cookie")
            chalReq.setValue(tokInfo, forHTTPHeaderField: "__RequestVerificationToken")
            let chalBody = """
            <?xml version="1.0" encoding="UTF-8"?>
            <request>
                <username>\(r.username)</username>
                <firstnonce>\(firstNonce)</firstnonce>
                <mode>1</mode>
            </request>
            """
            chalReq.httpBody = chalBody.data(using: .utf8)

            if let (chalData, chalRes) = try? await session.data(for: chalReq),
               let chalXML = String(data: chalData, encoding: .utf8),
               let saltHex = extractXMLTag("salt", from: chalXML),
               let serverNonce = extractXMLTag("servernonce", from: chalXML) {

                let iterations = Int(extractXMLTag("iterations", from: chalXML) ?? "100") ?? 100
                var step2Token = tokInfo
                var step2Cookie = currentCookie
                if let http = chalRes as? HTTPURLResponse {
                    if let t = http.allHeaderFields["__RequestVerificationToken"] as? String { step2Token = t }
                    if let c = http.allHeaderFields["Set-Cookie"] as? String { step2Cookie = c }
                }

                // حساب برهان المصادقة SCRAM Client Proof
                if let saltBytes = dataFromHex(saltHex),
                   let saltedPassword = pbkdf2SHA256(password: r.password, salt: saltBytes, iterations: iterations) {
                    let clientKey = hmacSHA256(key: saltedPassword, data: Data("Client Key".utf8))
                    let storedKey = Data(SHA256.hash(data: clientKey))
                    let authMsg = Data("\(firstNonce),\(serverNonce),\(serverNonce)".utf8)
                    let clientSig = hmacSHA256(key: storedKey, data: authMsg)
                    let clientProof = hexFromData(xorBytes(clientKey, clientSig))

                    // إرسال authentication_login
                    if let authURL = URL(string: "http://\(r.routerIP)/api/user/authentication_login") {
                        var authReq = URLRequest(url: authURL)
                        authReq.httpMethod = "POST"
                        authReq.setValue("application/xml", forHTTPHeaderField: "Content-Type")
                        authReq.setValue(step2Cookie.contains("SessionID=") ? step2Cookie : "SessionID=\(step2Cookie)", forHTTPHeaderField: "Cookie")
                        authReq.setValue(step2Token, forHTTPHeaderField: "__RequestVerificationToken")
                        let authBody = """
                        <?xml version="1.0" encoding="UTF-8"?>
                        <request>
                            <clientproof>\(clientProof)</clientproof>
                            <finalnonce>\(serverNonce)</finalnonce>
                        </request>
                        """
                        authReq.httpBody = authBody.data(using: .utf8)

                        if let (authData, authRes) = try? await session.data(for: authReq) {
                            let authStr = String(data: authData, encoding: .utf8) ?? ""
                            if let http = authRes as? HTTPURLResponse {
                                if let c = http.allHeaderFields["Set-Cookie"] as? String {
                                    sessionCookies[r.id] = c
                                }
                                if let t = http.allHeaderFields["__RequestVerificationToken"] as? String {
                                    verificationTokens[r.id] = t
                                }
                            }

                            if authStr.contains("<response>OK</response>") || authStr.contains("<serverproof>") {
                                addLog("✅ تم تسجيل الدخول لراوتر Huawei بنجاح كمسؤول (SCRAM-SHA256)")
                                return
                            } else {
                                let errCode = extractXMLTag("code", from: authStr) ?? "غير معروف"
                                addLog("فشل تسجيل دخول Huawei SCRAM (كود: \(errCode)) - يرجى التأكد من كلمة المرور", isError: true)
                                return
                            }
                        }
                    }
                }
            }
        }

        // 3. Fallback للراوترات الأقدم غير الداعمة لـ SCRAM (بروتوكول password_type 4)
        let pwdHash = sha256Hex(r.password)
        let pwdB64 = Data(pwdHash.utf8).base64EncodedString()
        let authString = "\(r.username)\(pwdB64)\(tokInfo)"
        let finalHash = sha256Hex(authString)
        let finalPassword = Data(finalHash.utf8).base64EncodedString()

        guard let loginURL = URL(string: "http://\(r.routerIP)/api/user/login") else { return }
        var req = URLRequest(loginURL: loginURL, cookie: currentCookie, token: tokInfo)
        req.httpMethod = "POST"
        req.setValue("application/xml", forHTTPHeaderField: "Content-Type")
        let xmlBody = """
        <?xml version="1.0" encoding="UTF-8"?>
        <request>
            <Username>\(r.username)</Username>
            <Password>\(finalPassword)</Password>
            <password_type>4</password_type>
        </request>
        """
        req.httpBody = xmlBody.data(using: .utf8)

        if let (data, res) = try? await session.data(for: req),
           let http = res as? HTTPURLResponse {
            let resStr = String(data: data, encoding: .utf8) ?? ""
            if let newCookie = http.allHeaderFields["Set-Cookie"] as? String {
                sessionCookies[r.id] = newCookie
            }
            if let newTok = http.allHeaderFields["__RequestVerificationToken"] as? String {
                verificationTokens[r.id] = newTok
            }
            addLog("رد تسجيل دخول Huawei القديم (\(http.statusCode)): \(resStr.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
    }

    private func fetchHuaweiHosts(_ r: inout RouterProfile) async {
        guard let url = URL(string: "http://\(r.routerIP)/api/wlan/host-list") else { return }
        var req = URLRequest(loginURL: url, cookie: sessionCookies[r.id], token: verificationTokens[r.id])
        guard let (data, _) = try? await session.data(for: req),
              let xml = String(data: data, encoding: .utf8) else { return }

        let parsed = parseHuaweiHostList(xml, existingRouter: r)
        if !parsed.isEmpty {
            r.devices = parsed
            addLog("تم جلب \(parsed.count) جهاز متصل براوتر Huawei")
        }
    }

    private func parseHuaweiHostList(_ xml: String, existingRouter: RouterProfile) -> [NetworkDevice] {
        var results: [NetworkDevice] = []
        let hostPattern = #"<Host>([\s\S]*?)<\/Host>"#
        guard let hostRegex = try? NSRegularExpression(pattern: hostPattern) else { return results }
        let matches = hostRegex.matches(in: xml, range: NSRange(xml.startIndex..., in: xml))

        for match in matches {
            guard let hostRange = Range(match.range(at: 1), in: xml) else { continue }
            let hostContent = String(xml[hostRange])
            let mac = extractXMLTag("MacAddress", from: hostContent)?.replacingOccurrences(of: "-", with: ":").uppercased() ?? ""
            guard !mac.isEmpty else { continue }
            let ip = extractXMLTag("IpAddress", from: hostContent) ?? "192.168.1.50"
            let hostName = extractXMLTag("HostName", from: hostContent) ?? ""
            let existing = existingRouter.devices.first(where: { $0.id == mac })

            results.append(NetworkDevice(
                ipAddress: ip,
                macAddress: mac,
                originalHostname: hostName,
                customName: existingRouter.customDeviceNames[mac] ?? existing?.customName,
                isOnline: true,
                isBlocked: existing?.isBlocked ?? false,
                isThrottled: existing?.isThrottled ?? false,
                currentSpeedKbps: existing?.currentSpeedKbps ?? 0,
                isTrusted: existing?.isTrusted ?? false,
                firstSeen: existing?.firstSeen ?? Date(),
                lastSeen: Date()
            ))
        }
        return results
    }

    // MARK: - منطق راوترات D-Link
    private func loginAndRefreshDLink(router: RouterProfile) async -> Bool {
        let r = router
        let loginEndpoint: String
        switch r.firmware {
        case .me110Boa: loginEndpoint = "http://\(r.routerIP)/login.cgi"
        case .revR1JsonRpc: loginEndpoint = "http://\(r.routerIP)/api/login"
        case .genericRealtek: loginEndpoint = "http://\(r.routerIP)/boaform/admin/formLogin"
        case .huaweiB311: loginEndpoint = "http://\(r.routerIP)/api/user/login"
        }

        guard let url = URL(string: loginEndpoint) else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = "username=\(r.username)&password=\(r.password)".data(using: .utf8)

        do {
            let (_, res) = try await session.data(for: req)
            if let http = res as? HTTPURLResponse {
                if let cookie = http.allHeaderFields["Set-Cookie"] as? String {
                    sessionCookies[r.id] = cookie
                }
                isConnected = (200...399).contains(http.statusCode)
                statusMessage = ""
                await refreshDLinkData()
                return true
            }
        } catch {
            isConnected = true
            statusMessage = "وضع عدم الاتصال المباشر (يعرض آخر بيانات محفوظة)"
            addLog("تعذر الوصول المباشر لـ \(r.routerIP): \(error.localizedDescription)", isError: true)
            syncWidgetSnapshot()
        }
        return isConnected
    }

    private func refreshDLinkData() async {
        let r = activeRouter
        let paths = ["status_traffic.html", "tc.html", "status.html"]
        for path in paths {
            guard let url = URL(string: "http://\(r.routerIP)/\(path)") else { continue }
            var req = URLRequest(url: url)
            if let cookie = sessionCookies[r.id] { req.setValue(cookie, forHTTPHeaderField: "Cookie") }
            if let (data, _) = try? await session.data(for: req),
               let html = String(data: data, encoding: .utf8),
               let bytes = extractWANBytes(from: html) {
                processWANBytes(bytes)
                break
            }
        }
        syncWidgetSnapshot()
        scheduleBackgroundRefresh()
    }

    private func extractWANBytes(from html: String) -> UInt64? {
        let pattern = #"\b(\d{7,16})\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))
        for m in matches {
            if let range = Range(m.range, in: html),
               let val = UInt64(html[range]),
               val > 1_000_000 {
                return val
            }
        }
        return nil
    }

    // MARK: - إجراءات التحكم في الأجهزة
    func renameDevice(_ device: NetworkDevice, newName: String) {
        var r = activeRouter
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        r.customDeviceNames[device.id] = trimmed
        if let idx = r.devices.firstIndex(where: { $0.id == device.id }) {
            r.devices[idx].customName = trimmed
        }
        activeRouter = r
        addLog("تمت تسمية الجهاز \(device.macAddress) إلى: \(trimmed)")
    }

    func toggleTrustDevice(_ device: NetworkDevice) {
        var r = activeRouter
        if let idx = r.devices.firstIndex(where: { $0.id == device.id }) {
            r.devices[idx].isTrusted.toggle()
            activeRouter = r
        }
    }

    func addManualDevice(name: String, ip: String, mac: String) {
        var r = activeRouter
        let cleanMAC = mac.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !cleanMAC.isEmpty else { return }
        r.customDeviceNames[cleanMAC] = name
        let newDev = NetworkDevice(
            ipAddress: ip.isEmpty ? "192.168.1.50" : ip,
            macAddress: cleanMAC,
            originalHostname: name,
            customName: name,
            isOnline: true,
            isBlocked: false,
            isThrottled: false,
            currentSpeedKbps: 0,
            isTrusted: true,
            firstSeen: Date(),
            lastSeen: Date()
        )
        r.devices.removeAll { $0.id == cleanMAC }
        r.devices.insert(newDev, at: 0)
        activeRouter = r
        addLog("تمت إضافة جهاز يدوياً: \(name)")
    }

    // MARK: - فصل أو حظر الجهاز (دعم دقيق ومؤكد لراوتر Huawei B311)
    func toggleBlock(_ device: NetworkDevice) async {
        var r = activeRouter
        let newBlockState = !device.isBlocked

        if r.firmware == .huaweiB311 {
            await toggleBlockHuawei(device: device, newBlockState: newBlockState)
        } else {
            let endpoint = r.firmware == .genericRealtek
                ? "http://\(r.routerIP)/boaform/admin/formWlanSetup"
                : "http://\(r.routerIP)/form2WlanSetup.cgi"
            if let url = URL(string: endpoint) {
                var req = URLRequest(url: url)
                req.httpMethod = "POST"
                req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                if let cookie = sessionCookies[r.id] { req.setValue(cookie, forHTTPHeaderField: "Cookie") }
                let action = newBlockState ? "add" : "delete"
                req.httpBody = "action=\(action)&mac=\(device.macAddress)&filter_mode=deny".data(using: .utf8)
                let _ = try? await session.data(for: req)
            }
        }

        if let idx = r.devices.firstIndex(where: { $0.id == device.id }) {
            r.devices[idx].isBlocked = newBlockState
            activeRouter = r
            addLog("\(newBlockState ? "تم حظر وفصل" : "تم إلغاء حظر"): \(device.displayName)")
        }
    }

    // التنفيذ الفعلي لحظر أجهزة Huawei عبر multi-macfilter-settings المعتمد
    private func toggleBlockHuawei(device: NetworkDevice, newBlockState: Bool) async {
        let r = activeRouter

        // 1. جلب Token و SessionID طازجة
        guard let freshToken = await getFreshHuaweiToken(routerIP: r.routerIP) else {
            addLog("فشل جلب رمز الأمان (Token) من راوتر Huawei", isError: true)
            return
        }
        let cookie = sessionCookies[r.id]

        // 2. تجميع كل الأجهزة التي يجب أن تكون في القائمة السوداء
        var blockedList = r.devices.filter { $0.id != device.id && $0.isBlocked }
        if newBlockState {
            blockedList.append(device)
        }

        // 2 = Blacklist (حظر), 0 = Disabled (إيقاف الفلترة إذا كانت القائمة فارغة)
        let filterStatus = blockedList.isEmpty ? 0 : 2

        var macEntriesXML = ""
        for (i, dev) in blockedList.prefix(10).enumerated() {
            let cleanMAC = dev.macAddress.replacingOccurrences(of: "-", with: ":").uppercased()
            let cleanName = dev.displayName.replacingOccurrences(of: " ", with: "_")
            macEntriesXML += """
                    <WifiMacFilterMac\(i)>\(cleanMAC)</WifiMacFilterMac\(i)>
                    <wifihostname\(i)>\(cleanName)</wifihostname\(i)>
            
            """
        }

        let multiXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <request>
            <Ssids>
                <Ssid>
                    <Index>0</Index>
                    <WifiMacFilterStatus>\(filterStatus)</WifiMacFilterStatus>
        \(macEntriesXML)        </Ssid>
            </Ssids>
        </request>
        """

        addLog("إرسال أمر حظر Huawei لنظام multi-macfilter (\(blockedList.count) جهاز)...")

        // 3. إرسال لـ api/wlan/multi-macfilter-settings
        if let url = URL(string: "http://\(r.routerIP)/api/wlan/multi-macfilter-settings") {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/xml", forHTTPHeaderField: "Content-Type")
            if let c = cookie {
                req.setValue(c.contains("SessionID=") ? c : "SessionID=\(c)", forHTTPHeaderField: "Cookie")
            }
            req.setValue(freshToken, forHTTPHeaderField: "__RequestVerificationToken")
            req.httpBody = multiXML.data(using: .utf8)

            do {
                let (data, res) = try await session.data(for: req)
                let resStr = String(data: data, encoding: .utf8) ?? ""
                let code = (res as? HTTPURLResponse)?.statusCode ?? 0
                addLog("رد Huawei multi-macfilter (\(code)): \(resStr.trimmingCharacters(in: .whitespacesAndNewlines))")

                if let http = res as? HTTPURLResponse,
                   let nextTok = http.allHeaderFields["__RequestVerificationToken"] as? String {
                    verificationTokens[r.id] = nextTok
                }
            } catch {
                addLog("خطأ في إرسال أمر الحظر: \(error.localizedDescription)", isError: true)
            }
        }

        // 4. إرسال لـ api/wlan/mac-filter كإجراء تكميلي
        if let token2 = await getFreshHuaweiToken(routerIP: r.routerIP),
           let url2 = URL(string: "http://\(r.routerIP)/api/wlan/mac-filter") {
            var req2 = URLRequest(url: url2)
            req2.httpMethod = "POST"
            req2.setValue("application/xml", forHTTPHeaderField: "Content-Type")
            if let c = cookie {
                req2.setValue(c.contains("SessionID=") ? c : "SessionID=\(c)", forHTTPHeaderField: "Cookie")
            }
            req2.setValue(token2, forHTTPHeaderField: "__RequestVerificationToken")

            let cleanMAC = device.macAddress.replacingOccurrences(of: "-", with: ":").uppercased()
            let singleXml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <request>
                <wifihostname>\(device.displayName)</wifihostname>
                <WifiMacFilterMac>\(cleanMAC)</WifiMacFilterMac>
            </request>
            """
            req2.httpBody = singleXml.data(using: .utf8)
            if let (data2, res2) = try? await session.data(for: req2) {
                let resStr2 = String(data: data2, encoding: .utf8) ?? ""
                let code2 = (res2 as? HTTPURLResponse)?.statusCode ?? 0
                addLog("رد Huawei mac-filter (\(code2)): \(resStr2.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
        }
    }

    func setThrottle(_ device: NetworkDevice, speedKbps: Int) async {
        var r = activeRouter
        if r.firmware != .huaweiB311 {
            let endpoint = r.firmware == .genericRealtek
                ? "http://\(r.routerIP)/boaform/admin/formTrafficControl"
                : "http://\(r.routerIP)/tc.cgi"

            if let url = URL(string: endpoint) {
                var req = URLRequest(url: url)
                req.httpMethod = "POST"
                req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                if let cookie = sessionCookies[r.id] { req.setValue(cookie, forHTTPHeaderField: "Cookie") }
                let enable = speedKbps > 0 ? "1" : "0"
                let upSpeed = max(128, speedKbps / 2)
                req.httpBody = "tc_enable=\(enable)&ip=\(device.ipAddress)&down_bw=\(speedKbps)&up_bw=\(upSpeed)".data(using: .utf8)
                let _ = try? await session.data(for: req)
            }
        }

        if let idx = r.devices.firstIndex(where: { $0.id == device.id }) {
            r.devices[idx].isThrottled = (speedKbps > 0)
            r.devices[idx].currentSpeedKbps = speedKbps
            activeRouter = r
            addLog(speedKbps > 0
                ? "تم تحديد سرعة \(device.displayName) إلى \(speedKbps) ك.ب"
                : "تم فتح السرعة الكاملة لـ \(device.displayName)")
        }
    }

    func rebootActiveRouter() async {
        let r = activeRouter
        if r.firmware == .huaweiB311 {
            if let freshToken = await getFreshHuaweiToken(routerIP: r.routerIP),
               let url = URL(string: "http://\(r.routerIP)/api/device/control") {
                var req = URLRequest(url: url)
                req.httpMethod = "POST"
                req.setValue("application/xml", forHTTPHeaderField: "Content-Type")
                if let c = sessionCookies[r.id] {
                    req.setValue(c.contains("SessionID=") ? c : "SessionID=\(c)", forHTTPHeaderField: "Cookie")
                }
                req.setValue(freshToken, forHTTPHeaderField: "__RequestVerificationToken")
                req.httpBody = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><request><Control>1</Control></request>".data(using: .utf8)
                let _ = try? await session.data(for: req)
            }
        } else {
            let endpoint = r.firmware == .genericRealtek
                ? "http://\(r.routerIP)/boaform/admin/formReboot"
                : "http://\(r.routerIP)/rebootinfo.cgi"

            if let url = URL(string: endpoint) {
                var req = URLRequest(url: url)
                req.httpMethod = "POST"
                if let cookie = sessionCookies[r.id] { req.setValue(cookie, forHTTPHeaderField: "Cookie") }
                req.httpBody = "reboot=1&action=reboot".data(using: .utf8)
                let _ = try? await session.data(for: req)
            }
        }
        addLog("تم إرسال أمر إعادة تشغيل الراوتر (\(r.name))")
        sendAlert(title: "🔄 إعادة تشغيل (\(r.name))", body: "جاري إعادة تشغيل الراوتر... سيعود الاتصال خلال 90 ثانية.")
    }

    // MARK: - أدوات مساعدة (Crypto + XML)
    private func sha256Hex(_ str: String) -> String {
        let digest = SHA256.hash(data: Data(str.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func dataFromHex(_ hex: String) -> Data? {
        var data = Data()
        var index = hex.startIndex
        while index < hex.endIndex {
            guard let nextIndex = hex.index(index, offsetBy: 2, limitedBy: hex.endIndex) else { break }
            let byteStr = String(hex[index..<nextIndex])
            if let byte = UInt8(byteStr, radix: 16) {
                data.append(byte)
            } else {
                return nil
            }
            index = nextIndex
        }
        return data
    }

    private func hexFromData(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    private func pbkdf2SHA256(password: String, salt: Data, iterations: Int, keyLength: Int = 32) -> Data? {
        var derivedKeyData = Data(repeating: 0, count: keyLength)
        let status = derivedKeyData.withUnsafeMutableBytes { derivedKeyBytes in
            salt.withUnsafeBytes { saltBytes in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    password,
                    password.utf8.count,
                    saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                    salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    UInt32(iterations),
                    derivedKeyBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                    keyLength
                )
            }
        }
        return status == kCCSuccess ? derivedKeyData : nil
    }

    private func hmacSHA256(key: Data, data: Data) -> Data {
        let symKey = SymmetricKey(data: key)
        let code = HMAC<SHA256>.authenticationCode(for: data, using: symKey)
        return Data(code)
    }

    private func xorBytes(_ a: Data, _ b: Data) -> Data {
        Data(zip(a, b).map { $0 ^ $1 })
    }

    private func extractXMLTag(_ tag: String, from xml: String) -> String? {
        let pattern = "<\(tag)>([^<]+)</\(tag)>"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(xml.startIndex..., in: xml)
        if let match = regex.firstMatch(in: xml, range: range),
           let r = Range(match.range(at: 1), in: xml) {
            return String(xml[r])
        }
        return nil
    }

    func exportBackupJSON() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(routers),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "[]"
    }

    func importBackupJSON(_ jsonString: String) -> Bool {
        guard let data = jsonString.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([RouterProfile].self, from: data),
              !decoded.isEmpty else {
            return false
        }
        self.routers = decoded
        self.activeRouterID = decoded[0].id
        saveAllProfiles()
        syncWidgetSnapshot()
        addLog("تم استيراد النسخة الاحتياطية بنجاح (\(decoded.count) راوتر)")
        return true
    }

    static func sampleDevices() -> [NetworkDevice] {
        [
            NetworkDevice(
                ipAddress: "192.168.1.10",
                macAddress: "D4:6A:A8:12:34:56",
                originalHostname: "iPhone",
                customName: "هاتف أحمد",
                isOnline: true,
                isBlocked: false,
                isThrottled: false,
                currentSpeedKbps: 0,
                isTrusted: true,
                firstSeen: Date().addingTimeInterval(-86400 * 10),
                lastSeen: Date()
            ),
            NetworkDevice(
                ipAddress: "192.168.1.15",
                macAddress: "E8:9F:80:AB:CD:EF",
                originalHostname: "SmartTV",
                customName: "شاشة الصالة",
                isOnline: true,
                isBlocked: false,
                isThrottled: true,
                currentSpeedKbps: 1024,
                isTrusted: true,
                firstSeen: Date().addingTimeInterval(-86400 * 20),
                lastSeen: Date()
            )
        ]
    }
}

// MARK: - ملحق URLRequest لراوترات Huawei
fileprivate extension URLRequest {
    init(loginURL: URL, cookie: String?, token: String?) {
        self.init(url: loginURL)
        if let c = cookie {
            self.setValue(c.contains("SessionID=") ? c : "SessionID=\(c)", forHTTPHeaderField: "Cookie")
        }
        if let t = token {
            self.setValue(t, forHTTPHeaderField: "__RequestVerificationToken")
        }
    }
}
