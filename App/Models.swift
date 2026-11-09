import Foundation

// نموذج بيانات الجهاز المتصل بالراوتر
struct NetworkDevice: Identifiable, Codable, Hashable {
    var id: String { macAddress }
    var ipAddress: String
    var macAddress: String
    var customName: String?
    var isBlocked: Bool
    var isThrottled: Bool
    var currentSpeedKbps: Int

    var displayName: String {
        if let custom = customName, !custom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return custom
        }
        let lastOctet = ipAddress.components(separatedBy: ".").last ?? ""
        return "جهاز (\(lastOctet))"
    }
}

// نموذج إعدادات الباقة والتنبيهات
struct QuotaConfig: Codable {
    var totalPlanGB: Double = 140.0
    var renewalDay: Int = 1
    var manualOffsetGB: Double = 0.0
    var lastRecordedBytes: UInt64 = 0
    var accumulatedBytes: UInt64 = 0
    var lastResetMonth: Int = Calendar.current.component(.month, from: Date())
    
    var alertThresholds: [Int] = [50, 75, 90]
    var notifiedThresholds: [Int] = []
    var knownMacAddresses: [String] = []
    var customDeviceNames: [String: String] = [:]
}
