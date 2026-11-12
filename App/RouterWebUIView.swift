import SwiftUI
import WebKit

// MARK: - عارض صفحة الويب المباشر للراوتر (Interactive Router WebUI View)
struct RouterWebUIView: View {
    @ObservedObject var service: RouterService
    @StateObject private var fallbackService = WebUIFallbackService.shared

    @Environment(\.dismiss) private var dismiss
    @State private var webView: WKWebView = {
        let config = WKWebViewConfiguration()
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs

        let script = WKUserScript(
            source: "window.confirm = function() { return true; }; window.alert = function() { return true; };",
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        config.userContentController.addUserScript(script)

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        return wv
    }()

    @State private var addressText: String = ""
    @State private var canGoBack: Bool = false
    @State private var canGoForward: Bool = false
    @State private var pageTitle: String = ""
    @State private var isLoadingPage: Bool = false

    // كشط وأزرار
    @State private var showButtonsSheet: Bool = false
    @State private var showCustomScriptSheet: Bool = false
    @State private var showScrapeSummarySheet: Bool = false
    @State private var customSelectorInput: String = ""
    @State private var customJSInput: String = ""
    @State private var lastActionToast: String? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    // 1. شريط العنوان والتحكم في المتصفح
                    HStack(spacing: 8) {
                        Button(action: { webView.goBack() }) {
                            Image(systemName: "chevron.right")
                                .font(.body.bold())
                                .foregroundColor(canGoBack ? .blue : .gray)
                        }
                        .disabled(!canGoBack)

                        Button(action: { webView.goForward() }) {
                            Image(systemName: "chevron.left")
                                .font(.body.bold())
                                .foregroundColor(canGoForward ? .blue : .gray)
                        }
                        .disabled(!canGoForward)

                        Button(action: { webView.reload() }) {
                            Image(systemName: "arrow.clockwise")
                                .font(.body)
                                .foregroundColor(.blue)
                        }

                        HStack(spacing: 4) {
                            Image(systemName: "lock.shield.fill")
                                .font(.caption2)
                                .foregroundColor(.orange)
                            TextField("عنوان صفحة الراوتر", text: $addressText)
                                .font(.caption)
                                .foregroundColor(.white)
                                .keyboardType(.URL)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .onSubmit {
                                    loadAddress(addressText)
                                }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Color(white: 0.15))
                        .cornerRadius(8)

                        Button(action: { loadInitialRouterURL() }) {
                            Image(systemName: "house.fill")
                                .font(.body)
                                .foregroundColor(.blue)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(white: 0.1))

                    // 2. شريط الأتمتة الذكية والأزرار السريعة
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            // زر تسجيل الدخول التلقائي
                            Button(action: { performAutoLogin() }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "key.fill")
                                    Text("دخول تلقائي")
                                }
                                .font(.caption.bold())
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.blue.opacity(0.3))
                                .foregroundColor(.blue)
                                .cornerRadius(6)
                            }

                            // زر كشط ومزامنة
                            Button(action: { performScrapeCurrentPage() }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.triangle.2.circlepath.doc.on.clipboard")
                                    Text("كشط ومزامنة")
                                }
                                .font(.caption.bold())
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.green.opacity(0.3))
                                .foregroundColor(.green)
                                .cornerRadius(6)
                            }

                            // زر الضغط على إعادة التشغيل
                            Button(action: { performRebootButtonPress() }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "power")
                                    Text("ضغط Reboot")
                                }
                                .font(.caption.bold())
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.red.opacity(0.3))
                                .foregroundColor(.red)
                                .cornerRadius(6)
                            }

                            // زر فحص وكشف كل أزرار الصفحة
                            Button(action: { inspectPageButtons() }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "hand.tap.fill")
                                    Text("كشف الأزرار (\(fallbackService.discoveredButtons.count))")
                                }
                                .font(.caption.bold())
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.purple.opacity(0.3))
                                .foregroundColor(.purple)
                                .cornerRadius(6)
                            }

                            // زر مخصص / JS
                            Button(action: { showCustomScriptSheet = true }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "terminal.fill")
                                    Text("أمر مخصص")
                                }
                                .font(.caption.bold())
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.gray.opacity(0.3))
                                .foregroundColor(.white)
                                .cornerRadius(6)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                    }
                    .background(Color(white: 0.08))

                    // تنبيه حالة الأتمتة
                    if let toast = lastActionToast {
                        HStack {
                            Image(systemName: "info.circle.fill")
                                .foregroundColor(.yellow)
                            Text(toast)
                                .font(.caption2)
                                .foregroundColor(.white)
                            Spacer()
                            Button(action: { lastActionToast = nil }) {
                                Image(systemName: "xmark")
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Color.yellow.opacity(0.2))
                    }

                    // 3. عارض الويب المباشر
                    ZStack {
                        WebViewWrapper(
                            webView: webView,
                            onNavigationChanged: { url, canBack, canFwd, title, loading in
                                self.addressText = url
                                self.canGoBack = canBack
                                self.canGoForward = canFwd
                                self.pageTitle = title
                                self.isLoadingPage = loading
                            }
                        )

                        if isLoadingPage {
                            VStack {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                                    .scaleEffect(1.2)
                                    .padding()
                                    .background(Color.black.opacity(0.7))
                                    .cornerRadius(10)
                            }
                        }
                    }
                }
            }
            .navigationTitle(pageTitle.isEmpty ? service.activeRouter.name : pageTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("إغلاق") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                loadInitialRouterURL()
            }
            .sheet(isPresented: $showButtonsSheet) {
                DiscoveredButtonsSheet(
                    buttons: fallbackService.discoveredButtons,
                    onPressButton: { btn in
                        showButtonsSheet = false
                        pressDiscoveredButton(btn)
                    }
                )
            }
            .sheet(isPresented: $showScrapeSummarySheet) {
                ScrapeSummarySheet(
                    result: fallbackService.lastResult ?? .empty,
                    onApply: { res in
                        service.applyWebUIScrapeResult(res)
                        showScrapeSummarySheet = false
                        lastActionToast = "تمت مزامنة بيانات الكشط مع التطبيق بنجاح"
                    }
                )
            }
            .sheet(isPresented: $showCustomScriptSheet) {
                CustomActionSheet(
                    onPressSelector: { sel in
                        showCustomScriptSheet = false
                        pressCustomSelector(sel)
                    },
                    onRunJS: { script in
                        showCustomScriptSheet = false
                        runCustomJavaScript(script)
                    }
                )
            }
        }
    }

    private func loadInitialRouterURL() {
        let r = service.activeRouter
        var path = r.webUIPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if path.hasPrefix("/") { path.removeFirst() }
        let full = path.isEmpty ? "http://\(r.routerIP)" : "http://\(r.routerIP)/\(path)"
        loadAddress(full)
    }

    private func loadAddress(_ str: String) {
        var clean = str.trimmingCharacters(in: .whitespacesAndNewlines)
        if !clean.lowercased().hasPrefix("http://") && !clean.lowercased().hasPrefix("https://") {
            clean = "http://\(clean)"
        }
        if let url = URL(string: clean) {
            addressText = clean
            webView.load(URLRequest(url: url))
        }
    }

    private func performAutoLogin() {
        let r = service.activeRouter
        Task {
            lastActionToast = "جارِ تعبئة بيانات الدخول والضغط على زر الدخول..."
            let done = await fallbackService.attemptAutoLogin(username: r.username, password: r.password, on: webView)
            if done {
                lastActionToast = "تم إرسال بيانات الدخول بنجاح"
            } else {
                lastActionToast = "لم يتم العثور على حقول تسجيل دخول في الصفحة الحالية"
            }
        }
    }

    private func performScrapeCurrentPage() {
        Task {
            lastActionToast = "جارِ كشط محتويات الصفحة الحالية..."
            let res = await fallbackService.scrapeCurrentPage(on: webView)
            fallbackService.lastResult = res
            fallbackService.discoveredButtons = res.buttons
            if (res.wanBytes ?? 0) > 0 || !res.devices.isEmpty {
                showScrapeSummarySheet = true
            } else {
                lastActionToast = "اكتمل الكشط: لم يُعثر على عداد بايتات صريح في الصفحة الحالية"
            }
        }
    }

    private func performRebootButtonPress() {
        Task {
            lastActionToast = "جارِ البحث عن زر إعادة التشغيل والضغط عليه..."
            let res = await fallbackService.pressButton(selector: nil, text: nil, semanticAction: .reboot, on: webView)
            lastActionToast = res.message
        }
    }

    private func inspectPageButtons() {
        Task {
            let res = await fallbackService.scrapeCurrentPage(on: webView)
            fallbackService.discoveredButtons = res.buttons
            showButtonsSheet = true
        }
    }

    private func pressDiscoveredButton(_ btn: WebUIButtonInfo) {
        Task {
            lastActionToast = "جارِ الضغط على [\(btn.displayLabel)]..."
            let res = await fallbackService.pressButton(selector: btn.selector, text: btn.text, semanticAction: nil, on: webView)
            lastActionToast = res.message
        }
    }

    private func pressCustomSelector(_ selector: String) {
        Task {
            lastActionToast = "جارِ الضغط على المحدد: \(selector)..."
            let res = await fallbackService.pressButton(selector: selector, text: nil, semanticAction: nil, on: webView)
            lastActionToast = res.message
        }
    }

    private func runCustomJavaScript(_ script: String) {
        Task {
            lastActionToast = "جارِ تنفيذ السكربت..."
            let res = await fallbackService.executeCustomScript(script, on: webView)
            lastActionToast = res.success ? "نتيجة السكربت: \(res.output)" : "خطأ: \(res.output)"
        }
    }
}

// MARK: - UIViewRepresentable لعرض WKWebView وتحديث حالته
struct WebViewWrapper: UIViewRepresentable {
    let webView: WKWebView
    var onNavigationChanged: (String, Bool, Bool, String, Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: WebViewWrapper

        init(_ parent: WebViewWrapper) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            notify(webView, loading: true)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            notify(webView, loading: false)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            notify(webView, loading: false)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            notify(webView, loading: false)
        }

        private func notify(_ wv: WKWebView, loading: Bool) {
            let url = wv.url?.absoluteString ?? ""
            let back = wv.canGoBack
            let fwd = wv.canGoForward
            let title = wv.title ?? ""
            parent.onNavigationChanged(url, back, fwd, title, loading)
        }
    }
}

// MARK: - نافذة الأزرار المكتشفة في الصفحة (Discovered Buttons Sheet)
struct DiscoveredButtonsSheet: View {
    let buttons: [WebUIButtonInfo]
    var onPressButton: (WebUIButtonInfo) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if buttons.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "hand.tap")
                            .font(.system(size: 40))
                            .foregroundColor(.gray)
                        Text("لم يتم العثور على أزرار واضحة في الصفحة الحالية")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    .padding()
                } else {
                    List {
                        ForEach(buttons) { btn in
                            Button(action: { onPressButton(btn) }) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack(spacing: 6) {
                                            if btn.isReboot {
                                                Image(systemName: "power")
                                                    .foregroundColor(.red)
                                            } else if btn.isLogin {
                                                Image(systemName: "key.fill")
                                                    .foregroundColor(.blue)
                                            } else if btn.isApply {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundColor(.green)
                                            } else {
                                                Image(systemName: "button.programmable")
                                                    .foregroundColor(.gray)
                                            }

                                            Text(btn.displayLabel)
                                                .font(.subheadline.bold())
                                                .foregroundColor(.white)
                                        }

                                        Text(btn.selector)
                                            .font(.caption2)
                                            .foregroundColor(.gray)
                                    }

                                    Spacer()

                                    Text("اضغط")
                                        .font(.caption.bold())
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(Color.blue.opacity(0.2))
                                        .foregroundColor(.blue)
                                        .cornerRadius(6)
                                }
                                .padding(.vertical, 4)
                            }
                            .listRowBackground(Color(white: 0.12))
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("الأزرار المكتشفة (\(buttons.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("تم") { dismiss() }
                }
            }
        }
    }
}

// MARK: - ملخص نتائج الكشط والمزامنة (Scrape Summary Sheet)
struct ScrapeSummarySheet: View {
    let result: WebUIScrapeResult
    var onApply: (WebUIScrapeResult) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("تم استخراج البيانات التالية من كود الصفحة:")
                            .font(.caption)
                            .foregroundColor(.gray)

                        // 1. عداد البايتات
                        VStack(alignment: .leading, spacing: 6) {
                            Text("عداد استهلاك الباقة (WAN Bytes)")
                                .font(.caption.bold())
                                .foregroundColor(.gray)

                            if let bytes = result.wanBytes, bytes > 0 {
                                let gb = Double(bytes) / (1024.0 * 1024.0 * 1024.0)
                                HStack {
                                    Image(systemName: "chart.pie.fill")
                                        .foregroundColor(.blue)
                                    Text("\(String(format: "%.2f", gb)) جيجابايت")
                                        .font(.title3.bold())
                                        .foregroundColor(.white)
                                    Spacer()
                                    Text("\(bytes) بايت")
                                        .font(.caption2)
                                        .foregroundColor(.gray)
                                }
                                .padding(10)
                                .background(Color(white: 0.12))
                                .cornerRadius(8)
                            } else {
                                Text("لم يتم العثور على عداد استهلاك واضح")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }

                        // 2. السرعة والمشغل
                        if let carrier = result.carrierName {
                            HStack {
                                Text("المشغل (Carrier):")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                Text(carrier)
                                    .font(.caption.bold())
                                    .foregroundColor(.orange)
                            }
                        }

                        // 3. الأجهزة المتصلة
                        VStack(alignment: .leading, spacing: 6) {
                            Text("الأجهزة المكتشفة في جداول الصفحة (\(result.devices.count))")
                                .font(.caption.bold())
                                .foregroundColor(.gray)

                            if result.devices.isEmpty {
                                Text("لم يتم العثور على جداول MAC/IP في الصفحة الحالية")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            } else {
                                ForEach(result.devices) { dev in
                                    HStack {
                                        Image(systemName: "laptopcomputer.and.iphone")
                                            .foregroundColor(.green)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(dev.hostName.isEmpty ? "جهاز متصل" : dev.hostName)
                                                .font(.caption.bold())
                                                .foregroundColor(.white)
                                            Text("\(dev.ipAddress) • \(dev.macAddress)")
                                                .font(.caption2)
                                                .foregroundColor(.gray)
                                        }
                                        Spacer()
                                    }
                                    .padding(8)
                                    .background(Color(white: 0.12))
                                    .cornerRadius(6)
                                }
                            }
                        }

                        // زر المزامنة
                        Button(action: { onApply(result) }) {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                Text("مزامنة هذه البيانات مع التطبيق والودجت")
                                    .fontWeight(.bold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                        .padding(.top, 10)
                    }
                    .padding(14)
                }
            }
            .navigationTitle("نتائج الكشط")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("إغلاق") { dismiss() }
                }
            }
        }
    }
}

// MARK: - نافذة تنفيذ أمر أو سكربت مخصص (Custom Action Sheet)
struct CustomActionSheet: View {
    var onPressSelector: (String) -> Void
    var onRunJS: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var selectorInput: String = ""
    @State private var jsInput: String = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                Form {
                    Section(header: Text("الضغط عبر CSS Selector").foregroundColor(.gray)) {
                        TextField("مثال: #submit_button أو input[name='save']", text: $selectorInput)
                            .font(.caption)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        Button("الضغط على هذا العنصر") {
                            if !selectorInput.isEmpty {
                                onPressSelector(selectorInput)
                            }
                        }
                        .disabled(selectorInput.isEmpty)
                    }
                    .listRowBackground(Color(white: 0.12))

                    Section(header: Text("تنفيذ كود JavaScript مخصص").foregroundColor(.gray)) {
                        TextEditor(text: $jsInput)
                            .font(.system(.caption, design: .monospaced))
                            .frame(height: 100)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        Button("تنفيذ السكربت في الصفحة") {
                            if !jsInput.isEmpty {
                                onRunJS(jsInput)
                            }
                        }
                        .disabled(jsInput.isEmpty)
                    }
                    .listRowBackground(Color(white: 0.12))
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("أمر أو سكريبت مخصص")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("إغلاق") { dismiss() }
                }
            }
        }
    }
}
