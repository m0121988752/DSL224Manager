import SwiftUI
import UIKit

// MARK: - 2. تبويب إدارة الراوترات المتعددة (Routers Tab)
struct RoutersListTabView: View {
    @ObservedObject var service: RouterService
    @State private var showAddRouter = false
    @State private var routerToEdit: RouterProfile? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(service.routers) { router in
                            RouterCardView(
                                router: router,
                                isActive: router.id == service.activeRouter.id,
                                onSelect: { service.selectRouter(router.id) },
                                onEdit: { routerToEdit = router },
                                onDelete: { service.deleteRouter(router.id) },
                                canDelete: service.routers.count > 1
                            )
                        }

                        Button(action: { showAddRouter = true }) {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                Text("إضافة راوتر جديد")
                                    .fontWeight(.bold)
                            }
                            .font(.subheadline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.blue.opacity(0.2))
                            .foregroundColor(.blue)
                            .cornerRadius(10)
                        }
                        .padding(.top, 4)
                    }
                    .padding(12)
                }
            }
            .navigationTitle("إدارة الراوترات (\(service.routers.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showAddRouter = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddRouter) {
                RouterEditorSheet(service: service, existingRouter: nil)
            }
            .sheet(item: $routerToEdit) { router in
                RouterEditorSheet(service: service, existingRouter: router)
            }
        }
    }
}

struct RouterCardView: View {
    let router: RouterProfile
    let isActive: Bool
    var onSelect: () -> Void
    var onEdit: () -> Void
    var onDelete: () -> Void
    let canDelete: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Image(systemName: "wifi.router.fill")
                            .foregroundColor(router.firmware == .huaweiB311 ? .orange : (isActive ? .blue : .gray))
                        Text(router.name)
                            .font(.subheadline.bold())
                            .foregroundColor(.white)
                        if let carrier = router.carrierName {
                            Text(carrier)
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.25))
                                .foregroundColor(.orange)
                                .cornerRadius(4)
                        }
                        if isActive {
                            Text("النشط")
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.25))
                                .foregroundColor(.blue)
                                .cornerRadius(4)
                        }
                    }
                    Text("\(router.routerIP) • \(router.firmware.rawValue)")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
                Spacer()

                HStack(spacing: 8) {
                    if !isActive {
                        Button(action: onSelect) {
                            Text("تفعيل")
                                .font(.caption2.bold())
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(6)
                        }
                    }

                    Button(action: onEdit) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.caption)
                            .padding(6)
                            .background(Color(white: 0.18))
                            .foregroundColor(.white)
                            .cornerRadius(6)
                    }

                    if canDelete {
                        Button(action: onDelete) {
                            Image(systemName: "trash")
                                .font(.caption)
                                .padding(6)
                                .background(Color.red.opacity(0.2))
                                .foregroundColor(.red)
                                .cornerRadius(6)
                        }
                    }
                }
            }

            // شريط الباقة المصغر
            VStack(spacing: 4) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(white: 0.18))
                            .frame(height: 6)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(router.usedPercentage > 85 ? Color.red : Color.blue)
                            .frame(width: max(0, min(geo.size.width, geo.size.width * CGFloat(router.usedPercentage / 100.0))), height: 6)
                    }
                }
                .frame(height: 6)

                HStack {
                    Text("مستهلك: \(String(format: "%.1f", router.usedGB)) / \(Int(router.totalPlanGB)) GB (\(Int(router.usedPercentage))%)")
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                    Spacer()
                    if let speed = router.liveSpeedFormatted {
                        Text(speed)
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(.cyan)
                    } else {
                        Text("\(router.onlineDevicesCount) متصل • \(router.throttledDevicesCount) محدد")
                            .font(.system(size: 10))
                            .foregroundColor(.gray)
                    }
                }
            }
        }
        .padding(12)
        .background(Color(white: 0.1))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isActive ? Color.blue.opacity(0.7) : Color(white: 0.16), lineWidth: 1)
        )
    }
}

struct RouterEditorSheet: View {
    @ObservedObject var service: RouterService
    let existingRouter: RouterProfile?
    @Environment(\.dismiss) var dismiss

    @State private var name: String = ""
    @State private var ip: String = "192.168.1.1"
    @State private var username: String = "admin"
    @State private var password: String = ""
    @State private var firmware: FirmwareProtocol = .huaweiB311
    @State private var totalPlanGB: Double = 140.0
    @State private var renewalDay: Int = 1
    @State private var enableWebUIFallback: Bool = true
    @State private var webUIPath: String = ""
    @State private var customUsageSelector: String = ""
    @State private var customUsageRegex: String = ""
    @State private var customDeviceTableSelector: String = ""
    @State private var customRebootButtonSelector: String = ""

    var body: some View {
        NavigationStack {
            Form {
                if existingRouter == nil {
                    Section("قوالب سريعة جاهزة") {
                        HStack(spacing: 8) {
                            Button("Huawei B311 (4G)") {
                                name = "راوتر 4G (B311)"
                                ip = "192.168.1.1"
                                username = "admin"
                                firmware = .huaweiB311
                            }
                            .buttonStyle(.bordered)

                            Button("D-Link (DSL-224)") {
                                name = "راوتر D-Link"
                                ip = "192.168.2.1"
                                username = "admin"
                                firmware = .me110Boa
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }

                Section("معلومات الراوتر") {
                    TextField("اسم الراوتر (مثال: راوتر 4G الصالة)", text: $name)
                    TextField("عنوان IP (مثال: 192.168.1.1)", text: $ip)
                        .keyboardType(.numbersAndPunctuation)
                    TextField("اسم المستخدم", text: $username)
                        .textInputAutocapitalization(.never)
                    SecureField("كلمة المرور", text: $password)
                    Picker("نظام الراوتر", selection: $firmware) {
                        ForEach(FirmwareProtocol.allCases) { fw in
                            Text(fw.rawValue).tag(fw)
                        }
                    }
                }

                Section("إعدادات الباقة") {
                    HStack {
                        Text("سعة الباقة الشهرية (GB)")
                        Spacer()
                        TextField("140", value: $totalPlanGB, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    Picker("يوم التجديد الشهري", selection: $renewalDay) {
                        ForEach(1...31, id: \.self) { day in
                            Text("يوم \(day)").tag(day)
                        }
                    }
                }

                Section("المتصفح البديل وكشط البيانات (WebUI Fallback)") {
                    Toggle("تفعيل كشط WebUI كبديل عند تعذر الـ API", isOn: $enableWebUIFallback)
                    TextField("مسار مخصص لصفحة الراوتر (اختياري - مثال: tc.html)", text: $webUIPath)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("تخصيص الكشط المرئي بدون كود (No-Code Scraper)") {
                    TextField("محدد عداد الاستهلاك (CSS Selector)", text: $customUsageSelector)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("نمط الاستخراج (Regex - اختياري)", text: $customUsageRegex)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("محدد جدول الأجهزة المتصلة", text: $customDeviceTableSelector)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("محدد زر إعادة التشغيل (Reboot Selector)", text: $customRebootButtonSelector)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle(existingRouter == nil ? "إضافة راوتر جديد" : "تعديل الراوتر")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("إلغاء") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("حفظ") {
                        if var edit = existingRouter {
                            edit.name = name.isEmpty ? "راوتر" : name
                            edit.routerIP = ip
                            edit.username = username
                            edit.password = password
                            edit.firmware = firmware
                            edit.totalPlanGB = totalPlanGB
                            edit.renewalDay = renewalDay
                            edit.enableWebUIFallback = enableWebUIFallback
                            edit.webUIPath = webUIPath
                            edit.customUsageSelector = customUsageSelector
                            edit.customUsageRegex = customUsageRegex
                            edit.customDeviceTableSelector = customDeviceTableSelector
                            edit.customRebootButtonSelector = customRebootButtonSelector
                            service.updateRouter(edit)
                        } else {
                            var newProfile = RouterProfile(
                                name: name.isEmpty ? "راوتر جديد" : name,
                                routerIP: ip,
                                username: username,
                                password: password,
                                firmware: firmware,
                                totalPlanGB: totalPlanGB,
                                renewalDay: renewalDay,
                                enableWebUIFallback: enableWebUIFallback,
                                webUIPath: webUIPath,
                                customUsageSelector: customUsageSelector,
                                customUsageRegex: customUsageRegex,
                                customDeviceTableSelector: customDeviceTableSelector,
                                customRebootButtonSelector: customRebootButtonSelector
                            )
                            newProfile.devices = RouterService.sampleDevices()
                            service.addRouter(newProfile)
                        }
                        dismiss()
                    }
                }
            }
            .onAppear {
                if let r = existingRouter {
                    name = r.name
                    ip = r.routerIP
                    username = r.username
                    password = r.password
                    firmware = r.firmware
                    totalPlanGB = r.totalPlanGB
                    renewalDay = r.renewalDay
                    enableWebUIFallback = r.enableWebUIFallback
                    webUIPath = r.webUIPath
                    customUsageSelector = r.customUsageSelector
                    customUsageRegex = r.customUsageRegex
                    customDeviceTableSelector = r.customDeviceTableSelector
                    customRebootButtonSelector = r.customRebootButtonSelector
                }
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }
}

// MARK: - 3. تبويب الإحصائيات والسجل (Stats & Logs Tab)
struct StatsAndLogsTabView: View {
    @ObservedObject var service: RouterService

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        // ملخص الاستهلاك
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("تحليل باقة (\(service.activeRouter.name))")
                                    .font(.caption.bold())
                                    .foregroundColor(.gray)
                                Spacer()
                                if let carrier = service.activeRouter.carrierName {
                                    Text(carrier)
                                        .font(.caption2.bold())
                                        .foregroundColor(.orange)
                                }
                            }

                            VStack(spacing: 8) {
                                StatDetailRow(label: "نوع الراوتر والنظام", value: service.activeRouter.firmware.rawValue)
                                Divider().background(Color(white: 0.2))
                                StatDetailRow(label: "إجمالي سعة الباقة", value: "\(Int(service.activeRouter.totalPlanGB)) GB")
                                Divider().background(Color(white: 0.2))
                                StatDetailRow(label: "المستهلك الفعلي (تراكمي + يدوي)", value: "\(String(format: "%.2f", service.activeRouter.usedGB)) GB")
                                Divider().background(Color(white: 0.2))
                                StatDetailRow(label: "المتبقي حتى يوم التجديد (\(service.activeRouter.renewalDay))", value: "\(String(format: "%.2f", service.activeRouter.remainingGB)) GB")
                                Divider().background(Color(white: 0.2))
                                StatDetailRow(label: "الأيام المتبقية للتجديد", value: "\(service.activeRouter.daysUntilRenewal) يوم")
                                Divider().background(Color(white: 0.2))
                                StatDetailRow(label: "الحد اليومي المقترح لعدم انتهاء الباقة", value: "\(String(format: "%.2f", service.activeRouter.recommendedDailyGB)) GB / يوم")
                                if let speed = service.activeRouter.liveSpeedFormatted {
                                    Divider().background(Color(white: 0.2))
                                    StatDetailRow(label: "السرعة اللحظية للاتصال", value: speed)
                                }
                            }
                            .padding(12)
                            .background(Color(white: 0.1))
                            .cornerRadius(10)
                        }

                        // سجل الاستهلاك اليومي
                        if !service.activeRouter.dailyHistory.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("سجل الاستهلاك اليومي")
                                    .font(.caption.bold())
                                    .foregroundColor(.gray)

                                VStack(spacing: 6) {
                                    ForEach(service.activeRouter.dailyHistory.prefix(10)) { item in
                                        HStack {
                                            Text(item.dateKey)
                                                .font(.caption)
                                                .foregroundColor(.white)
                                            Spacer()
                                            Text("\(String(format: "%.2f", item.consumedGB)) GB")
                                                .font(.caption.bold())
                                                .foregroundColor(.blue)
                                        }
                                        .padding(8)
                                        .background(Color(white: 0.1))
                                        .cornerRadius(8)
                                    }
                                }
                            }
                        }

                        // سجل العمليات الحية
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("سجل عمليات النظام (\(service.logs.count))")
                                    .font(.caption.bold())
                                    .foregroundColor(.gray)
                                Spacer()
                                if !service.logs.isEmpty {
                                    Button("مسح السجل") {
                                        service.logs.removeAll()
                                    }
                                    .font(.caption2)
                                    .foregroundColor(.red)
                                }
                            }

                            if service.logs.isEmpty {
                                Text("لا توجد سجلات حالياً")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                    .padding(12)
                            } else {
                                VStack(spacing: 6) {
                                    ForEach(service.logs.prefix(30)) { log in
                                        HStack(alignment: .top, spacing: 8) {
                                            Text(log.timeString)
                                                .font(.system(size: 10, design: .monospaced))
                                                .foregroundColor(.gray)
                                            Text(log.message)
                                                .font(.caption2)
                                                .foregroundColor(log.isError ? .orange : .white)
                                            Spacer()
                                        }
                                        .padding(8)
                                        .background(Color(white: 0.1))
                                        .cornerRadius(6)
                                    }
                                }
                            }
                        }
                    }
                    .padding(12)
                }
            }
            .navigationTitle("الإحصائيات والسجل")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct StatDetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.gray)
            Spacer()
            Text(value)
                .font(.caption.bold())
                .foregroundColor(.white)
        }
    }
}

// MARK: - 4. تبويب الإعدادات الشاملة (Full Settings Tab)
struct FullSettingsTabView: View {
    @ObservedObject var service: RouterService
    @State private var newThresholdInput: String = ""
    @State private var showAddThresholdAlert: Bool = false
    @State private var showResetQuotaConfirm: Bool = false
    @State private var showBackupSheet: Bool = false
    @State private var backupText: String = ""
    @State private var copiedAutomationMsg: Bool = false
    @State private var showWebUIHub: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                // 1. إعدادات الراوتر النشط
                Section("الراوتر النشط (\(service.activeRouter.name))") {
                    HStack {
                        Text("اسم الراوتر")
                        Spacer()
                        TextField("راوتر المنزل", text: Binding(
                            get: { service.activeRouter.name },
                            set: { var r = service.activeRouter; r.name = $0; service.activeRouter = r }
                        ))
                        .multilineTextAlignment(.trailing)
                    }

                    HStack {
                        Text("عنوان IP")
                        Spacer()
                        TextField("192.168.1.1", text: Binding(
                            get: { service.activeRouter.routerIP },
                            set: { var r = service.activeRouter; r.routerIP = $0; service.activeRouter = r }
                        ))
                        .keyboardType(.numbersAndPunctuation)
                        .multilineTextAlignment(.trailing)
                    }

                    HStack {
                        Text("اسم المستخدم")
                        Spacer()
                        TextField("admin", text: Binding(
                            get: { service.activeRouter.username },
                            set: { var r = service.activeRouter; r.username = $0; service.activeRouter = r }
                        ))
                        .textInputAutocapitalization(.never)
                        .multilineTextAlignment(.trailing)
                    }

                    HStack {
                        Text("كلمة السر")
                        Spacer()
                        SecureField("كلمة سر الراوتر", text: Binding(
                            get: { service.activeRouter.password },
                            set: { var r = service.activeRouter; r.password = $0; service.activeRouter = r }
                        ))
                        .multilineTextAlignment(.trailing)
                    }

                    Picker("بروتوكول الراوتر", selection: Binding(
                        get: { service.activeRouter.firmware },
                        set: { var r = service.activeRouter; r.firmware = $0; service.activeRouter = r }
                    )) {
                        ForEach(FirmwareProtocol.allCases) { fw in
                            Text(fw.rawValue).tag(fw)
                        }
                    }

                    Button(action: { Task { _ = await service.loginAndRefresh() } }) {
                        HStack {
                            Image(systemName: "bolt.horizontal.circle.fill")
                            Text("اختبار الاتصال وتحديث البيانات الآن")
                        }
                    }
                }

                // 2. إعدادات الباقة والتجديد
                Section("الباقة وموعد التجديد الشهري") {
                    HStack {
                        Text("سعة الباقة الكلية (GB)")
                        Spacer()
                        TextField("140", value: Binding(
                            get: { service.activeRouter.totalPlanGB },
                            set: { var r = service.activeRouter; r.totalPlanGB = max(1, $0); service.activeRouter = r }
                        ), format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                    }

                    Picker("يوم تجديد الباقة شهرياً", selection: Binding(
                        get: { service.activeRouter.renewalDay },
                        set: { var r = service.activeRouter; r.renewalDay = $0; service.activeRouter = r }
                    )) {
                        ForEach(1...31, id: \.self) { day in
                            Text("يوم \(day) من كل شهر").tag(day)
                        }
                    }

                    HStack {
                        Text("ضبط الاستهلاك اليدوي (GB)")
                        Spacer()
                        TextField("0", value: Binding(
                            get: { service.activeRouter.manualOffsetGB },
                            set: { var r = service.activeRouter; r.manualOffsetGB = max(0, $0); service.activeRouter = r }
                        ), format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                    }

                    Button(role: .destructive, action: { showResetQuotaConfirm = true }) {
                        HStack {
                            Image(systemName: "arrow.counterclockwise")
                            Text("تصفير عداد الاستهلاك للشهر الحالي")
                        }
                    }
                }

                // 3. الإشعارات وحدود التنبيه المتعددة
                Section("الإشعارات وحدود التنبيه") {
                    Toggle("تنبيه فور دخول جهاز جديد للشبكة", isOn: Binding(
                        get: { service.activeRouter.notifyOnNewDevice },
                        set: { var r = service.activeRouter; r.notifyOnNewDevice = $0; service.activeRouter = r }
                    ))

                    Toggle("تنبيهات تخطي نسب استهلاك الباقة", isOn: Binding(
                        get: { service.activeRouter.notifyOnQuotaThreshold },
                        set: { var r = service.activeRouter; r.notifyOnQuotaThreshold = $0; service.activeRouter = r }
                    ))

                    if service.activeRouter.notifyOnQuotaThreshold {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("نسب التنبيه المئوية:")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                Spacer()
                                Button(action: {
                                    newThresholdInput = ""
                                    showAddThresholdAlert = true
                                }) {
                                    Label("إضافة نسبة", systemImage: "plus.circle.fill")
                                        .font(.caption.bold())
                                }
                            }

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(service.activeRouter.alertThresholds.sorted(), id: \.self) { th in
                                        HStack(spacing: 4) {
                                            Text("\(th)%")
                                                .font(.caption.bold())
                                            Button(action: {
                                                var r = service.activeRouter
                                                r.alertThresholds.removeAll { $0 == th }
                                                service.activeRouter = r
                                            }) {
                                                Image(systemName: "xmark.circle.fill")
                                                    .font(.caption2)
                                                    .foregroundColor(.gray)
                                            }
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color(white: 0.2))
                                        .cornerRadius(6)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    Button(action: {
                        service.sendAlert(
                            title: "✅ إشعار تجريبي ناجح",
                            body: "التنبيهات تعمل بنجاح على (\(service.activeRouter.name)). المتبقي: \(String(format: "%.1f", service.activeRouter.remainingGB)) GB"
                        )
                    }) {
                        Label("إرسال إشعار تجريبي للهاتف", systemImage: "bell.badge.fill")
                    }
                }

                // 4. العمل في الخلفية والودجت والأتمتة
                Section("الودجت والعمل التلقائي في الخلفية") {
                    Button(action: {
                        service.syncWidgetSnapshot()
                        service.scheduleBackgroundRefresh()
                    }) {
                        Label("تحديث بيانات الودجت الآن", systemImage: "square.grid.2x2.fill")
                    }

                    Button(action: {
                        UIPasteboard.general.string = "dsl224://sync"
                        copiedAutomationMsg = true
                    }) {
                        HStack {
                            Label("نسخ رابط الأتمتة الخلفية (dsl224://sync)", systemImage: "link")
                            Spacer()
                            if copiedAutomationMsg {
                                Text("تم النسخ")
                                    .font(.caption2.bold())
                                    .foregroundColor(.green)
                            }
                        }
                    }

                    Text("نصيحة: افتح تطبيق Shortcuts > التحكم التلقائي (Automation) > عند الاتصال بواي فاي المنزل > أضف إجراء Open URLs وضع الرابط dsl224://sync ليتم التحديث تلقائياً فور دخولك للمنزل.")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }

                // 5. النسخ الاحتياطي والاستعادة
                Section("النسخ الاحتياطي والاستعادة") {
                    Button(action: {
                        backupText = service.exportBackupJSON()
                        showBackupSheet = true
                    }) {
                        Label("تصدير / استيراد الإعدادات (JSON)", systemImage: "externaldrive.fill.badge.timemachine")
                    }
                }

                // 6. أدوات متصفح WebUI وكشط البيانات والضغط على الأزرار
                Section("متصفح الراوتر والأزرار (WebUI Fallback)") {
                    Toggle("تفعيل كشط WebUI كبديل تلقائي عند تعذر API", isOn: Binding(
                        get: { service.activeRouter.enableWebUIFallback },
                        set: { var r = service.activeRouter; r.enableWebUIFallback = $0; service.activeRouter = r }
                    ))

                    Button(action: { showWebUIHub = true }) {
                        Label("فتح متصفح الراوتر وكشف الأزرار (WebUI Hub)", systemImage: "globe.americas.fill")
                    }

                    Button(action: {
                        Task { await service.runWebUIFallbackScrape() }
                    }) {
                        Label("تشغيل فحص كشط البيانات الآن (Scrape Now)", systemImage: "arrow.triangle.2.circlepath.doc.on.clipboard")
                    }

                    Button(action: {
                        Task { _ = await service.pressWebUIButton(semanticAction: .reboot) }
                    }) {
                        Label("الضغط على زر إعادة التشغيل (Reboot) عبر المتصفح", systemImage: "power")
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("الإعدادات الشاملة")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showWebUIHub) {
                RouterWebUIView(service: service)
            }
            .alert("إضافة نسبة تنبيه جديدة (%)", isPresented: $showAddThresholdAlert) {
                TextField("مثال: 60 أو 85", text: $newThresholdInput)
                    .keyboardType(.numberPad)
                Button("إضافة") {
                    if let val = Int(newThresholdInput), (1...99).contains(val) {
                        var r = service.activeRouter
                        if !r.alertThresholds.contains(val) {
                            r.alertThresholds.append(val)
                            r.alertThresholds.sort()
                            service.activeRouter = r
                        }
                    }
                }
                Button("إلغاء", role: .cancel) {}
            }
            .confirmationDialog(
                "هل أنت متأكد من تصفير عداد الاستهلاك للدورة الحالية؟",
                isPresented: $showResetQuotaConfirm,
                titleVisibility: .visible
            ) {
                Button("تصفير العداد الآن", role: .destructive) {
                    service.resetCurrentCycleQuota()
                }
                Button("إلغاء", role: .cancel) {}
            }
            .sheet(isPresented: $showBackupSheet) {
                BackupRestoreSheet(service: service, jsonText: $backupText)
            }
        }
    }
}

struct BackupRestoreSheet: View {
    @ObservedObject var service: RouterService
    @Binding var jsonText: String
    @Environment(\.dismiss) var dismiss
    @State private var statusAlert: String = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text("يمكنك نسخ هذا الكود للاحتفاظ بنسخة احتياطية لكل الراوترات وأسماء الأجهزة، أو لصق نسخة سابقة لاستعادتها:")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity, alignment: .leading)

                TextEditor(text: $jsonText)
                    .font(.system(size: 11, design: .monospaced))
                    .padding(8)
                    .background(Color(white: 0.12))
                    .cornerRadius(8)

                if !statusAlert.isEmpty {
                    Text(statusAlert)
                        .font(.caption.bold())
                        .foregroundColor(.green)
                }

                HStack(spacing: 10) {
                    Button(action: {
                        UIPasteboard.general.string = jsonText
                        statusAlert = "تم نسخ النسخة الاحتياطية إلى الحافظة ✅"
                    }) {
                        Label("نسخ للحافظة", systemImage: "doc.on.doc")
                            .font(.caption.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }

                    Button(action: {
                        if service.importBackupJSON(jsonText) {
                            statusAlert = "تمت استعادة البيانات بنجاح ✅"
                        } else {
                            statusAlert = "تنسيق JSON غير صالح ❌"
                        }
                    }) {
                        Label("استعادة من النص", systemImage: "arrow.down.doc.fill")
                            .font(.caption.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color(white: 0.2))
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                }
            }
            .padding(14)
            .navigationTitle("النسخ الاحتياطي")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("إغلاق") { dismiss() }
                }
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }
}
