import SwiftUI

// MARK: - نتيجة الكشف التلقائي عن الراوتر
struct DetectedRouterResult {
    var ip: String
    var modelName: String
    var firmware: FirmwareProtocol
    var matchedPreset: RouterPreset?
    var details: String
}

// MARK: - معالج الإعداد الذكي لأول مرة (Setup Wizard)
struct SetupWizardView: View {
    @ObservedObject var service: RouterService
    var onFinish: () -> Void

    @State private var currentStep: Int = 1
    @State private var isDetecting: Bool = false
    @State private var detectionResult: DetectedRouterResult? = nil
    @State private var detectionStatus: String = ""

    // بيانات الخطوة 1 و 2
    @State private var routerName: String = "راوتر المنزل"
    @State private var routerIP: String = "192.168.1.1"
    @State private var selectedFirmware: FirmwareProtocol = .me110Boa
    @State private var username: String = "admin"
    @State private var password: String = ""
    @State private var isPasswordVisible: Bool = false

    // فحص الاتصال في الخطوة 2
    @State private var isTestingLogin: Bool = false
    @State private var testLoginMessage: String = ""
    @State private var isLoginSuccess: Bool? = nil

    // بيانات الخطوة 3 (الباقة)
    @State private var totalPlanGB: String = "140"
    @State private var renewalDay: Int = 1
    @State private var currentUsedGB: String = "0"

    private let commonPlanSizes = ["140", "200", "250", "300", "400", "600"]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    // مؤشر الخطوات بالأعلى
                    stepsHeaderView
                        .padding(.vertical, 12)
                        .background(Color(white: 0.1))

                    ScrollView {
                        VStack(spacing: 16) {
                            switch currentStep {
                            case 1:
                                stepOneAutoDetectView
                            case 2:
                                stepTwoCredentialsView
                            case 3:
                                stepThreeQuotaView
                            case 4:
                                stepFourSummaryView
                            default:
                                EmptyView()
                            }
                        }
                        .padding(16)
                    }

                    // أزرار التنقل بالأسفل
                    bottomNavigationButtons
                        .padding(16)
                        .background(Color(white: 0.08))
                }
            }
            .navigationTitle("معالج الإعداد الذكي 🪄")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("تخطي") {
                        UserDefaults.standard.set(true, forKey: "hasCompletedWizard")
                        onFinish()
                    }
                    .font(.caption)
                    .foregroundColor(.gray)
                }
            }
            .onAppear {
                // إذا لم يتم الكشف مسبقاً، نشغل الكشف التلقائي مباشرة
                if detectionResult == nil {
                    runAutoDetection()
                }
            }
        }
    }

    // MARK: - مؤشر الخطوات
    private var stepsHeaderView: some View {
        HStack(spacing: 0) {
            stepIndicatorItem(number: 1, title: "الكشف", icon: "antenna.radiowaves.left.and.right")
            stepConnectorLine(isDone: currentStep > 1)
            stepIndicatorItem(number: 2, title: "الدخول", icon: "key.fill")
            stepConnectorLine(isDone: currentStep > 2)
            stepIndicatorItem(number: 3, title: "الباقة", icon: "chart.pie.fill")
            stepConnectorLine(isDone: currentStep > 3)
            stepIndicatorItem(number: 4, title: "جاهز", icon: "checkmark.seal.fill")
        }
        .padding(.horizontal, 16)
    }

    private func stepIndicatorItem(number: Int, title: String, icon: String) -> some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(currentStep >= number ? (currentStep == number ? Color.blue : Color.green) : Color(white: 0.2))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
            }
            Text(title)
                .font(.system(size: 10, weight: currentStep == number ? .bold : .regular))
                .foregroundColor(currentStep == number ? .white : .gray)
        }
        .frame(maxWidth: .infinity)
    }

    private func stepConnectorLine(isDone: Bool) -> some View {
        Rectangle()
            .fill(isDone ? Color.green : Color(white: 0.2))
            .frame(height: 2)
            .frame(maxWidth: 30)
            .padding(.bottom, 16)
    }

    // MARK: - الخطوة 1: الكشف التلقائي عن الراوتر
    private var stepOneAutoDetectView: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("الخطوة 1: كشف الراوتر المتصل")
                    .font(.headline.bold())
                    .foregroundColor(.white)
                Text("يقوم التطبيق بفحص عنوان البوابة (Gateway) والتعرف على طراز الراوتر ومواصفاته برمجياً.")
                    .font(.caption)
                    .foregroundColor(.gray)
            }

            // بطاقة حالة الكشف
            VStack(spacing: 12) {
                if isDetecting {
                    HStack(spacing: 10) {
                        ProgressView()
                            .tint(.blue)
                        Text(detectionStatus.isEmpty ? "جارِ فحص عناوين الشبكة المحلية..." : detectionStatus)
                            .font(.caption)
                            .foregroundColor(.cyan)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity)
                    .background(Color(white: 0.14))
                    .cornerRadius(10)
                } else if let res = detectionResult {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("تم اكتشاف الراوتر بنجاح!")
                                .font(.subheadline.bold())
                                .foregroundColor(.green)
                            Spacer()
                            Text(res.ip)
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(.blue)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.2))
                                .cornerRadius(4)
                        }

                        Text("الطراز المقترح: \(res.modelName)")
                            .font(.caption.bold())
                            .foregroundColor(.white)

                        Text(res.details)
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                    .padding(12)
                    .background(Color.green.opacity(0.12))
                    .cornerRadius(10)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.green.opacity(0.4), lineWidth: 1))
                } else {
                    Button(action: runAutoDetection) {
                        HStack {
                            Image(systemName: "sparkles")
                            Text("بدء الكشف التلقائي عن الراوتر الآن")
                                .fontWeight(.bold)
                        }
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.blue.opacity(0.25))
                        .foregroundColor(.blue)
                        .cornerRadius(8)
                    }
                }
            }

            Divider().background(Color(white: 0.2))

            // الحقول اليدوية للتأكيد أو التعديل
            VStack(alignment: .leading, spacing: 10) {
                Text("تأكيد أو تعديل المواصفات يدويّاً:")
                    .font(.caption.bold())
                    .foregroundColor(.gray)

                VStack(alignment: .leading, spacing: 4) {
                    Text("اسم الراوتر").font(.caption2).foregroundColor(.gray)
                    TextField("اسم الراوتر", text: $routerName)
                        .font(.subheadline)
                        .padding(10)
                        .background(Color(white: 0.14))
                        .cornerRadius(8)
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("عنوان IP الافتراضي").font(.caption2).foregroundColor(.gray)
                    TextField("192.168.1.1", text: $routerIP)
                        .font(.subheadline)
                        .keyboardType(.numbersAndPunctuation)
                        .padding(10)
                        .background(Color(white: 0.14))
                        .cornerRadius(8)
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("نظام وبروتوكول الراوتر").font(.caption2).foregroundColor(.gray)
                    Picker("البروتوكول", selection: $selectedFirmware) {
                        ForEach(FirmwareProtocol.allCases) { fw in
                            Text(fw.rawValue).tag(fw)
                        }
                    }
                    .pickerStyle(.menu)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(white: 0.14))
                    .cornerRadius(8)
                }
            }
        }
    }

    // MARK: - الخطوة 2: بيانات الدخول واختبار الاتصال اللحظي
    private var stepTwoCredentialsView: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("الخطوة 2: بيانات الدخول واختبار الاتصال")
                    .font(.headline.bold())
                    .foregroundColor(.white)
                Text("أدخل اسم المستخدم وكلمة السر المطبوعة على ظهر الراوتر أو التي قمت بتعيينها.")
                    .font(.caption)
                    .foregroundColor(.gray)
            }

            VStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("اسم المستخدم").font(.caption2).foregroundColor(.gray)
                    TextField("admin", text: $username)
                        .font(.subheadline)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(10)
                        .background(Color(white: 0.14))
                        .cornerRadius(8)
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("كلمة المرور").font(.caption2).foregroundColor(.gray)
                    HStack {
                        if isPasswordVisible {
                            TextField("كلمة مرور الراوتر", text: $password)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        } else {
                            SecureField("كلمة مرور الراوتر", text: $password)
                        }
                        Button(action: { isPasswordVisible.toggle() }) {
                            Image(systemName: isPasswordVisible ? "eye.slash.fill" : "eye.fill")
                                .foregroundColor(.gray)
                        }
                    }
                    .font(.subheadline)
                    .padding(10)
                    .background(Color(white: 0.14))
                    .cornerRadius(8)
                    .foregroundColor(.white)
                }

                // زر اختبار الاتصال
                Button(action: testConnection) {
                    HStack(spacing: 6) {
                        if isTestingLogin {
                            ProgressView().tint(.blue)
                            Text("جارِ اختبار الاتصال...")
                        } else {
                            Image(systemName: "bolt.fill")
                            Text("⚡ اختبار الاتصال بكلمة المرور الآن")
                        }
                    }
                    .font(.caption.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.blue.opacity(0.2))
                    .foregroundColor(.blue)
                    .cornerRadius(8)
                }
                .disabled(isTestingLogin || password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                // نتيجة فحص الاتصال
                if !testLoginMessage.isEmpty {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: (isLoginSuccess ?? false) ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundColor((isLoginSuccess ?? false) ? .green : .orange)
                        Text(testLoginMessage)
                            .font(.caption)
                            .foregroundColor((isLoginSuccess ?? false) ? .green : .orange)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(((isLoginSuccess ?? false) ? Color.green : Color.orange).opacity(0.12))
                    .cornerRadius(8)
                }
            }
        }
    }

    // MARK: - الخطوة 3: باقة الإنترنت وتاريخ التجديد
    private var stepThreeQuotaView: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("الخطوة 3: باقة الإنترنت وتاريخ التجديد")
                    .font(.headline.bold())
                    .foregroundColor(.white)
                Text("حدد حجم باقتك الشهرية ويوم التجديد ليقوم التطبيق بحساب المتبقي ومعدل الاستهلاك الآمن يومياً.")
                    .font(.caption)
                    .foregroundColor(.gray)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("حجم الباقة الإجمالي (جيجابايت):")
                    .font(.caption.bold())
                    .foregroundColor(.gray)

                // خيارات سريعة شائعة
                HStack(spacing: 8) {
                    ForEach(commonPlanSizes, id: \.self) { size in
                        Button(action: { totalPlanGB = size }) {
                            Text("\(size) GB")
                                .font(.caption2.bold())
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(totalPlanGB == size ? Color.blue : Color(white: 0.16))
                                .foregroundColor(.white)
                                .cornerRadius(6)
                        }
                    }
                }

                TextField("حجم مخصص بالـ GB", text: $totalPlanGB)
                    .keyboardType(.numberPad)
                    .font(.subheadline)
                    .padding(10)
                    .background(Color(white: 0.14))
                    .cornerRadius(8)
                    .foregroundColor(.white)

                Divider().background(Color(white: 0.2))

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("يوم التجديد الشهري:")
                            .font(.caption.bold())
                            .foregroundColor(.gray)
                        Spacer()
                        Text("يوم \(renewalDay) من كل شهر")
                            .font(.caption.bold())
                            .foregroundColor(.cyan)
                    }

                    Stepper(value: $renewalDay, in: 1...31) {
                        Text("اختر يوم التجديد (1 - 31)")
                            .font(.caption)
                            .foregroundColor(.white)
                    }
                    .padding(8)
                    .background(Color(white: 0.14))
                    .cornerRadius(8)
                }

                Divider().background(Color(white: 0.2))

                VStack(alignment: .leading, spacing: 4) {
                    Text("المستهلك حتى اللحظة (اختياري)").font(.caption2).foregroundColor(.gray)
                    TextField("0.0", text: $currentUsedGB)
                        .keyboardType(.decimalPad)
                        .font(.subheadline)
                        .padding(10)
                        .background(Color(white: 0.14))
                        .cornerRadius(8)
                        .foregroundColor(.white)
                    Text("إذا كنت في منتصف الشهر، أدخل ما استهلكته لتبدأ الباقة بحساب دقيق فوراً.")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
            }
        }
    }

    // MARK: - الخطوة 4: ملخص وتأكيد الإعداد
    private var stepFourSummaryView: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("الخطوة 4: جاهز للاستخدام! 🚀")
                    .font(.headline.bold())
                    .foregroundColor(.white)
                Text("راجع ملخص إعدادات الراوتر واضغط على زر البدء لتطبيقها مباشرة.")
                    .font(.caption)
                    .foregroundColor(.gray)
            }

            VStack(spacing: 10) {
                summaryRow(title: "اسم الراوتر", value: routerName, icon: "router.fill")
                summaryRow(title: "عنوان IP", value: routerIP, icon: "network")
                summaryRow(title: "طراز النظام", value: selectedFirmware.rawValue, icon: "cpu")
                summaryRow(title: "اسم المستخدم", value: username, icon: "person.fill")
                summaryRow(title: "حجم الباقة", value: "\(totalPlanGB) جيجابايت", icon: "chart.bar.fill")
                summaryRow(title: "يوم التجديد", value: "يوم \(renewalDay) من كل شهر", icon: "calendar")

                if let matched = detectionResult?.matchedPreset {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(.cyan)
                        Text("تم تفعيل قالب: \(matched.name)")
                            .font(.caption2.bold())
                            .foregroundColor(.cyan)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity)
                    .background(Color.cyan.opacity(0.12))
                    .cornerRadius(6)
                }
            }
            .padding(12)
            .background(Color(white: 0.12))
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(white: 0.2), lineWidth: 1))
        }
    }

    private func summaryRow(title: String, value: String, icon: String) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.blue)
                .frame(width: 20)
            Text(title)
                .font(.caption)
                .foregroundColor(.gray)
            Spacer()
            Text(value)
                .font(.caption.bold())
                .foregroundColor(.white)
        }
    }

    // MARK: - شريط أزرار التنقل بالأسفل
    private var bottomNavigationButtons: some View {
        HStack(spacing: 12) {
            if currentStep > 1 {
                Button(action: { currentStep -= 1 }) {
                    HStack {
                        Image(systemName: "chevron.right")
                        Text("السابق")
                    }
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(white: 0.18))
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
            }

            Button(action: handleNextStep) {
                HStack {
                    Text(currentStep == 4 ? "حفظ وبدء استخدام التطبيق 🚀" : "التالي")
                        .font(.subheadline.bold())
                    if currentStep < 4 {
                        Image(systemName: "chevron.left")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
        }
    }

    // MARK: - منطق التنقل والحفظ
    private func handleNextStep() {
        if currentStep < 4 {
            currentStep += 1
        } else {
            // حفظ الإعدادات في الراوتر النشط
            applyAndCompleteWizard()
        }
    }

    private func applyAndCompleteWizard() {
        var r = service.activeRouter
        r.name = routerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "راوتر المنزل" : routerName
        r.routerIP = routerIP.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "192.168.1.1" : routerIP
        r.username = username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "admin" : username
        r.password = password
        r.firmware = selectedFirmware

        if let plan = Double(totalPlanGB), plan > 0 {
            r.totalPlanGB = plan
        }
        r.renewalDay = renewalDay

        if let offset = Double(currentUsedGB.replacingOccurrences(of: ",", with: ".")), offset > 0 {
            r.manualOffsetGB = offset
        }

        // إذا كان هناك قالب مطابق، ننقل محددات No-Code الخاصة به
        if let preset = detectionResult?.matchedPreset {
            r.customUsageSelector = preset.customUsageSelector
            r.customUsageRegex = preset.customUsageRegex
            r.customUsageUnit = preset.customUsageUnit
            r.customDeviceTableSelector = preset.customDeviceTableSelector
            r.customRebootButtonSelector = preset.customRebootButtonSelector
            r.customUsernameSelector = preset.customUsernameSelector
            r.customPasswordSelector = preset.customPasswordSelector
            r.customLoginButtonSelector = preset.customLoginButtonSelector
        }

        service.activeRouter = r
        service.saveAllProfiles()
        UserDefaults.standard.set(true, forKey: "hasCompletedWizard")

        // بدء تحديث خلفي للبيانات
        Task {
            _ = await service.loginAndRefresh()
        }

        onFinish()
    }

    // MARK: - اختبار الاتصال في الخطوة 2
    private func testConnection() {
        Task {
            isTestingLogin = true
            testLoginMessage = "جارِ فحص الاتصال بـ \(routerIP)..."

            var testProfile = service.activeRouter
            testProfile.name = routerName
            testProfile.routerIP = routerIP.trimmingCharacters(in: .whitespacesAndNewlines)
            testProfile.username = username.trimmingCharacters(in: .whitespacesAndNewlines)
            testProfile.password = password
            testProfile.firmware = selectedFirmware

            let res = await service.testRouterConnection(profile: testProfile)
            isLoginSuccess = res.success
            testLoginMessage = res.message
            isTestingLogin = false
        }
    }

    // MARK: - الكشف التلقائي عن الراوتر
    private func runAutoDetection() {
        Task {
            isDetecting = true
            detectionStatus = "فحص عناوين الشبكة المحلية المعتادة..."

            let candidateIPs = ["192.168.1.1", "192.168.8.1", "192.168.0.1", "192.168.2.1"]
            var detected: DetectedRouterResult? = nil

            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 2.0
            config.timeoutIntervalForResource = 3.0
            let ephemeralSession = URLSession(configuration: config)

            for ip in candidateIPs {
                detectionStatus = "فحص الاتصال بالعنوان \(ip)..."

                // 1. فحص راوتر Huawei HiLink
                if let url = URL(string: "http://\(ip)/api/webserver/SesTokInfo") {
                    var req = URLRequest(url: url)
                    req.timeoutInterval = 1.8
                    if let (data, res) = try? await ephemeralSession.data(for: req),
                       let http = res as? HTTPURLResponse, (http.statusCode == 200 || http.statusCode == 403),
                       let str = String(data: data, encoding: .utf8), str.contains("response") || str.contains("SesInfo") {
                        let matched = RouterPresetsManager.builtinPresets.first { $0.id == "huawei_b311" }
                        detected = DetectedRouterResult(
                            ip: ip,
                            modelName: "راوتر Huawei 4G (B311 / HiLink)",
                            firmware: .huaweiB311,
                            matchedPreset: matched,
                            details: "تم التعرف على واجهة HiLink API الخاصة براوترات هواوي"
                        )
                        break
                    }
                }

                // 2. فحص راوتر D-Link DSL-224 (ME_1.10 Boa)
                if let url = URL(string: "http://\(ip)/login.cgi") {
                    var req = URLRequest(url: url)
                    req.timeoutInterval = 1.8
                    if let (data, res) = try? await ephemeralSession.data(for: req),
                       let http = res as? HTTPURLResponse, http.statusCode == 200,
                       let str = String(data: data, encoding: .utf8), str.contains("DSL-224") || str.contains("boa") || str.contains("login") {
                        let matched = RouterPresetsManager.builtinPresets.first { $0.id == "dlink_dsl224" }
                        detected = DetectedRouterResult(
                            ip: ip,
                            modelName: "راوتر D-Link DSL-224 (ME_1.10)",
                            firmware: .me110Boa,
                            matchedPreset: matched,
                            details: "تم التعرف على صفحة الدخول Boa لراوتر D-Link DSL-224"
                        )
                        break
                    }
                }

                // 3. فحص راوتر ZTE H168N / H188A
                if let url = URL(string: "http://\(ip)/boaform/admin/formLogin") {
                    var req = URLRequest(url: url)
                    req.timeoutInterval = 1.8
                    if let (_, res) = try? await ephemeralSession.data(for: req),
                       let http = res as? HTTPURLResponse, (200...404).contains(http.statusCode) {
                        let matched = RouterPresetsManager.builtinPresets.first { $0.id == "zte_h168n" }
                        detected = DetectedRouterResult(
                            ip: ip,
                            modelName: "راوتر ZTE ZXHN (H168N / H188A)",
                            firmware: .genericRealtek,
                            matchedPreset: matched,
                            details: "تم رصد معالج Realtek/ZTE ونموذج formLogin"
                        )
                        break
                    }
                }

                // 4. فحص الصفحة الرئيسية للراوتر للتعرف على الماركة
                if let url = URL(string: "http://\(ip)/") {
                    var req = URLRequest(url: url)
                    req.timeoutInterval = 1.8
                    if let (data, res) = try? await ephemeralSession.data(for: req),
                       let http = res as? HTTPURLResponse, (200...399).contains(http.statusCode),
                       let str = String(data: data, encoding: .utf8) {
                        let lower = str.lowercased()
                        if lower.contains("huawei") || lower.contains("hilink") {
                            let matched = RouterPresetsManager.builtinPresets.first { $0.id == "huawei_b311" }
                            detected = DetectedRouterResult(
                                ip: ip,
                                modelName: "راوتر Huawei 4G Flybox",
                                firmware: .huaweiB311,
                                matchedPreset: matched,
                                details: "تم رصد علامة تجارية هواوي في الصفحة الرئيسية"
                            )
                            break
                        } else if lower.contains("vodafone") || lower.contains("h300s") {
                            let matched = RouterPresetsManager.builtinPresets.first { $0.id == "vodafone_vdsl" }
                            detected = DetectedRouterResult(
                                ip: ip,
                                modelName: "راوتر فودافون VDSL (H300s)",
                                firmware: .genericRealtek,
                                matchedPreset: matched,
                                details: "تم رصد واجهة راوتر فودافون مصر"
                            )
                            break
                        } else if lower.contains("tp-link") || lower.contains("archer") || lower.contains("vr600") {
                            let matched = RouterPresetsManager.builtinPresets.first { $0.id == "tplink_vdsl" }
                            detected = DetectedRouterResult(
                                ip: ip,
                                modelName: "راوتر TP-Link Archer / VR600",
                                firmware: .genericRealtek,
                                matchedPreset: matched,
                                details: "تم رصد واجهة راوتر TP-Link"
                            )
                            break
                        } else if lower.contains("orange") || lower.contains("flybox") {
                            let matched = RouterPresetsManager.builtinPresets.first { $0.id == "orange_flybox" }
                            detected = DetectedRouterResult(
                                ip: ip,
                                modelName: "راوتر أورنج Flybox 4G",
                                firmware: .huaweiB311,
                                matchedPreset: matched,
                                details: "تم رصد واجهة أورنج Flybox"
                            )
                            break
                        } else {
                            detected = DetectedRouterResult(
                                ip: ip,
                                modelName: "راوتر منزلي (\(ip))",
                                firmware: .me110Boa,
                                matchedPreset: nil,
                                details: "تم الاستجابة بنجاح من العنوان \(ip)"
                            )
                            break
                        }
                    }
                }
            }

            isDetecting = false
            if let det = detected {
                detectionResult = det
                routerIP = det.ip
                routerName = det.modelName
                selectedFirmware = det.firmware
            } else {
                detectionStatus = "لم يتم الرد من العناوين الشائعة، يمكنك إدخال الـ IP يدويّاً"
            }
        }
    }
}
