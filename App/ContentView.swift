import SwiftUI

enum DeviceFilterMode: String, CaseIterable, Identifiable {
    case all = "الكل"
    case online = "متصل"
    case throttled = "محدد السرعة"
    case blocked = "محظور"

    var id: String { rawValue }
}

struct ContentView: View {
    @ObservedObject var service: RouterService
    @State private var selectedTab: Int = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardTabView(service: service)
                .tabItem {
                    Label("الشبكة", systemImage: "wifi.router")
                }
                .tag(0)

            RoutersListTabView(service: service)
                .tabItem {
                    Label("الراوترات", systemImage: "server.rack")
                }
                .tag(1)

            StatsAndLogsTabView(service: service)
                .tabItem {
                    Label("الإحصائيات", systemImage: "chart.bar.doc.horizontal")
                }
                .tag(2)

            FullSettingsTabView(service: service)
                .tabItem {
                    Label("الإعدادات", systemImage: "gearshape.fill")
                }
                .tag(3)
        }
        .tint(.blue)
        .environment(\.layoutDirection, .rightToLeft)
        .task {
            if !service.isConnected {
                _ = await service.loginAndRefresh()
            }
        }
    }
}

// MARK: - 1. تبويب الشبكة الرئيسي (Dashboard)
struct DashboardTabView: View {
    @ObservedObject var service: RouterService
    @State private var searchText: String = ""
    @State private var filterMode: DeviceFilterMode = .all
    @State private var deviceToRename: NetworkDevice? = nil
    @State private var newNameInput: String = ""
    @State private var deviceForCustomSpeed: NetworkDevice? = nil
    @State private var customSpeedInput: String = "768"
    @State private var showAddManualDevice: Bool = false
    @State private var showRebootConfirm: Bool = false
    @State private var showQuickCalibrate: Bool = false
    @State private var calibrateInputGB: String = ""
    @State private var showWebUISheet: Bool = false

    private var filteredDevices: [NetworkDevice] {
        service.activeRouter.devices.filter { dev in
            let matchesFilter: Bool
            switch filterMode {
            case .all: matchesFilter = true
            case .online: matchesFilter = dev.isOnline
            case .throttled: matchesFilter = dev.isThrottled
            case .blocked: matchesFilter = dev.isBlocked
            }
            guard matchesFilter else { return false }
            if searchText.trimmingCharacters(in: .whitespaces).isEmpty { return true }
            let q = searchText.lowercased()
            return dev.displayName.lowercased().contains(q)
                || dev.ipAddress.lowercased().contains(q)
                || dev.macAddress.lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 10) {
                        // شريط حالة الاتصال إن وجد
                        if !service.statusMessage.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 6) {
                                    Image(systemName: "info.circle.fill")
                                        .foregroundColor(.orange)
                                    Text(service.statusMessage)
                                        .font(.caption2)
                                        .foregroundColor(.orange)
                                    Spacer()
                                }

                                HStack(spacing: 8) {
                                    Button(action: {
                                        Task { await service.runWebUIFallbackScrape() }
                                    }) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "arrow.triangle.2.circlepath.doc.on.clipboard")
                                            Text("تشغيل كشط WebUI البديل")
                                        }
                                        .font(.caption2.bold())
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.orange.opacity(0.25))
                                        .foregroundColor(.orange)
                                        .cornerRadius(6)
                                    }

                                    Button(action: { showWebUISheet = true }) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "globe.americas.fill")
                                            Text("فتح متصفح الراوتر والأزرار")
                                        }
                                        .font(.caption2.bold())
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.blue.opacity(0.25))
                                        .foregroundColor(.blue)
                                        .cornerRadius(6)
                                    }
                                }
                            }
                            .padding(8)
                            .background(Color(white: 0.12))
                            .cornerRadius(8)
                        }

                        // بطاقة الباقة الشاملة (مع دعم شبكة 4G والسرعة الحية لراوتر Huawei B311)
                        ComprehensiveQuotaCard(
                            router: service.activeRouter,
                            onCalibrateTap: {
                                calibrateInputGB = String(format: "%.1f", service.activeRouter.usedGB)
                                showQuickCalibrate = true
                            }
                        )

                        // شريط البحث والفلترة
                        VStack(spacing: 8) {
                            HStack(spacing: 8) {
                                HStack(spacing: 6) {
                                    Image(systemName: "magnifyingglass")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                    TextField("ابحث باسم الجهاز أو IP أو MAC...", text: $searchText)
                                        .font(.caption)
                                        .foregroundColor(.white)
                                }
                                .padding(8)
                                .background(Color(white: 0.11))
                                .cornerRadius(8)

                                Button(action: { showAddManualDevice = true }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "plus")
                                        Text("إضافة")
                                    }
                                    .font(.caption.bold())
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .background(Color(white: 0.15))
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                                }
                            }

                            Picker("فلترة", selection: $filterMode) {
                                ForEach(DeviceFilterMode.allCases) { mode in
                                    Text(mode.rawValue).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
                        }

                        // قائمة الأجهزة
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("الأجهزة (\(filteredDevices.count))")
                                    .font(.caption.bold())
                                    .foregroundColor(.gray)
                                Spacer()
                                if service.isLoading {
                                    ProgressView().scaleEffect(0.75)
                                }
                            }
                            .padding(.horizontal, 4)

                            if filteredDevices.isEmpty {
                                Text("لا توجد أجهزة مطابقة للفلتر الحالي")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 24)
                            } else {
                                ForEach(filteredDevices) { device in
                                    DeviceControlRow(
                                        device: device,
                                        service: service,
                                        onRename: {
                                            deviceToRename = device
                                            newNameInput = device.displayName
                                        },
                                        onCustomSpeed: {
                                            deviceForCustomSpeed = device
                                            customSpeedInput = "\(max(256, device.currentSpeedKbps))"
                                        }
                                    )
                                }
                            }
                        }
                    }
                    .padding(12)
                }
                .refreshable {
                    await service.loginAndRefresh()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // قائمة تبديل الراوتر السريعة
                ToolbarItem(placement: .navigationBarLeading) {
                    Menu {
                        ForEach(service.routers) { router in
                            Button(action: { service.selectRouter(router.id) }) {
                                HStack {
                                    Text(router.name)
                                    if let carrier = router.carrierName {
                                        Text("(\(carrier))")
                                    }
                                    if router.id == service.activeRouter.id {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "wifi.router.fill")
                                .font(.caption)
                                .foregroundColor(service.activeRouter.firmware == .huaweiB311 ? .orange : .blue)
                            Text(service.activeRouter.name)
                                .font(.subheadline.bold())
                                .foregroundColor(.white)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.gray)
                        }
                    }
                }

                // أزرار المتصفح البديل والتحديث وإعادة تشغيل الراوتر
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button(action: { showWebUISheet = true }) {
                        Image(systemName: "globe.americas.fill")
                            .font(.subheadline)
                            .foregroundColor(.orange)
                    }
                    Button(action: { Task { await service.loginAndRefresh() } }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.subheadline)
                            .foregroundColor(.blue)
                    }
                    Button(action: { showRebootConfirm = true }) {
                        Image(systemName: "power")
                            .font(.subheadline)
                            .foregroundColor(.red)
                    }
                }
            }
            // نافذة تسمية الجهاز
            .alert("تسمية الجهاز", isPresented: Binding(
                get: { deviceToRename != nil },
                set: { if !$0 { deviceToRename = nil } }
            )) {
                TextField("اسم الجهاز (مثال: شاشة الصالة)", text: $newNameInput)
                Button("حفظ") {
                    if let dev = deviceToRename {
                        service.renameDevice(dev, newName: newNameInput)
                    }
                }
                Button("إلغاء", role: .cancel) {}
            }
            // نافذة تحديد سرعة مخصصة بالكيلوبت
            .alert("تحديد سرعة مخصصة (Kbps)", isPresented: Binding(
                get: { deviceForCustomSpeed != nil },
                set: { if !$0 { deviceForCustomSpeed = nil } }
            )) {
                TextField("مثال: 768 أو 1500", text: $customSpeedInput)
                    .keyboardType(.numberPad)
                Button("تطبيق") {
                    if let dev = deviceForCustomSpeed, let speed = Int(customSpeedInput), speed > 0 {
                        Task { await service.setThrottle(dev, speedKbps: speed) }
                    }
                }
                Button("إلغاء", role: .cancel) {}
            }
            // نافذة المعايرة السريعة للاستهلاك
            .alert("ضبط الاستهلاك الحالي (GB)", isPresented: $showQuickCalibrate) {
                TextField("الجيجابايت المستهلكة حالياً", text: $calibrateInputGB)
                    .keyboardType(.decimalPad)
                Button("حفظ") {
                    if let val = Double(calibrateInputGB.replacingOccurrences(of: ",", with: ".")) {
                        var r = service.activeRouter
                        r.manualOffsetGB = max(0, val - r.accumulatedGB)
                        service.activeRouter = r
                    }
                }
                Button("إلغاء", role: .cancel) {}
            } message: {
                Text("أدخل إجمالي ما استهلكته من الباقة حتى اللحظة ليتم البناء عليه تلقائياً.")
            }
            // تأكيد إعادة تشغيل الراوتر
            .confirmationDialog(
                "هل تريد إعادة تشغيل (\(service.activeRouter.name)) الآن؟",
                isPresented: $showRebootConfirm,
                titleVisibility: .visible
            ) {
                Button("إعادة تشغيل الراوتر", role: .destructive) {
                    Task { await service.rebootActiveRouter() }
                }
                Button("إلغاء", role: .cancel) {}
            }
            // نافذة إضافة جهاز يدوياً
            .sheet(isPresented: $showAddManualDevice) {
                AddManualDeviceSheet(service: service)
            }
            // نافذة متصفح WebUI وكشط البيانات والضغط على الأزرار
            .sheet(isPresented: $showWebUISheet) {
                RouterWebUIView(service: service)
            }
        }
    }
}

// MARK: - بطاقة الباقة الشاملة
struct ComprehensiveQuotaCard: View {
    let router: RouterProfile
    var onCalibrateTap: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("استهلاك الباقة الشهرية")
                            .font(.caption.bold())
                            .foregroundColor(.white)

                        if let carrier = router.carrierName {
                            Text(carrier)
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.25))
                                .foregroundColor(.orange)
                                .cornerRadius(4)
                        }
                    }

                    HStack(spacing: 4) {
                        Text("يتجدد يوم \(router.renewalDay) • متبقي \(router.daysUntilRenewal) يوم")
                            .font(.system(size: 11))
                            .foregroundColor(.gray)

                        if let speed = router.liveSpeedFormatted {
                            Text("•")
                                .foregroundColor(.gray)
                            Text(speed)
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundColor(.cyan)
                        }
                    }
                }
                Spacer()
                Button(action: onCalibrateTap) {
                    HStack(spacing: 4) {
                        Image(systemName: "slider.horizontal.3")
                        Text("ضبط الاستهلاك")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(white: 0.18))
                    .foregroundColor(.blue)
                    .cornerRadius(6)
                }
            }

            // شريط النسبة
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(white: 0.18))
                        .frame(height: 8)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(progressColor)
                        .frame(width: max(0, min(geo.size.width, geo.size.width * CGFloat(router.usedPercentage / 100.0))), height: 8)
                }
            }
            .frame(height: 8)

            // الأرقام الثلاثية
            HStack(spacing: 8) {
                QuotaStatBox(
                    title: "المستهلك",
                    value: "\(String(format: "%.1f", router.usedGB)) GB",
                    sub: "\(Int(router.usedPercentage))% من \(Int(router.totalPlanGB))G",
                    color: .white
                )
                QuotaStatBox(
                    title: "المتبقي",
                    value: "\(String(format: "%.1f", router.remainingGB)) GB",
                    sub: "متاح للاستخدام",
                    color: progressColor
                )
                QuotaStatBox(
                    title: "المعدل الآمن يومياً",
                    value: "\(String(format: "%.1f", router.recommendedDailyGB)) GB",
                    sub: "لإكمال الشهر",
                    color: .green
                )
            }
        }
        .padding(12)
        .background(Color(white: 0.1))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(white: 0.16), lineWidth: 1)
        )
    }

    private var progressColor: Color {
        if router.usedPercentage >= 85 { return .red }
        if router.usedPercentage >= 70 { return .orange }
        return .blue
    }
}

struct QuotaStatBox: View {
    let title: String
    let value: String
    let sub: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10))
                .foregroundColor(.gray)
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(color)
                .lineLimit(1)
            Text(sub)
                .font(.system(size: 9))
                .foregroundColor(.gray)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color(white: 0.14))
        .cornerRadius(8)
    }
}

// MARK: - بطاقة التحكم في الجهاز
struct DeviceControlRow: View {
    let device: NetworkDevice
    @ObservedObject var service: RouterService
    var onRename: () -> Void
    var onCustomSpeed: () -> Void

    let speedPresets: [(label: String, kbps: Int)] = [
        ("256K", 256),
        ("512K", 512),
        ("1M", 1024),
        ("2M", 2048)
    ]

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(device.isBlocked ? Color.red : (device.isOnline ? Color.green : Color.gray))
                            .frame(width: 7, height: 7)

                        Text(device.displayName)
                            .font(.subheadline.bold())
                            .foregroundColor(.white)

                        Button(action: onRename) {
                            Image(systemName: "pencil")
                                .font(.caption2)
                                .foregroundColor(.blue)
                        }

                        Button(action: { service.toggleTrustDevice(device) }) {
                            Image(systemName: device.isTrusted ? "checkmark.shield.fill" : "shield")
                                .font(.caption2)
                                .foregroundColor(device.isTrusted ? .green : .gray)
                        }
                    }

                    HStack(spacing: 6) {
                        Text(device.ipAddress)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.gray)
                        Text("•")
                            .foregroundColor(.gray)
                        Text(device.macAddress)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.gray)
                    }
                }

                Spacer()

                // زر الفصل / إلغاء الفصل
                Button(action: { Task { await service.toggleBlock(device) } }) {
                    HStack(spacing: 4) {
                        Image(systemName: device.isBlocked ? "lock.open.fill" : "xmark.shield.fill")
                        Text(device.isBlocked ? "فك الحظر" : "فصل")
                    }
                    .font(.caption2.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(device.isBlocked ? Color.green.opacity(0.2) : Color.red.opacity(0.2))
                    .foregroundColor(device.isBlocked ? .green : .red)
                    .cornerRadius(6)
                }
            }

            // صف أزرار تحديد السرعة (تعمل لراوترات D-Link)
            if service.activeRouter.firmware != .huaweiB311 {
                HStack(spacing: 5) {
                    ForEach(speedPresets, id: \.kbps) { preset in
                        SpeedOptionButton(
                            title: preset.label,
                            isSelected: device.isThrottled && device.currentSpeedKbps == preset.kbps
                        ) {
                            Task { await service.setThrottle(device, speedKbps: preset.kbps) }
                        }
                    }

                    SpeedOptionButton(
                        title: isCustomSpeed ? "\(device.currentSpeedKbps)K" : "مخصص",
                        isSelected: isCustomSpeed
                    ) {
                        onCustomSpeed()
                    }

                    SpeedOptionButton(
                        title: "كاملة",
                        isSelected: !device.isThrottled || device.currentSpeedKbps == 0
                    ) {
                        Task { await service.setThrottle(device, speedKbps: 0) }
                    }
                }
            }
        }
        .padding(10)
        .background(Color(white: 0.1))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(device.isBlocked ? Color.red.opacity(0.4) : Color(white: 0.16), lineWidth: 1)
        )
    }

    private var isCustomSpeed: Bool {
        guard device.isThrottled && device.currentSpeedKbps > 0 else { return false }
        return ![256, 512, 1024, 2048].contains(device.currentSpeedKbps)
    }
}

struct SpeedOptionButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(isSelected ? Color.blue : Color(white: 0.17))
                .foregroundColor(.white)
                .cornerRadius(6)
        }
    }
}

// MARK: - نافذة إضافة جهاز يدوياً
struct AddManualDeviceSheet: View {
    @ObservedObject var service: RouterService
    @Environment(\.dismiss) var dismiss
    @State private var name: String = ""
    @State private var ip: String = "192.168.1."
    @State private var mac: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("بيانات الجهاز") {
                    TextField("اسم الجهاز (مثال: بلايستيشن)", text: $name)
                    TextField("عنوان IP (مثال: 192.168.1.25)", text: $ip)
                        .keyboardType(.numbersAndPunctuation)
                    TextField("عنوان MAC (مثال: AA:BB:CC:11:22:33)", text: $mac)
                        .textInputAutocapitalization(.characters)
                }
            }
            .navigationTitle("إضافة جهاز يدوياً")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("إلغاء") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("إضافة") {
                        service.addManualDevice(
                            name: name.isEmpty ? "جهاز مضاف" : name,
                            ip: ip,
                            mac: mac
                        )
                        dismiss()
                    }
                    .disabled(mac.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }
}
