import SwiftUI

// MARK: - نموذج قالب إعدادات الراوتر الجاهز (Router Preset Template)
struct RouterPreset: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var manufacturer: String
    var defaultIP: String
    var firmware: FirmwareProtocol
    var description: String
    var webUIPath: String = ""

    // محددات No-Code المخصصة
    var customUsageSelector: String = ""
    var customUsageRegex: String = ""
    var customUsageUnit: String = "Auto"
    var customDeviceTableSelector: String = ""
    var customRebootButtonSelector: String = ""
    var customUsernameSelector: String = ""
    var customPasswordSelector: String = ""
    var customLoginButtonSelector: String = ""
}

// MARK: - مدير ومكتبة القوالب الجاهزة والتصدير/الاستيراد
struct RouterPresetsManager {
    static let builtinPresets: [RouterPreset] = [
        RouterPreset(
            id: "dlink_dsl224",
            name: "D-Link DSL-224 (ME_1.10 Boa)",
            manufacturer: "D-Link",
            defaultIP: "192.168.1.1",
            firmware: .me110Boa,
            description: "راوتر D-Link DSL-224 بنظام Boa الافتراضي (WE / فودافون / أورنج)",
            webUIPath: "",
            customUsageSelector: "#wan_bytes, .traffic-stat, td.bytes_val, table.status_table td",
            customUsageRegex: #"(\d{7,16})"#,
            customUsageUnit: "Bytes",
            customDeviceTableSelector: "#dhcp_client_table, tr.device-row, table.status_table",
            customRebootButtonSelector: "#btn_reboot, input[value*='Reboot' i]",
            customUsernameSelector: "input[name='username'], #f_username",
            customPasswordSelector: "input[name='password'], #f_password",
            customLoginButtonSelector: "#loginbtn, input[type='submit']"
        ),
        RouterPreset(
            id: "zte_h168n",
            name: "ZTE ZXHN H168N / H188A",
            manufacturer: "ZTE",
            defaultIP: "192.168.1.1",
            firmware: .genericRealtek,
            description: "راوتر VDSL الأكثر انتشاراً من WE وفودافون وأورنج في مصر والشرق الأوسط",
            webUIPath: "",
            customUsageSelector: "#wan_bytes, #div_wan_traffic, td.bytes_val, td.traffic_val",
            customUsageRegex: #"([0-9\.]+)\s*(GB|MB|KB)"#,
            customUsageUnit: "Auto",
            customDeviceTableSelector: "#table_dhcp_clients, #dev_table, tr.client_item",
            customRebootButtonSelector: "#btn_reboot, #reboot, input[value='Reboot']",
            customUsernameSelector: "#username, input[name='Username']",
            customPasswordSelector: "#password, input[name='Password']",
            customLoginButtonSelector: "#loginbtn, input[name='login_submit']"
        ),
        RouterPreset(
            id: "huawei_b311",
            name: "Huawei B311-221 (HiLink 4G)",
            manufacturer: "Huawei",
            defaultIP: "192.168.8.1",
            firmware: .huaweiB311,
            description: "راوترات هواوي 4G الهوائية لشركات الاتصالات (Orange, Zain, STC, WE)",
            webUIPath: "",
            customUsageSelector: "#traffic_used, span.data_used, div.flow_val",
            customUsageRegex: #"([0-9\.]+)\s*(GB|MB)"#,
            customUsageUnit: "Auto",
            customDeviceTableSelector: "#device_table, .dev-list, div.host_list",
            customRebootButtonSelector: "#reboot_apply_button, #btn_reboot",
            customUsernameSelector: "#username, input[name='username']",
            customPasswordSelector: "#password, input[name='password']",
            customLoginButtonSelector: "#login_btn, #btnLogin"
        ),
        RouterPreset(
            id: "vodafone_h300s",
            name: "Vodafone VDSL (H300s / DG8045)",
            manufacturer: "Vodafone / Sercomm",
            defaultIP: "192.168.1.1",
            firmware: .genericRealtek,
            description: "راوتر فودافون VDSL المنزلي الشهير H300s وراوترات الشريحة",
            webUIPath: "",
            customUsageSelector: "#Internet_Stats, .traffic-container, td.stat-data",
            customUsageRegex: #"([0-9\.]+)\s*(GB|MB)"#,
            customUsageUnit: "Auto",
            customDeviceTableSelector: "#Ethernet_Clients, #WLAN_Clients, .device-list",
            customRebootButtonSelector: "#Reboot_btn, button[name='Reboot']",
            customUsernameSelector: "input[name='user'], #user",
            customPasswordSelector: "input[name='pass'], #pass",
            customLoginButtonSelector: "#loginBtn, button[type='submit']"
        ),
        RouterPreset(
            id: "tplink_vr600",
            name: "TP-Link Archer / VR600",
            manufacturer: "TP-Link",
            defaultIP: "192.168.1.1",
            firmware: .genericRealtek,
            description: "راوترات تي بي لينك VDSL الحديثة والراوترات الهوائية",
            webUIPath: "",
            customUsageSelector: "#traffic_status, #wan_rx_bytes, .stat-value",
            customUsageRegex: #"([0-9\.]+)\s*(GB|MB|KB)"#,
            customUsageUnit: "Auto",
            customDeviceTableSelector: "#client_list_table, #dhcpTable, tr.grid-row",
            customRebootButtonSelector: "#reboot_button, #btn_reboot, .reboot-btn",
            customUsernameSelector: "input[name='userName'], #userName",
            customPasswordSelector: "input[name='pcPassword'], #pcPassword",
            customLoginButtonSelector: "#login_button, .login-btn"
        ),
        RouterPreset(
            id: "orange_flybox_mf283",
            name: "Orange Home 4G Flybox (MF283+)",
            manufacturer: "ZTE / Orange",
            defaultIP: "192.168.0.1",
            firmware: .genericRealtek,
            description: "راوتر أورنج الهوائي المنزلي Home 4G (موديل ZTE MF283+)",
            webUIPath: "",
            customUsageSelector: "#traffic_data, #traffic_flow_data, .flow-data",
            customUsageRegex: #"([0-9\.]+)\s*(GB|MB)"#,
            customUsageUnit: "Auto",
            customDeviceTableSelector: "#connected_dev_list, #devList, tr.dev_item",
            customRebootButtonSelector: "#restart_btn, input[value='Restart']",
            customUsernameSelector: "input[name='user'], #txtUser",
            customPasswordSelector: "input[name='password'], #txtPwd",
            customLoginButtonSelector: "#btnLogin, input[value='Login']"
        )
    ]

    // تصدير قالب راوتر إلى JSON آمن (تجريد كلمة المرور لحماية الخصوصية)
    static func exportTemplate(from profile: RouterProfile) -> String {
        let fwKey: String
        switch profile.firmware {
        case .huaweiB311: fwKey = "HUAWEI_B311"
        case .me110Boa: fwKey = "ME110_BOA"
        case .revR1JsonRpc: fwKey = "REV_R1"
        case .genericRealtek: fwKey = "GENERIC_REALTEK"
        }

        let exportDict: [String: Any] = [
            "dsl224_template_version": 1,
            "name": profile.name,
            "defaultIP": profile.routerIP,
            "firmware": profile.firmware.rawValue,
            "firmwareKey": fwKey,
            "webUIPath": profile.webUIPath,
            "customUsageSelector": profile.customUsageSelector,
            "customUsageRegex": profile.customUsageRegex,
            "customUsageUnit": profile.customUsageUnit,
            "customDeviceTableSelector": profile.customDeviceTableSelector,
            "customRebootButtonSelector": profile.customRebootButtonSelector,
            "customUsernameSelector": profile.customUsernameSelector,
            "customPasswordSelector": profile.customPasswordSelector,
            "customLoginButtonSelector": profile.customLoginButtonSelector
        ]

        if let data = try? JSONSerialization.data(withJSONObject: exportDict, options: [.prettyPrinted]),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return ""
    }

    // استيراد قالب راوتر من كود JSON وتطبيقه على الراوتر المحدد
    static func importTemplate(from jsonString: String, into profile: inout RouterProfile) -> Bool {
        guard let data = jsonString.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8),
              let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return false
        }

        if let name = dict["name"] as? String, !name.isEmpty {
            profile.name = name
        }
        if let ip = dict["defaultIP"] as? String, !ip.isEmpty {
            profile.routerIP = ip
        } else if let ip = dict["routerIP"] as? String, !ip.isEmpty {
            profile.routerIP = ip
        }

        // دعم مفتاح المنصتين المشترك firmwareKey ثم firmware
        if let fwKey = dict["firmwareKey"] as? String {
            switch fwKey {
            case "HUAWEI_B311": profile.firmware = .huaweiB311
            case "ME110_BOA": profile.firmware = .me110Boa
            case "REV_R1": profile.firmware = .revR1JsonRpc
            default: profile.firmware = .genericRealtek
            }
        } else if let fwStr = dict["firmware"] as? String {
            if let direct = FirmwareProtocol(rawValue: fwStr) {
                profile.firmware = direct
            } else if fwStr.contains("B311") || fwStr.contains("Huawei") {
                profile.firmware = .huaweiB311
            } else if fwStr.contains("224") || fwStr.contains("Boa") {
                profile.firmware = .me110Boa
            } else {
                profile.firmware = .genericRealtek
            }
        }
        if let path = dict["webUIPath"] as? String {
            profile.webUIPath = path
        }

        // محددات No-Code
        if let usageSel = dict["customUsageSelector"] as? String {
            profile.customUsageSelector = usageSel
        }
        if let usageReg = dict["customUsageRegex"] as? String {
            profile.customUsageRegex = usageReg
        }
        if let usageUnit = dict["customUsageUnit"] as? String {
            profile.customUsageUnit = usageUnit
        }
        if let devSel = dict["customDeviceTableSelector"] as? String {
            profile.customDeviceTableSelector = devSel
        }
        if let rebootSel = dict["customRebootButtonSelector"] as? String {
            profile.customRebootButtonSelector = rebootSel
        }
        if let userSel = dict["customUsernameSelector"] as? String {
            profile.customUsernameSelector = userSel
        }
        if let passSel = dict["customPasswordSelector"] as? String {
            profile.customPasswordSelector = passSel
        }
        if let loginSel = dict["customLoginButtonSelector"] as? String {
            profile.customLoginButtonSelector = loginSel
        }

        return true
    }

    // تطبيق قالب جاهز على الراوتر
    static func applyPreset(_ preset: RouterPreset, to profile: inout RouterProfile) {
        profile.name = preset.name
        profile.routerIP = preset.defaultIP
        profile.firmware = preset.firmware
        profile.webUIPath = preset.webUIPath
        profile.customUsageSelector = preset.customUsageSelector
        profile.customUsageRegex = preset.customUsageRegex
        profile.customUsageUnit = preset.customUsageUnit
        profile.customDeviceTableSelector = preset.customDeviceTableSelector
        profile.customRebootButtonSelector = preset.customRebootButtonSelector
        profile.customUsernameSelector = preset.customUsernameSelector
        profile.customPasswordSelector = preset.customPasswordSelector
        profile.customLoginButtonSelector = preset.customLoginButtonSelector
    }
}

// MARK: - شاشة تصفح مكتبة القوالب الجاهزة وتصدير/استيراد الإعدادات (Presets Library Sheet)
struct PresetsLibrarySheet: View {
    @ObservedObject var service: RouterService
    var onPresetApplied: () -> Void = {}
    var onSelectPreset: ((RouterPreset) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    @State private var toastMessage: String? = nil
    @State private var showImportDialog = false
    @State private var importInputText = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // إشعار أو تنبيه
                        if let msg = toastMessage {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text(msg)
                                    .font(.caption.bold())
                                    .foregroundColor(.white)
                                Spacer()
                                Button(action: { toastMessage = nil }) {
                                    Image(systemName: "xmark")
                                        .font(.caption2)
                                        .foregroundColor(.gray)
                                }
                            }
                            .padding(10)
                            .background(Color.green.opacity(0.2))
                            .cornerRadius(8)
                        }

                        // بطاقة إجراءات المشاركة والاستيراد السريع
                        VStack(alignment: .leading, spacing: 10) {
                            Text("مشاركة واستيراد القوالب (Share & Import)")
                                .font(.caption.bold())
                                .foregroundColor(.gray)

                            HStack(spacing: 10) {
                                Button(action: {
                                    let json = RouterPresetsManager.exportTemplate(from: service.activeRouter)
                                    UIPasteboard.general.string = json
                                    toastMessage = "تم نسخ قالب راوترك للحافظة بنجاح! يمكنك مشاركته الآن"
                                }) {
                                    HStack {
                                        Image(systemName: "square.and.arrow.up")
                                        Text("تصدير ومشاركة قالبي")
                                    }
                                    .font(.caption.bold())
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(Color.blue.opacity(0.25))
                                    .foregroundColor(.blue)
                                    .cornerRadius(8)
                                }

                                Button(action: {
                                    if let clip = UIPasteboard.general.string, !clip.isEmpty {
                                        var r = service.activeRouter
                                        if RouterPresetsManager.importTemplate(from: clip, into: &r) {
                                            if let onSelect = onSelectPreset {
                                                let p = RouterPreset(
                                                    id: "imported_\(UUID().uuidString.prefix(6))",
                                                    name: r.name,
                                                    manufacturer: "Custom",
                                                    defaultIP: r.routerIP,
                                                    firmware: r.firmware,
                                                    description: "قالب مستورد من الحافظة",
                                                    webUIPath: r.webUIPath,
                                                    customUsageSelector: r.customUsageSelector,
                                                    customUsageRegex: r.customUsageRegex,
                                                    customUsageUnit: r.customUsageUnit,
                                                    customDeviceTableSelector: r.customDeviceTableSelector,
                                                    customRebootButtonSelector: r.customRebootButtonSelector,
                                                    customUsernameSelector: r.customUsernameSelector,
                                                    customPasswordSelector: r.customPasswordSelector,
                                                    customLoginButtonSelector: r.customLoginButtonSelector
                                                )
                                                onSelect(p)
                                                dismiss()
                                            } else {
                                                service.updateRouter(r)
                                                service.saveAllProfiles()
                                                toastMessage = "تم استيراد القالب من الحافظة وتطبيقه بنجاح"
                                                onPresetApplied()
                                            }
                                        } else {
                                            toastMessage = "النص الموجود في الحافظة ليس قالب راوتر صالحاً"
                                        }
                                    } else {
                                        toastMessage = "الحافظة فارغة! انسخ كود القالب أولاً"
                                    }
                                }) {
                                    HStack {
                                        Image(systemName: "square.and.arrow.down")
                                        Text("استيراد من الحافظة")
                                    }
                                    .font(.caption.bold())
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(Color.purple.opacity(0.25))
                                    .foregroundColor(.purple)
                                    .cornerRadius(8)
                                }
                            }
                        }
                        .padding(14)
                        .background(Color(white: 0.12))
                        .cornerRadius(12)

                        // قائمة القوالب الجاهزة
                        Text("قوالب الراوترات المعتمدة الجاهزة (\(RouterPresetsManager.builtinPresets.count))")
                            .font(.caption.bold())
                            .foregroundColor(.gray)

                        VStack(spacing: 12) {
                            ForEach(RouterPresetsManager.builtinPresets) { preset in
                                PresetItemCard(preset: preset) {
                                    if let onSelect = onSelectPreset {
                                        onSelect(preset)
                                        dismiss()
                                    } else {
                                        var r = service.activeRouter
                                        RouterPresetsManager.applyPreset(preset, to: &r)
                                        service.updateRouter(r)
                                        service.saveAllProfiles()
                                        toastMessage = "تم تطبيق قالب [\(preset.name)] بنجاح"
                                        onPresetApplied()
                                    }
                                }
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("مكتبة قوالب الراوترات")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("تم") { dismiss() }
                }
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }
}

// MARK: - بطاقة عرض القالب الجاهز
struct PresetItemCard: View {
    let preset: RouterPreset
    let onApply: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(preset.name)
                        .font(.subheadline.bold())
                        .foregroundColor(.white)

                    Text("\(preset.manufacturer) • \(preset.defaultIP)")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }

                Spacer()

                Text(preset.manufacturer)
                    .font(.caption2.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.blue.opacity(0.2))
                    .foregroundColor(.blue)
                    .cornerRadius(6)
            }

            Text(preset.description)
                .font(.caption)
                .foregroundColor(Color(white: 0.75))
                .lineLimit(2)

            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.caption2)
                        .foregroundColor(.green)
                    Text("جاهز ومُعد مسبقاً")
                        .font(.caption2)
                        .foregroundColor(.green)
                }

                Spacer()

                Button(action: onApply) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle.fill")
                        Text("تطبيق هذا القالب")
                    }
                    .font(.caption.bold())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.green)
                    .foregroundColor(.black)
                    .cornerRadius(8)
                }
            }
        }
        .padding(14)
        .background(Color(white: 0.12))
        .cornerRadius(12)
    }
}
