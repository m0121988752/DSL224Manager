import SwiftUI

struct ContentView: View {
    @StateObject private var service = RouterService()
    @State private var showSettings = false
    @State private var deviceToRename: NetworkDevice?
    @State private var newNameInput = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if !service.isConnected {
                    // شاشة تسجيل الدخول المدمجة
                    VStack(spacing: 16) {
                        Image(systemName: "wifi.router")
                            .font(.system(size: 48))
                            .foregroundColor(.blue)

                        Text("إدارة راوتر D-Link")
                            .font(.headline)
                            .foregroundColor(.white)

                        VStack(spacing: 8) {
                            TextField("عنوان IP الراوتر", text: $service.routerIP)
                                .textFieldStyle(.roundedBorder)
                                .multilineTextAlignment(.center)

                            SecureField("كلمة سر الراوتر", text: $service.password)
                                .textFieldStyle(.roundedBorder)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: 280)

                        if !service.statusMessage.isEmpty {
                            Text(service.statusMessage)
                                .font(.caption)
                                .foregroundColor(.red)
                        }

                        Button(action: { Task { await service.login() } }) {
                            if service.isLoading {
                                ProgressView().tint(.white)
                                    .frame(maxWidth: 280)
                                    .padding(.vertical, 10)
                            } else {
                                Text("اتصال")
                                    .fontWeight(.bold)
                                    .frame(maxWidth: 280)
                                    .padding(.vertical, 10)
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                            }
                        }
                    }
                    .padding()
                } else {
                    // الشاشة الرئيسية لإدارة الشبكة
                    ScrollView {
                        VStack(spacing: 12) {
                            // بطاقة استهلاك الباقة
                            QuotaCard(service: service)

                            // قائمة الأجهزة المتصلة
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("الأجهزة المتصلة (\(service.devices.count))")
                                        .font(.caption.bold())
                                        .foregroundColor(.gray)
                                    Spacer()
                                    Button(action: { Task { await service.refreshData() } }) {
                                        Image(systemName: "arrow.clockwise")
                                            .font(.caption)
                                            .foregroundColor(.blue)
                                    }
                                }
                                .padding(.horizontal, 4)

                                ForEach(service.devices) { device in
                                    DeviceRow(device: device, service: service) {
                                        deviceToRename = device
                                        newNameInput = device.displayName
                                    }
                                }
                            }
                        }
                        .padding(12)
                    }
                }
            }
            .navigationTitle(service.isConnected ? "شبكتي" : "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if service.isConnected {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(action: { showSettings = true }) {
                            Image(systemName: "gearshape")
                                .foregroundColor(.white)
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: { Task { await service.reboot() } }) {
                            Image(systemName: "arrow.clockwise.circle")
                                .foregroundColor(.red)
                        }
                    }
                }
            }
            // نافذة الإعدادات
            .sheet(isPresented: $showSettings) {
                SettingsView(service: service)
            }
            // نافذة تسمية الأجهزة
            .alert("تسمية الجهاز", isPresented: Binding(
                get: { deviceToRename != nil },
                set: { if !$0 { deviceToRename = nil } }
            )) {
                TextField("اسم الجهاز", text: $newNameInput)
                Button("حفظ") {
                    if let dev = deviceToRename {
                        service.renameDevice(device: dev, newName: newNameInput)
                    }
                }
                Button("إلغاء", role: .cancel) {}
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }
}

// بطاقة استهلاك الباقة الشهرية
struct QuotaCard: View {
    @ObservedObject var service: RouterService

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("استهلاك الباقة (تجديد يوم \(service.quota.renewalDay))")
                    .font(.caption)
                    .foregroundColor(.gray)
                Spacer()
                Text("باقة \(Int(service.quota.totalPlanGB)) جيجا")
                    .font(.caption.bold())
                    .foregroundColor(.white)
            }

            // شريط التقدم
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(white: 0.18))
                        .frame(height: 8)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(progressColor)
                        .frame(width: max(0, min(geo.size.width, geo.size.width * CGFloat(service.usedPercentage / 100.0))), height: 8)
                }
            }
            .frame(height: 8)

            HStack {
                Text("مستهلك: **\(String(format: "%.1f", service.usedGB)) GB** (\(Int(service.usedPercentage))%)")
                    .font(.caption2)
                    .foregroundColor(.white)
                Spacer()
                Text("متبقي: **\(String(format: "%.1f", service.remainingGB)) GB**")
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
        }
        .padding(12)
        .background(Color(white: 0.12))
        .cornerRadius(10)
    }

    private var progressColor: Color {
        if service.usedPercentage >= 85 { return .red }
        if service.usedPercentage >= 70 { return .orange }
        return .blue
    }
}

// بطاقة كل جهاز متصل
struct DeviceRow: View {
    let device: NetworkDevice
    @ObservedObject var service: RouterService
    var onRename: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(device.displayName)
                            .font(.subheadline.bold())
                            .foregroundColor(.white)
                        Button(action: onRename) {
                            Image(systemName: "pencil")
                                .font(.caption2)
                                .foregroundColor(.blue)
                        }
                    }
                    Text("\(device.ipAddress) • \(device.macAddress)")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
                Spacer()

                Button(action: { Task { await service.toggleBlock(device: device) } }) {
                    Text(device.isBlocked ? "إلغاء الفصل" : "فصل")
                        .font(.caption2.bold())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(device.isBlocked ? Color.green.opacity(0.2) : Color.red.opacity(0.2))
                        .foregroundColor(device.isBlocked ? .green : .red)
                        .cornerRadius(6)
                }
            }

            // أزرار التحكم بالسرعة
            HStack(spacing: 6) {
                SpeedButton(title: "512 ك.ب", isSelected: device.currentSpeedKbps == 512) {
                    Task { await service.setThrottle(device: device, speedKbps: 512) }
                }
                SpeedButton(title: "1 ميجا", isSelected: device.currentSpeedKbps == 1024) {
                    Task { await service.setThrottle(device: device, speedKbps: 1024) }
                }
                SpeedButton(title: "كاملة", isSelected: !device.isThrottled) {
                    Task { await service.setThrottle(device: device, speedKbps: 0) }
                }
            }
        }
        .padding(10)
        .background(Color(white: 0.1))
        .cornerRadius(10)
    }
}

struct SpeedButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption2.bold())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(isSelected ? Color.blue : Color(white: 0.18))
                .foregroundColor(.white)
                .cornerRadius(6)
        }
    }
}

// نافذة الإعدادات لتحديد الباقة وميعاد التجديد
struct SettingsView: View {
    @ObservedObject var service: RouterService
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("بيانات الباقة الشهرية") {
                    HStack {
                        Text("سعة الباقة (جيجابايت)")
                        Spacer()
                        TextField("140", value: $service.quota.totalPlanGB, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }

                    HStack {
                        Text("يوم التجديد شهرياً")
                        Spacer()
                        Picker("", selection: $service.quota.renewalDay) {
                            ForEach(1...31, id: \.self) { day in
                                Text("\(day)").tag(day)
                            }
                        }
                    }

                    HStack {
                        Text("تعديل الاستهلاك الحالي (GB)")
                        Spacer()
                        TextField("0", value: $service.quota.manualOffsetGB, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                }

                Section("إعدادات الراوتر") {
                    HStack {
                        Text("عنوان IP الراوتر")
                        Spacer()
                        TextField("192.168.1.1", text: $service.routerIP)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
            .navigationTitle("الإعدادات")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("حفظ") {
                    service.saveSettings()
                    dismiss()
                }
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }
}
