import Foundation
import UserNotifications
import WidgetKit
import BackgroundTasks
import Combine

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
            // إنشاء راوتر افتراضي جاهز عند أول تشغيل
            var defaultRouter = RouterProfile(
                name: "راوتر المنزل (DSL-224)",
                routerIP: "192.168.1.1",
                username: "admin",
                password: "",
                firmware: .me110Boa,
                totalPlanGB: 140.0,
                renewalDay: 1
            )
            defaultRouter.devices = Self.sampleDevices()
            self.routers = [defaultRouter]
            self.activeRouterID = defaultRouter.id
            saveAllProfiles()
        }
    }

    func syncWidgetSnapshot() {
        let r = activeRouter
        let snapshot = WidgetSnapshot(
            routerName: r.name,
            routerIP: r.routerIP,
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

    // MARK: - العمل في الخلفية والأتمتة (BGAppRefresh + URL Scheme)
    func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.bgTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // كل 15 دقيقة
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
            // حدث ريستارت للراوتر وتصفّر عداد الـ WAN
            deltaBytes = currentWANBytes
            r.accumulatedBytes += deltaBytes
            r.lastRecordedWANBytes = currentWANBytes
            addLog("تم رصد إعادة تشغيل الراوتر وحفظ الاستهلاك السابق بدون فقدان")
        }

        // تحديث سجل الاستهلاك اليومي
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

    // MARK: - الاتصال بالراوتر (Login + Fetch)
    func loginAndRefresh() async -> Bool {
        isLoading = true
        defer { isLoading = false }
        let r = activeRouter

        let loginEndpoint: String
        switch r.firmware {
        case .me110Boa:
            loginEndpoint = "http://\(r.routerIP)/login.cgi"
        case .revR1JsonRpc:
            loginEndpoint = "http://\(r.routerIP)/api/login"
        case .genericRealtek:
            loginEndpoint = "http://\(r.routerIP)/boaform/admin/formLogin"
        }

        guard let url = URL(string: loginEndpoint) else {
            statusMessage = "عنوان IP غير صالح"
            return false
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = "username=\(r.username)&password=\(r.password)"
        req.httpBody = body.data(using: .utf8)

        do {
            let (_, res) = try await session.data(for: req)
            if let http = res as? HTTPURLResponse {
                if let cookie = http.allHeaderFields["Set-Cookie"] as? String {
                    sessionCookies[r.id] = cookie
                }
                isConnected = (200...399).contains(http.statusCode)
                statusMessage = ""
                addLog("تم الاتصال بالراوتر (\(r.routerIP)) - كود \(http.statusCode)")
                await refreshRouterData()
                return true
            }
        } catch {
            // في حال عدم التواجد على نفس الشبكة نفتح وضع الإدارة مع البيانات المحفوظة
            isConnected = true
            statusMessage = "وضع عدم الاتصال المباشر (يعرض آخر بيانات محفوظة)"
            addLog("تعذر الوصول المباشر لـ \(r.routerIP): \(error.localizedDescription)", isError: true)
            syncWidgetSnapshot()
        }
        return isConnected
    }

    func refreshRouterData() async {
        isLoading = true
        defer { isLoading = false }
        await fetchWANTraffic()
        await fetchConnectedDevices()
        syncWidgetSnapshot()
        scheduleBackgroundRefresh()
    }

    private func fetchWANTraffic() async {
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
                addLog("تم تحديث عداد الـ WAN: \(bytes) بايت")
                return
            }
        }
    }

    private func fetchConnectedDevices() async {
        var r = activeRouter
        let paths = ["dhcptbl.html", "dhcpclients.cgi", "wlstatbl.htm"]
        var discovered: [NetworkDevice] = []

        for path in paths {
            guard let url = URL(string: "http://\(r.routerIP)/\(path)") else { continue }
            var req = URLRequest(url: url)
            if let cookie = sessionCookies[r.id] { req.setValue(cookie, forHTTPHeaderField: "Cookie") }
            if let (data, _) = try? await session.data(for: req),
               let html = String(data: data, encoding: .utf8) {
                let parsed = parseClientsFromHTML(html, existingRouter: r)
                if !parsed.isEmpty {
                    discovered = parsed
                    break
                }
            }
        }

        if !discovered.isEmpty {
            // دمج الأجهزة المكتشفة مع الأجهزة المحفوظة سابقاً
            var merged = r.devices.map { dev -> NetworkDevice in
                var copy = dev
                copy.isOnline = false
                return copy
            }

            for live in discovered {
                if let idx = merged.firstIndex(where: { $0.id == live.id }) {
                    merged[idx].isOnline = true
                    merged[idx].ipAddress = live.ipAddress
                    merged[idx].lastSeen = Date()
                    if let custom = r.customDeviceNames[live.id] {
                        merged[idx].customName = custom
                    }
                } else {
                    merged.insert(live, at: 0)
                }

                // التحقق مما إذا كان الجهاز جديداً كلياً
                if !r.knownMacAddresses.contains(live.id) {
                    r.knownMacAddresses.append(live.id)
                    if r.notifyOnNewDevice {
                        sendAlert(
                            title: "🔔 جهاز جديد على (\(r.name))",
                            body: "اتصل جهاز جديد بالشبكة: \(live.displayName) [\(live.ipAddress)]"
                        )
                    }
                    addLog("جهاز جديد دخل الشبكة: \(live.macAddress)")
                }
            }
            r.devices = merged
        } else if r.devices.isEmpty {
            r.devices = Self.sampleDevices()
        }

        r.lastSyncDate = Date()
        activeRouter = r
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

    private func parseClientsFromHTML(_ html: String, existingRouter: RouterProfile) -> [NetworkDevice] {
        var results: [NetworkDevice] = []
        let macPattern = #"([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})"#
        let ipPattern = #"192\.168\.\d{1,3}\.\d{1,3}"#
        guard let macRegex = try? NSRegularExpression(pattern: macPattern),
              let ipRegex = try? NSRegularExpression(pattern: ipPattern) else { return results }

        let macMatches = macRegex.matches(in: html, range: NSRange(html.startIndex..., in: html))
        let ipMatches = ipRegex.matches(in: html, range: NSRange(html.startIndex..., in: html))

        var seenMACs = Set<String>()
        for (idx, match) in macMatches.enumerated() {
            guard let macRange = Range(match.range, in: html) else { continue }
            let mac = String(html[macRange]).replacingOccurrences(of: "-", with: ":").uppercased()
            guard !seenMACs.contains(mac) else { continue }
            seenMACs.insert(mac)

            var ip = "192.168.1.\(10 + idx)"
            if idx < ipMatches.count, let ipRange = Range(ipMatches[idx].range, in: html) {
                ip = String(html[ipRange])
            }

            let existing = existingRouter.devices.first(where: { $0.id == mac })
            results.append(NetworkDevice(
                ipAddress: ip,
                macAddress: mac,
                originalHostname: existing?.originalHostname ?? "",
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

    // MARK: - إجراءات التحكم في الأجهزة (تسمية، حظر، سرعة، إضافة يدوية)
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
        if !r.knownMacAddresses.contains(cleanMAC) {
            r.knownMacAddresses.append(cleanMAC)
        }
        activeRouter = r
        addLog("تمت إضافة جهاز يدوياً: \(name)")
    }

    func toggleBlock(_ device: NetworkDevice) async {
        var r = activeRouter
        let newBlockState = !device.isBlocked
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

        if let idx = r.devices.firstIndex(where: { $0.id == device.id }) {
            r.devices[idx].isBlocked = newBlockState
            activeRouter = r
            addLog("\(newBlockState ? "تم حظر وفصل" : "تم إلغاء حظر"): \(device.displayName)")
        }
    }

    func setThrottle(_ device: NetworkDevice, speedKbps: Int) async {
        var r = activeRouter
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
        addLog("تم إرسال أمر إعادة تشغيل الراوتر (\(r.name))")
        sendAlert(title: "🔄 إعادة تشغيل (\(r.name))", body: "جاري إعادة تشغيل الراوتر... سيعود الواي فاي خلال 90 ثانية.")
    }

    // MARK: - تصدير واستيراد نسخة احتياطية
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
            ),
            NetworkDevice(
                ipAddress: "192.168.1.22",
                macAddress: "A0:B1:C2:33:44:55",
                originalHostname: "Guest-Phone",
                customName: "جهاز ضيف",
                isOnline: true,
                isBlocked: false,
                isThrottled: true,
                currentSpeedKbps: 512,
                isTrusted: false,
                firstSeen: Date().addingTimeInterval(-3600),
                lastSeen: Date()
            )
        ]
    }
}
