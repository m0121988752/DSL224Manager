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

    // وضع اختيار العناصر المرئي بدون كود (No-Code Visual Element Picker)
    @State private var isPickerModeActive: Bool = false
    @State private var pickedElement: PickedElementInfo? = nil
    @State private var showAssignmentSheet: Bool = false

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

                        Button(action: { togglePickerMode() }) {
                            Image(systemName: isPickerModeActive ? "target" : "scope")
                                .font(.body.bold())
                                .foregroundColor(isPickerModeActive ? .green : .white)
                                .padding(4)
                                .background(isPickerModeActive ? Color.green.opacity(0.25) : Color.clear)
                                .clipShape(Circle())
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(white: 0.1))

                    // 2. شريط الأتمتة الذكية والأزرار السريعة
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            // زر وضع التقاط العناصر المرئي لأي راوتر بدون كود
                            Button(action: { togglePickerMode() }) {
                                HStack(spacing: 4) {
                                    Image(systemName: isPickerModeActive ? "target" : "scope")
                                    Text(isPickerModeActive ? "إلغاء الالتقاط" : "التقاط عنصر 🎯")
                                }
                                .font(.caption.bold())
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(isPickerModeActive ? Color.green : Color.green.opacity(0.3))
                                .foregroundColor(isPickerModeActive ? .black : .green)
                                .cornerRadius(6)
                            }

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

                    // إشعار وضع الالتقاط النشط
                    if isPickerModeActive {
                        HStack(spacing: 8) {
                            Image(systemName: "scope")
                                .foregroundColor(.black)
                                .font(.caption.bold())
                            Text("وضع التقاط العناصر مفعّل 🎯: انقر على أي رقم استهلاك، جدول أجهزة، أو زر في صفحة الراوتر لربطه فوراً بدون كود")
                                .font(.caption2.bold())
                                .foregroundColor(.black)
                            Spacer()
                            Button(action: { togglePickerMode() }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.black.opacity(0.8))
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(red: 0.0, green: 0.9, blue: 0.46))
                    }

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
                            isPickerActive: isPickerModeActive,
                            onNavigationChanged: { url, canBack, canFwd, title, loading in
                                self.addressText = url
                                self.canGoBack = canBack
                                self.canGoForward = canFwd
                                self.pageTitle = title
                                self.isLoadingPage = loading
                            },
                            onElementPicked: { info in
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                self.pickedElement = info
                                self.showAssignmentSheet = true
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
            .sheet(isPresented: $showAssignmentSheet) {
                if let info = pickedElement {
                    ElementAssignmentSheet(
                        info: info,
                        onAssign: { action in
                            handleElementAssignment(info: info, action: action)
                        }
                    )
                }
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

    // MARK: - إدارة وضع التقاط العناصر (Visual Element Picker Mode)
    private func togglePickerMode() {
        isPickerModeActive.toggle()
        if isPickerModeActive {
            lastActionToast = "تم تفعيل وضع الالتقاط 🎯: انقر على أي رقم أو جدول أو زر في صفحة الراوتر"
            webView.evaluateJavaScript(RouterWebUIView.startPickerJS, completionHandler: nil)
        } else {
            lastActionToast = "تم إيقاف وضع الالتقاط"
            webView.evaluateJavaScript(RouterWebUIView.stopPickerJS, completionHandler: nil)
        }
    }

    private func handleElementAssignment(info: PickedElementInfo, action: ElementAssignmentAction) {
        showAssignmentSheet = false
        var r = service.activeRouter

        switch action {
        case .usageCounter:
            r.customUsageSelector = info.selector
            let t = info.text.uppercased()
            if t.contains("GB") || t.contains("جيجا") {
                r.customUsageUnit = "GB"
            } else if t.contains("MB") || t.contains("ميجا") {
                r.customUsageUnit = "MB"
            } else if t.contains("KB") || t.contains("كيلو") {
                r.customUsageUnit = "KB"
            } else if t.contains("BYTE") || t.contains("بايت") {
                r.customUsageUnit = "Bytes"
            }
            service.updateRouter(r)
            service.saveAllProfiles()
            lastActionToast = "تم تعيين عداد استهلاك الباقة بنجاح: \(info.selector)"
            isPickerModeActive = false
            webView.evaluateJavaScript(RouterWebUIView.stopPickerJS, completionHandler: nil)

        case .devicesTable:
            r.customDeviceTableSelector = info.selector
            service.updateRouter(r)
            service.saveAllProfiles()
            lastActionToast = "تم تعيين جدول الأجهزة المتصلة بنجاح: \(info.selector)"
            isPickerModeActive = false
            webView.evaluateJavaScript(RouterWebUIView.stopPickerJS, completionHandler: nil)

        case .rebootButton:
            r.customRebootButtonSelector = info.selector
            service.updateRouter(r)
            service.saveAllProfiles()
            lastActionToast = "تم تعيين زر إعادة التشغيل بنجاح: \(info.selector)"
            isPickerModeActive = false
            webView.evaluateJavaScript(RouterWebUIView.stopPickerJS, completionHandler: nil)

        case .usernameInput:
            r.customUsernameSelector = info.selector
            service.updateRouter(r)
            service.saveAllProfiles()
            lastActionToast = "تم تعيين حقل اسم المستخدم بنجاح: \(info.selector)"
            isPickerModeActive = false
            webView.evaluateJavaScript(RouterWebUIView.stopPickerJS, completionHandler: nil)

        case .passwordInput:
            r.customPasswordSelector = info.selector
            service.updateRouter(r)
            service.saveAllProfiles()
            lastActionToast = "تم تعيين حقل كلمة المرور بنجاح: \(info.selector)"
            isPickerModeActive = false
            webView.evaluateJavaScript(RouterWebUIView.stopPickerJS, completionHandler: nil)

        case .loginButton:
            r.customLoginButtonSelector = info.selector
            service.updateRouter(r)
            service.saveAllProfiles()
            lastActionToast = "تم تعيين زر تسجيل الدخول بنجاح: \(info.selector)"
            isPickerModeActive = false
            webView.evaluateJavaScript(RouterWebUIView.stopPickerJS, completionHandler: nil)

        case .copySelector:
            UIPasteboard.general.string = info.selector
            lastActionToast = "تم نسخ محدد العنصر للحافظة: \(info.selector)"
        }
    }

    // سكريبت تفعيل وضع الاختيار البصري لجميع الراوترات
    static let startPickerJS = """
    (function() {
        if (window.__dslPickerActive) return;
        window.__dslPickerActive = true;

        var box = document.getElementById('__dsl_picker_box');
        if (!box) {
            box = document.createElement('div');
            box.id = '__dsl_picker_box';
            box.style.position = 'fixed';
            box.style.pointerEvents = 'none';
            box.style.zIndex = '2147483647';
            box.style.border = '2px dashed #00E676';
            box.style.backgroundColor = 'rgba(0, 230, 118, 0.22)';
            box.style.borderRadius = '5px';
            box.style.boxShadow = '0 0 14px rgba(0, 230, 118, 0.65)';
            box.style.transition = 'all 0.08s ease-out';
            box.style.display = 'none';

            var badge = document.createElement('div');
            badge.id = '__dsl_picker_badge';
            badge.style.position = 'absolute';
            badge.style.top = '-28px';
            badge.style.left = '0';
            badge.style.backgroundColor = '#00E676';
            badge.style.color = '#000000';
            badge.style.fontSize = '12px';
            badge.style.fontWeight = 'bold';
            badge.style.padding = '2px 8px';
            badge.style.borderRadius = '4px';
            badge.style.whiteSpace = 'nowrap';
            badge.style.fontFamily = 'monospace';
            badge.style.boxShadow = '0 2px 6px rgba(0,0,0,0.4)';
            box.appendChild(badge);

            document.documentElement.appendChild(box);
        }

        var hoveredEl = null;

        function getUniqueSelector(el) {
            if (!el || el === document.body || el === document.documentElement) return '';
            if (el.id && el.id.trim() !== '') {
                try {
                    var cleanId = CSS.escape ? CSS.escape(el.id) : el.id;
                    if (document.querySelectorAll('#' + cleanId).length === 1) {
                        return '#' + cleanId;
                    }
                } catch(e) {}
            }
            var name = el.getAttribute('name');
            if (name) {
                var sel = el.tagName.toLowerCase() + '[name="' + name + '"]';
                try {
                    if (document.querySelectorAll(sel).length === 1) return sel;
                } catch(e) {}
            }
            var path = [];
            var curr = el;
            while (curr && curr.nodeType === Node.ELEMENT_NODE && curr !== document.documentElement) {
                var tag = curr.tagName.toLowerCase();
                if (curr.id && curr.id.trim() !== '') {
                    try {
                        var cleanId = CSS.escape ? CSS.escape(curr.id) : curr.id;
                        if (document.querySelectorAll('#' + cleanId).length === 1) {
                            path.unshift('#' + cleanId);
                            break;
                        }
                    } catch(e) {}
                }
                var parent = curr.parentElement;
                if (parent) {
                    var siblings = Array.from(parent.children).filter(function(e) { return e.tagName.toLowerCase() === tag; });
                    if (siblings.length > 1) {
                        var index = siblings.indexOf(curr) + 1;
                        path.unshift(tag + ':nth-of-type(' + index + ')');
                    } else {
                        path.unshift(tag);
                    }
                } else {
                    path.unshift(tag);
                }
                curr = curr.parentElement;
                if (path.length >= 4) break;
            }
            return path.join(' > ');
        }

        function onPointerMove(e) {
            var x = e.clientX, y = e.clientY;
            var el = document.elementFromPoint(x, y);
            if (!el || el === box || box.contains(el)) return;
            hoveredEl = el;

            var rect = el.getBoundingClientRect();
            box.style.left = rect.left + 'px';
            box.style.top = rect.top + 'px';
            box.style.width = Math.max(rect.width, 14) + 'px';
            box.style.height = Math.max(rect.height, 14) + 'px';
            box.style.display = 'block';

            var badge = document.getElementById('__dsl_picker_badge');
            if (badge) {
                var tag = el.tagName.toLowerCase();
                var id = el.id ? '#' + el.id : '';
                var txt = (el.innerText || el.textContent || el.value || '').trim();
                if (txt.length > 18) txt = txt.substring(0, 18) + '...';
                badge.innerText = tag + id + (txt ? ' "' + txt + '"' : '');
                if (rect.top < 34) {
                    badge.style.top = (rect.height + 4) + 'px';
                } else {
                    badge.style.top = '-28px';
                }
            }
        }

        function onClick(e) {
            e.preventDefault();
            e.stopPropagation();
            e.stopImmediatePropagation();

            var el = hoveredEl || e.target;
            if (!el || el === box || box.contains(el)) return false;

            var selector = getUniqueSelector(el);
            var tag = el.tagName ? el.tagName.toLowerCase() : '';
            var text = (el.innerText || el.textContent || '').trim().replace(/\\s+/g, ' ');
            var value = el.value || '';

            var payload = {
                selector: selector,
                tag: tag,
                text: text.slice(0, 200),
                value: value.slice(0, 100),
                url: window.location.href
            };

            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.elementPicker) {
                window.webkit.messageHandlers.elementPicker.postMessage(payload);
            }
            return false;
        }

        window.__dslPickerMoveHandler = onPointerMove;
        window.__dslPickerClickHandler = onClick;

        document.addEventListener('pointermove', onPointerMove, true);
        document.addEventListener('touchmove', function(e) {
            if (e.touches && e.touches[0]) {
                onPointerMove({ clientX: e.touches[0].clientX, clientY: e.touches[0].clientY });
            }
        }, { capture: true, passive: true });

        document.addEventListener('click', onClick, true);
        document.addEventListener('touchend', function(e) {
            if (e.changedTouches && e.changedTouches[0]) {
                var t = e.changedTouches[0];
                var el = document.elementFromPoint(t.clientX, t.clientY);
                if (el) {
                    hoveredEl = el;
                    onClick(e);
                }
            }
        }, true);
    })();
    """

    // سكريبت إيقاف وضع الاختيار البصري
    static let stopPickerJS = """
    (function() {
        window.__dslPickerActive = false;
        var box = document.getElementById('__dsl_picker_box');
        if (box && box.parentElement) {
            box.parentElement.removeChild(box);
        }
        if (window.__dslPickerMoveHandler) {
            document.removeEventListener('pointermove', window.__dslPickerMoveHandler, true);
        }
        if (window.__dslPickerClickHandler) {
            document.removeEventListener('click', window.__dslPickerClickHandler, true);
        }
    })();
    """
}

// MARK: - UIViewRepresentable لعرض WKWebView وتحديث حالته
struct WebViewWrapper: UIViewRepresentable {
    let webView: WKWebView
    var isPickerActive: Bool
    var onNavigationChanged: (String, Bool, Bool, String, Bool) -> Void
    var onElementPicked: (PickedElementInfo) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        webView.navigationDelegate = context.coordinator
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "elementPicker")
        webView.configuration.userContentController.add(context.coordinator, name: "elementPicker")
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        if isPickerActive {
            uiView.evaluateJavaScript(RouterWebUIView.startPickerJS, completionHandler: nil)
        } else {
            uiView.evaluateJavaScript(RouterWebUIView.stopPickerJS, completionHandler: nil)
        }
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: WebViewWrapper

        init(_ parent: WebViewWrapper) {
            self.parent = parent
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "elementPicker",
                  let dict = message.body as? [String: Any] else { return }

            let selector = dict["selector"] as? String ?? ""
            let tag = dict["tag"] as? String ?? ""
            let text = dict["text"] as? String ?? ""
            let value = dict["value"] as? String ?? ""
            let url = dict["url"] as? String ?? ""

            let info = PickedElementInfo(
                selector: selector,
                tag: tag,
                text: text,
                value: value,
                url: url
            )

            DispatchQueue.main.async {
                self.parent.onElementPicked(info)
            }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            notify(webView, loading: true)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            notify(webView, loading: false)
            if parent.isPickerActive {
                webView.evaluateJavaScript(RouterWebUIView.startPickerJS, completionHandler: nil)
            }
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

// MARK: - أنواع التعيين المتاحة لعنصر الراوتر
enum ElementAssignmentAction {
    case usageCounter
    case devicesTable
    case rebootButton
    case usernameInput
    case passwordInput
    case loginButton
    case copySelector
}

// MARK: - معلومات العنصر الملتقط عبر المتصفح (No-Code Picked Element)
struct PickedElementInfo: Identifiable {
    let id = UUID()
    let selector: String
    let tag: String
    let text: String
    let value: String
    let url: String

    var suggestedType: SuggestedElementType {
        let lowText = text.lowercased()
        let lowVal = value.lowercased()
        let lowSel = selector.lowercased()
        let fullSearch = "\(lowText) \(lowVal) \(lowSel)"

        if fullSearch.contains("gb") || fullSearch.contains("mb") || fullSearch.contains("kb") ||
           fullSearch.contains("bytes") || fullSearch.contains("traffic") || fullSearch.contains("usage") ||
           fullSearch.contains("download") || fullSearch.contains("باقة") || fullSearch.contains("استهلاك") {
            return .usageCounter
        }
        if tag == "table" || tag == "tbody" || fullSearch.contains("device") || fullSearch.contains("host") ||
           fullSearch.contains("dhcp") || fullSearch.contains("mac") || fullSearch.contains("client") || fullSearch.contains("أجهزة") {
            return .devicesTable
        }
        if fullSearch.contains("reboot") || fullSearch.contains("restart") || fullSearch.contains("إعادة التشغيل") {
            return .rebootButton
        }
        if tag == "input" && (fullSearch.contains("user") || fullSearch.contains("login") || fullSearch.contains("اسم المستخدم")) {
            return .usernameInput
        }
        if tag == "input" && (fullSearch.contains("pass") || fullSearch.contains("pwd") || fullSearch.contains("كلمة المرور")) {
            return .passwordInput
        }
        if (tag == "button" || tag == "input" || tag == "a") && (fullSearch.contains("login") || fullSearch.contains("signin") || fullSearch.contains("دخول")) {
            return .loginButton
        }
        return .unknown
    }
}

enum SuggestedElementType {
    case usageCounter
    case devicesTable
    case rebootButton
    case usernameInput
    case passwordInput
    case loginButton
    case unknown

    var title: String {
        switch self {
        case .usageCounter: return "عداد استهلاك الباقة"
        case .devicesTable: return "جدول الأجهزة المتصلة"
        case .rebootButton: return "زر إعادة التشغيل"
        case .usernameInput: return "حقل اسم المستخدم"
        case .passwordInput: return "حقل كلمة المرور"
        case .loginButton: return "زر تسجيل الدخول"
        case .unknown: return "عنصر عام"
        }
    }

    var icon: String {
        switch self {
        case .usageCounter: return "chart.pie.fill"
        case .devicesTable: return "laptopcomputer.and.iphone"
        case .rebootButton: return "power"
        case .usernameInput: return "person.fill"
        case .passwordInput: return "lock.fill"
        case .loginButton: return "key.fill"
        case .unknown: return "target"
        }
    }
}

// MARK: - شاشة تعيين العنصر الملتقط بدون كود (Element Assignment Sheet)
struct ElementAssignmentSheet: View {
    let info: PickedElementInfo
    var onAssign: (ElementAssignmentAction) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // بطاقة معاينة العنصر الملتقط
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("<\(info.tag.uppercased())>")
                                    .font(.caption.bold())
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.blue.opacity(0.3))
                                    .foregroundColor(.blue)
                                    .cornerRadius(6)

                                Spacer()

                                if info.suggestedType != .unknown {
                                    HStack(spacing: 4) {
                                        Image(systemName: "sparkles")
                                            .foregroundColor(.yellow)
                                        Text("مقترح: \(info.suggestedType.title)")
                                            .font(.caption2.bold())
                                            .foregroundColor(.yellow)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.yellow.opacity(0.2))
                                    .cornerRadius(6)
                                }
                            }

                            if !info.text.isEmpty {
                                Text("المحتوى: \"\(info.text)\"")
                                    .font(.subheadline)
                                    .foregroundColor(.white)
                                    .lineLimit(3)
                            } else if !info.value.isEmpty {
                                Text("القيمة: \"\(info.value)\"")
                                    .font(.subheadline)
                                    .foregroundColor(.white)
                                    .lineLimit(2)
                            }

                            HStack {
                                Image(systemName: "number")
                                    .foregroundColor(.gray)
                                    .font(.caption2)
                                Text(info.selector)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.gray)
                                    .lineLimit(2)
                            }
                        }
                        .padding(14)
                        .background(Color(white: 0.12))
                        .cornerRadius(10)

                        Text("اختر كيف ترغب في تعيين هذا العنصر في راوترك:")
                            .font(.caption.bold())
                            .foregroundColor(.gray)

                        // خيارات التعيين
                        VStack(spacing: 10) {
                            AssignmentOptionRow(
                                title: "عداد استهلاك الباقة",
                                subtitle: "لقراءة الرصيد المستهلك ومزامنته مع التطبيق والودجت",
                                icon: "chart.pie.fill",
                                color: .blue,
                                isRecommended: info.suggestedType == .usageCounter
                            ) {
                                onAssign(.usageCounter)
                            }

                            AssignmentOptionRow(
                                title: "جدول الأجهزة المتصلة",
                                subtitle: "لاستخراج قائمة الهواتف والأجهزة المتصلة براوترك",
                                icon: "laptopcomputer.and.iphone",
                                color: .green,
                                isRecommended: info.suggestedType == .devicesTable
                            ) {
                                onAssign(.devicesTable)
                            }

                            AssignmentOptionRow(
                                title: "زر إعادة التشغيل (Reboot)",
                                subtitle: "للضغط عليه تلقائياً عند طلب إعادة تشغيل الراوتر",
                                icon: "power",
                                color: .red,
                                isRecommended: info.suggestedType == .rebootButton
                            ) {
                                onAssign(.rebootButton)
                            }

                            AssignmentOptionRow(
                                title: "حقل اسم المستخدم (Login User)",
                                subtitle: "لحقن اسم المستخدم تلقائياً عند تسجيل الدخول",
                                icon: "person.fill",
                                color: .orange,
                                isRecommended: info.suggestedType == .usernameInput
                            ) {
                                onAssign(.usernameInput)
                            }

                            AssignmentOptionRow(
                                title: "حقل كلمة المرور (Login Pass)",
                                subtitle: "لحقن كلمة المرور تلقائياً في صفحة دخول الراوتر",
                                icon: "lock.fill",
                                color: .purple,
                                isRecommended: info.suggestedType == .passwordInput
                            ) {
                                onAssign(.passwordInput)
                            }

                            AssignmentOptionRow(
                                title: "زر تسجيل الدخول (Login Submit)",
                                subtitle: "للنقر عليه تلقائياً بعد ملء بيانات الدخول",
                                icon: "key.fill",
                                color: .yellow,
                                isRecommended: info.suggestedType == .loginButton
                            ) {
                                onAssign(.loginButton)
                            }
                        }

                        // زر نسخ المحدد للحافظة
                        Button(action: { onAssign(.copySelector) }) {
                            HStack {
                                Image(systemName: "doc.on.doc")
                                Text("نسخ المحدد فقط للحافظة")
                            }
                            .font(.caption.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color(white: 0.15))
                            .foregroundColor(.white)
                            .cornerRadius(8)
                        }
                        .padding(.top, 4)
                    }
                    .padding(14)
                }
            }
            .navigationTitle("تعيين العنصر الملتقط")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("إلغاء") { dismiss() }
                }
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }
}

// MARK: - عنصر صف التعيين
struct AssignmentOptionRow: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    var isRecommended: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(color)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.subheadline.bold())
                            .foregroundColor(.white)

                        if isRecommended {
                            Text("مقترح")
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.yellow.opacity(0.3))
                                .foregroundColor(.yellow)
                                .cornerRadius(4)
                        }
                    }

                    Text(subtitle)
                        .font(.caption2)
                        .foregroundColor(.gray)
                }

                Spacer()

                Image(systemName: "chevron.left")
                    .font(.caption2.bold())
                    .foregroundColor(.gray)
            }
            .padding(12)
            .background(isRecommended ? color.opacity(0.12) : Color(white: 0.12))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isRecommended ? color.opacity(0.4) : Color.clear, lineWidth: 1)
            )
            .cornerRadius(10)
        }
    }
}
