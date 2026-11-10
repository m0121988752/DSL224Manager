import Foundation

// MARK: - نوع سوفتوير الراوتر
enum FirmwareProtocol: String, Codable, CaseIterable, Identifiable {
    case me110Boa = "D-Link ME_1.10 (CGI/Boa)"
    case revR1JsonRpc = "D-Link Rev.R1 (JSON-RPC 3.x)"
    case genericRealtek = "Realtek Standard (boaform)"
    case huaweiB311 = "Huawei B311 / HiLink 4G"

    var id: String { rawValue }
}

// MARK: - نموذج الجهاز المتصل أو المحفوظ
struct NetworkDevice: Identifiable, Codable, Hashable {
    var id: String { macAddress.uppercased() }
    var ipAddress: String
    var macAddress: String
    var originalHostname: String
    var customName: String?
    var isOnline: Bool
    var isBlocked: Bool
    var isThrottled: Bool
    var currentSpeedKbps: Int
    var isTrusted: Bool
    var firstSeen: Date
    var lastSeen: Date

    var displayName: String {
        if let custom = customName, !custom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return custom
        }
        if !originalHostname.isEmpty && originalHostname != "*" && originalHostname.lowercased() != "unknown" {
            return originalHostname
        }
        let lastOctet = ipAddress.components(separatedBy: ".").last ?? ""
        return "جهاز (\(lastOctet))"
    }

    var speedLabel: String {
        guard isThrottled && currentSpeedKbps > 0 else { return "كاملة" }
        if currentSpeedKbps >= 1024 && currentSpeedKbps % 1024 == 0 {
            return "\(currentSpeedKbps / 1024) ميجا"
        }
        return "\(currentSpeedKbps) ك.ب"
    }
}

// MARK: - سجل الاستهلاك اليومي
struct DailyUsageRecord: Identifiable, Codable, Hashable {
    var id: String { dateKey }
    var dateKey: String // yyyy-MM-dd
    var consumedGB: Double
}

// MARK: - ملف تعريف الراوتر الكامل (يدعم راوترات متعددة + Huawei B311)
struct RouterProfile: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String = "راوتر المنزل"
    var routerIP: String = "192.168.1.1"
    var username: String = "admin"
    var password: String = ""
    var firmware: FirmwareProtocol = .me110Boa

    // بيانات شبكة 4G / مشغل الشريحة (خاصة براوترات Huawei مثل B311)
    var carrierName: String? = nil
    var liveDownloadRateKbps: Double? = nil
    var liveUploadRateKbps: Double? = nil

    // إعدادات الباقة
    var totalPlanGB: Double = 140.0
    var renewalDay: Int = 1
    var manualOffsetGB: Double = 0.0
    var lastRecordedWANBytes: UInt64 = 0
    var accumulatedBytes: UInt64 = 0
    var lastResetMonth: Int = Calendar.current.component(.month, from: Date())
    var lastResetYear: Int = Calendar.current.component(.year, from: Date())
    var lastSyncDate: Date? = nil

    // إعدادات الإشعارات والتنبيهات
    var notifyOnNewDevice: Bool = true
    var notifyOnQuotaThreshold: Bool = true
    var alertThresholds: [Int] = [50, 75, 90, 95]
    var notifiedThresholds: [Int] = []

    // الأجهزة والأسماء المخصصة
    var devices: [NetworkDevice] = []
    var customDeviceNames: [String: String] = [:]
    var knownMacAddresses: [String] = []
    var dailyHistory: [DailyUsageRecord] = []

    // MARK: حسابات الباقة
    var accumulatedGB: Double {
        Double(accumulatedBytes) / (1024.0 * 1024.0 * 1024.0)
    }

    var usedGB: Double {
        max(0.0, manualOffsetGB + accumulatedGB)
    }

    var remainingGB: Double {
        max(0.0, totalPlanGB - usedGB)
    }

    var usedPercentage: Double {
        guard totalPlanGB > 0 else { return 0 }
        return min(100.0, (usedGB / totalPlanGB) * 100.0)
    }

    var daysUntilRenewal: Int {
        let cal = Calendar.current
        let now = Date()
        let currentDay = cal.component(.day, from: now)
        let clampedRenewal = min(max(1, renewalDay), 28)

        if currentDay < clampedRenewal {
            return clampedRenewal - currentDay
        } else {
            guard let nextMonth = cal.date(byAdding: .month, value: 1, to: now),
                  let nextRenewalDate = cal.date(from: DateComponents(
                    year: cal.component(.year, from: nextMonth),
                    month: cal.component(.month, from: nextMonth),
                    day: clampedRenewal
                  )) else {
                return 30 - currentDay + clampedRenewal
            }
            let diff = cal.dateComponents([.day], from: now, to: nextRenewalDate).day ?? 1
            return max(1, diff)
        }
    }

    var recommendedDailyGB: Double {
        let days = Double(max(1, daysUntilRenewal))
        return remainingGB / days
    }

    var onlineDevicesCount: Int {
        devices.filter { $0.isOnline }.count
    }

    var blockedDevicesCount: Int {
        devices.filter { $0.isBlocked }.count
    }

    var throttledDevicesCount: Int {
        devices.filter { $0.isThrottled }.count
    }

    var liveSpeedFormatted: String? {
        guard let down = liveDownloadRateKbps else { return nil }
        let up = liveUploadRateKbps ?? 0
        if down >= 1024 {
            return String(format: "⬇ %.1f MB/s • ⬆ %.0f KB/s", down / 1024.0, up)
        } else {
            return String(format: "⬇ %.0f KB/s • ⬆ %.0f KB/s", down, up)
        }
    }
}

// MARK: - نموذج سجل العمليات (Logs)
struct LogEntry: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var timestamp: Date = Date()
    var routerName: String
    var message: String
    var isError: Bool = false

    var timeString: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss"
        return fmt.string(from: timestamp)
    }
}

// MARK: - لقطة بيانات الودجت (Widget Snapshot)
struct WidgetSnapshot: Codable {
    var routerName: String
    var routerIP: String
    var carrierName: String?
    var liveSpeedFormatted: String?
    var usedGB: Double
    var remainingGB: Double
    var totalPlanGB: Double
    var usedPercentage: Double
    var daysUntilRenewal: Int
    var recommendedDailyGB: Double
    var onlineDevicesCount: Int
    var throttledDevicesCount: Int
    var blockedDevicesCount: Int
    var lastUpdated: Date

    static let placeholder = WidgetSnapshot(
        routerName: "راوتر المنزل",
        routerIP: "192.168.1.1",
        carrierName: "Orange EG",
        liveSpeedFormatted: "⬇ 2.4 MB/s",
        usedGB: 64.5,
        remainingGB: 75.5,
        totalPlanGB: 140.0,
        usedPercentage: 46.0,
        daysUntilRenewal: 14,
        recommendedDailyGB: 5.4,
        onlineDevicesCount: 4,
        throttledDevicesCount: 1,
        blockedDevicesCount: 0,
        lastUpdated: Date()
    )
}

// MARK: - التخزين المشترك بين التطبيق والودجت
enum SharedStorage {
    static let appGroupID = "group.com.personal.DSL224Manager"
    static let snapshotKey = "DSL224_WIDGET_SNAPSHOT_V2"
    static let profilesKey = "DSL224_PROFILES_LIST_V2"
    static let activeIDKey = "DSL224_ACTIVE_ROUTER_ID_V2"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    static func saveWidgetSnapshot(_ snapshot: WidgetSnapshot) {
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: snapshotKey)
            UserDefaults.standard.set(data, forKey: snapshotKey)
        }
    }

    static func loadWidgetSnapshot() -> WidgetSnapshot {
        if let data = defaults.data(forKey: snapshotKey) ?? UserDefaults.standard.data(forKey: snapshotKey),
           let decoded = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) {
            return decoded
        }
        return .placeholder
    }
}
