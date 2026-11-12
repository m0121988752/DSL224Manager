import Foundation
import WebKit
import Combine

/// خدمة كشط واجهات الويب للراوترات والضغط على الأزرار عبر محرك WebKit
@MainActor
class WebUIFallbackService: NSObject, ObservableObject, WKNavigationDelegate {
    static let shared = WebUIFallbackService()

    @Published var isRunning: Bool = false
    @Published var progressMessage: String = ""
    @Published var lastResult: WebUIScrapeResult? = nil
    @Published var discoveredButtons: [WebUIButtonInfo] = []
    @Published var currentURLString: String = ""
    @Published var pageTitle: String = ""

    private var headlessWebView: WKWebView?
    private var navigationContinuation: CheckedContinuation<Bool, Never>?
    private var navigationTimeoutTask: Task<Void, Never>?

    override init() {
        super.init()
        setupHeadlessWebView()
    }

    private func setupHeadlessWebView() {
        let config = WKWebViewConfiguration()
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs

        // حظر النوافذ المنبثقة التنبيهية التي توقف الأتمتة واستبدالها بالموافقة التلقائية
        let suppressDialogsScript = WKUserScript(
            source: """
            window.alert = function() { return true; };
            window.confirm = function() { return true; };
            window.prompt = function() { return null; };
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        config.userContentController.addUserScript(suppressDialogsScript)

        let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 1024, height: 768), configuration: config)
        wv.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        wv.navigationDelegate = self
        self.headlessWebView = wv
    }

    // MARK: - كشط واجهة الراوتر مع تسجيل الدخول التلقائي عند الحاجة
    func autoLoginAndScrape(router: RouterProfile, timeoutSeconds: Double = 12.0) async -> WebUIScrapeResult {
        isRunning = true
        progressMessage = "جارِ فتح واجهة ويب الراوتر (\(router.routerIP))..."
        defer {
            isRunning = false
            progressMessage = ""
        }

        let baseURL = "http://\(router.routerIP)"
        let targetPath = !router.webUIPath.isEmpty ? router.webUIPath : ""
        let fullURLStr = targetPath.isEmpty ? baseURL : "\(baseURL)/\(targetPath)"

        guard let targetURL = URL(string: fullURLStr) else {
            return WebUIScrapeResult(
                success: false,
                wanBytes: nil,
                liveDownloadKbps: nil,
                liveUploadKbps: nil,
                carrierName: nil,
                devices: [],
                buttons: [],
                pageTitle: "",
                currentURL: fullURLStr,
                rawTextSnippet: "",
                message: "رابط الراوتر غير صالح: \(fullURLStr)"
            )
        }

        // 1. الانتقال للصفحة الأولى
        let loaded = await loadURL(targetURL, timeout: timeoutSeconds)
        guard loaded else {
            return WebUIScrapeResult(
                success: false,
                wanBytes: nil,
                liveDownloadKbps: nil,
                liveUploadKbps: nil,
                carrierName: nil,
                devices: [],
                buttons: [],
                pageTitle: "",
                currentURL: fullURLStr,
                rawTextSnippet: "",
                message: "تعذر تحميل صفحة الراوتر (انتهت المهلة أو الجهاز غير متاح)"
            )
        }

        // 2. فحص وجود نموذج تسجيل دخول وتعبئته إذا وجد
        progressMessage = "فحص نموذج تسجيل الدخول..."
        let loginAttempted = await attemptAutoLogin(username: router.username, password: router.password)
        if loginAttempted {
            progressMessage = "تم إرسال بيانات الدخول، انتظار تحديث الصفحة..."
            // انتظار ثوانٍ قليلة لتحديث الصفحة بعد الإرسال
            try? await Task.sleep(nanoseconds: 2_500_000_000)
        }

        // 3. في حال كان الراوتر D-Link ولم نصل لصفحة المرور، نجرب الانتقال المباشر لصفحات الإحصائيات
        if router.firmware != .huaweiB311 && targetPath.isEmpty {
            let statsPages = ["status_traffic.html", "tc.html", "status.html"]
            for page in statsPages {
                if let statsURL = URL(string: "\(baseURL)/\(page)") {
                    progressMessage = "تجربة صفحة الإحصائيات: \(page)..."
                    _ = await loadURL(statsURL, timeout: 4.0)
                    let check = await scrapeCurrentPage()
                    if (check.wanBytes ?? 0) > 0 || !check.devices.isEmpty {
                        self.lastResult = check
                        self.discoveredButtons = check.buttons
                        return check
                    }
                }
            }
        }

        // 4. كشط محتويات الصفحة الحالية
        progressMessage = "كشط البيانات والأجهزة والأزرار..."
        let result = await scrapeCurrentPage()
        self.lastResult = result
        self.discoveredButtons = result.buttons
        return result
    }

    // MARK: - تحميل رابط مع مهلة زمنية
    private func loadURL(_ url: URL, timeout: Double) async -> Bool {
        guard let wv = headlessWebView else { return false }
        currentURLString = url.absoluteString

        return await withCheckedContinuation { continuation in
            self.navigationContinuation = continuation

            navigationTimeoutTask?.cancel()
            navigationTimeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                if let self = self, self.navigationContinuation != nil {
                    self.navigationContinuation?.resume(returning: false)
                    self.navigationContinuation = nil
                }
            }

            let req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: timeout)
            wv.load(req)
        }
    }

    // MARK: - WKNavigationDelegate
    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            self.navigationTimeoutTask?.cancel()
            self.currentURLString = webView.url?.absoluteString ?? ""
            self.pageTitle = webView.title ?? ""
            if let cont = self.navigationContinuation {
                self.navigationContinuation = nil
                cont.resume(returning: true)
            }
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            self.navigationTimeoutTask?.cancel()
            if let cont = self.navigationContinuation {
                self.navigationContinuation = nil
                cont.resume(returning: false)
            }
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            self.navigationTimeoutTask?.cancel()
            if let cont = self.navigationContinuation {
                self.navigationContinuation = nil
                cont.resume(returning: false)
            }
        }
    }

    // MARK: - تسجيل الدخول التلقائي عبر حقن JavaScript
    func attemptAutoLogin(username: String, password: String, on targetWebView: WKWebView? = nil) async -> Bool {
        let wv = targetWebView ?? headlessWebView
        guard let wv = wv else { return false }

        let escapedUser = username.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let escapedPass = password.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")

        let js = """
        (function() {
            var userSelectors = [
                'input[name*="user" i]',
                'input[name*="login" i]',
                'input[id*="user" i]',
                'input[id*="login" i]',
                '#username',
                '#txtUser',
                '#login_username',
                'input[type="text"]'
            ];
            var passSelectors = [
                'input[type="password"]',
                'input[name*="pass" i]',
                'input[name*="pwd" i]',
                'input[id*="pass" i]',
                'input[id*="pwd" i]',
                '#password',
                '#txtPwd'
            ];

            var userEl = null;
            for (var i = 0; i < userSelectors.length; i++) {
                var el = document.querySelector(userSelectors[i]);
                if (el) { userEl = el; break; }
            }

            var passEl = null;
            for (var j = 0; j < passSelectors.length; j++) {
                var p = document.querySelector(passSelectors[j]);
                if (p) { passEl = p; break; }
            }

            if (!userEl && !passEl) {
                return JSON.stringify({ attempted: false, reason: 'No login fields found' });
            }

            if (userEl && "\(escapedUser)".length > 0) {
                userEl.value = "\(escapedUser)";
                userEl.dispatchEvent(new Event('input', { bubbles: true }));
                userEl.dispatchEvent(new Event('change', { bubbles: true }));
            }

            if (passEl && "\(escapedPass)".length > 0) {
                passEl.value = "\(escapedPass)";
                passEl.dispatchEvent(new Event('input', { bubbles: true }));
                passEl.dispatchEvent(new Event('change', { bubbles: true }));
            }

            // البحث عن زر الإرسال أو الدخول
            var submitSelectors = [
                'input[type="submit"]',
                'button[type="submit"]',
                '#login_btn',
                '#loginBtn',
                '#btnLogin',
                '.login-btn',
                '.btn-login',
                'input[value*="login" i]',
                'input[value*="دخول" i]',
                'input[value*="تسجيل" i]',
                'button.login',
                'a.login-btn'
            ];

            var submitEl = null;
            for (var k = 0; k < submitSelectors.length; k++) {
                var b = document.querySelector(submitSelectors[k]);
                if (b) { submitEl = b; break; }
            }

            if (submitEl) {
                submitEl.click();
                return JSON.stringify({ attempted: true, action: 'clicked_submit' });
            }

            // محاولة إرسال النموذج مباشرة
            var form = (passEl ? passEl.closest('form') : null) || document.querySelector('form');
            if (form) {
                form.submit();
                return JSON.stringify({ attempted: true, action: 'form_submitted' });
            }

            return JSON.stringify({ attempted: true, action: 'fields_populated' });
        })();
        """

        do {
            let res = try await wv.evaluateJavaScript(js)
            if let jsonStr = res as? String,
               let data = jsonStr.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let attempted = dict["attempted"] as? Bool {
                return attempted
            }
            return false
        } catch {
            return false
        }
    }

    // MARK: - كشط محتويات DOM (الإحصائيات، البايتات، الأجهزة، والأزرار)
    func scrapeCurrentPage(on targetWebView: WKWebView? = nil) async -> WebUIScrapeResult {
        let wv = targetWebView ?? headlessWebView
        guard let wv = wv else {
            return .empty
        }

        let js = """
        (function() {
            var bodyText = document.body ? document.body.innerText : '';
            var title = document.title || '';
            var currentUrl = window.location.href;

            // 1. استخراج العداد التراكمي (أرقام كبيرة 7 إلى 16 خانة)
            var foundBytes = null;
            var digitMatches = bodyText.match(/\\b(\\d{7,16})\\b/g);
            if (digitMatches && digitMatches.length > 0) {
                var maxVal = 0;
                for (var i = 0; i < digitMatches.length; i++) {
                    var val = parseInt(digitMatches[i], 10);
                    // نتجاهل التواريخ والأرقام الشاذة
                    if (val > 1000000 && val > maxVal && val < 9000000000000000) {
                        maxVal = val;
                    }
                }
                if (maxVal > 0) { foundBytes = maxVal; }
            }

            // في حال لم نجد أرقام بايتات خام، نفحص النصوص ذات الوحدات مثل "14.5 GB" أو "250 MB"
            if (!foundBytes) {
                var sizeMatches = bodyText.match(/([0-9]+(?:\\.[0-9]+)?)\\s*(GB|MB|KB|Bytes|جيجابايت|ميجابايت|بايت)/i);
                if (sizeMatches) {
                    var num = parseFloat(sizeMatches[1]);
                    var unit = sizeMatches[2].toUpperCase();
                    if (unit.indexOf('GB') !== -1 || unit.indexOf('جيجا') !== -1) {
                        foundBytes = Math.round(num * 1024 * 1024 * 1024);
                    } else if (unit.indexOf('MB') !== -1 || unit.indexOf('ميجا') !== -1) {
                        foundBytes = Math.round(num * 1024 * 1024);
                    } else if (unit.indexOf('KB') !== -1 || unit.indexOf('كيلو') !== -1) {
                        foundBytes = Math.round(num * 1024);
                    }
                }
            }

            // 2. استخراج السرعة اللحظية إن وجدت
            var downRate = null;
            var upRate = null;
            var speedMatch = bodyText.match(/([0-9]+(?:\\.[0-9]+)?)\\s*(KB\\/s|Kbps|MB\\/s|Mbps)/ig);
            if (speedMatch && speedMatch.length > 0) {
                var firstVal = parseFloat(speedMatch[0]);
                if (speedMatch[0].toLowerCase().indexOf('mb') !== -1) {
                    downRate = firstVal * 1024;
                } else {
                    downRate = firstVal;
                }
            }

            // 3. استخراج اسم المشغل (Carrier)
            var carrier = null;
            var carriers = ['Orange', 'Vodafone', 'Etisalat', 'WE', 'Telecom Egypt', 'Zain', 'STC', 'Mobily', 'Ooredoo'];
            for (var c = 0; c < carriers.length; c++) {
                if (bodyText.indexOf(carriers[c]) !== -1) {
                    carrier = carriers[c];
                    break;
                }
            }

            // 4. استخراج الأجهزة المتصلة من جداول الصفحة
            var devices = [];
            var seenMacs = {};
            var macRegex = /([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})/;
            var ipRegex = /\\b(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\b/;

            var rows = document.querySelectorAll('tr, .device-item, .host-item, li');
            rows.forEach(function(row) {
                var rowText = row.innerText || '';
                var macMatch = rowText.match(macRegex);
                if (macMatch) {
                    var mac = macMatch[0].toUpperCase().replace(/-/g, ':');
                    if (!seenMacs[mac]) {
                        seenMacs[mac] = true;
                        var ipMatch = rowText.match(ipRegex);
                        var ip = ipMatch ? ipMatch[0] : '192.168.1.100';

                        // استخراج اسم الجهاز إن أمكن من الخلايا المجاورة
                        var hostname = '';
                        var cells = row.querySelectorAll('td, span, div');
                        for (var ci = 0; ci < cells.length; ci++) {
                            var cellTxt = (cells[ci].innerText || '').trim();
                            if (cellTxt && !cellTxt.match(macRegex) && !cellTxt.match(ipRegex) && cellTxt.length < 30 && cellTxt.length > 1) {
                                hostname = cellTxt;
                                break;
                            }
                        }

                        devices.push({
                            macAddress: mac,
                            ipAddress: ip,
                            hostName: hostname
                        });
                    }
                }
            });

            // 5. اكتشاف جميع الأزرار وعناصر التحكم في الصفحة
            var buttons = [];
            var btnElements = document.querySelectorAll('button, input[type="button"], input[type="submit"], [role="button"], a.btn, input[type="reset"]');
            btnElements.forEach(function(el, index) {
                var txt = (el.innerText || el.textContent || el.value || '').trim();
                var id = el.id || ('btn_' + index);
                var name = el.getAttribute('name') || '';
                var val = (el.value || '').trim();

                var selector = '';
                if (el.id) {
                    selector = '#' + CSS.escape(el.id);
                } else if (name) {
                    selector = el.tagName.toLowerCase() + '[name="' + CSS.escape(name) + '"]';
                } else if (val) {
                    selector = el.tagName.toLowerCase() + '[value="' + CSS.escape(val) + '"]';
                } else {
                    selector = el.tagName.toLowerCase() + ':nth-of-type(' + (index + 1) + ')';
                }

                var fullSearch = (txt + ' ' + id + ' ' + name + ' ' + val).toLowerCase();
                var isReboot = fullSearch.indexOf('reboot') !== -1 || fullSearch.indexOf('restart') !== -1 || fullSearch.indexOf('إعادة') !== -1;
                var isLogin = fullSearch.indexOf('login') !== -1 || fullSearch.indexOf('signin') !== -1 || fullSearch.indexOf('دخول') !== -1 || fullSearch.indexOf('تسجيل') !== -1;
                var isApply = fullSearch.indexOf('apply') !== -1 || fullSearch.indexOf('save') !== -1 || fullSearch.indexOf('submit') !== -1 || fullSearch.indexOf('تطبيق') !== -1 || fullSearch.indexOf('حفظ') !== -1;

                if (txt || id || name || val) {
                    buttons.push({
                        id: id,
                        selector: selector,
                        tag: el.tagName.toLowerCase(),
                        text: txt.substring(0, 50),
                        value: val.substring(0, 50),
                        isReboot: isReboot,
                        isLogin: isLogin,
                        isApply: isApply
                    });
                }
            });

            return JSON.stringify({
                success: true,
                wanBytes: foundBytes,
                liveDownloadKbps: downRate,
                liveUploadKbps: upRate,
                carrierName: carrier,
                devices: devices,
                buttons: buttons,
                pageTitle: title,
                currentURL: currentUrl,
                rawTextSnippet: bodyText.substring(0, 300),
                message: 'تم الكشط بنجاح'
            });
        })();
        """

        do {
            let res = try await wv.evaluateJavaScript(js)
            if let jsonStr = res as? String,
               let data = jsonStr.data(using: .utf8),
               let decoded = try? JSONDecoder().decode(WebUIScrapeResult.self, from: data) {
                return decoded
            }
        } catch {
            return WebUIScrapeResult(
                success: false,
                wanBytes: nil,
                liveDownloadKbps: nil,
                liveUploadKbps: nil,
                carrierName: nil,
                devices: [],
                buttons: [],
                pageTitle: wv.title ?? "",
                currentURL: wv.url?.absoluteString ?? "",
                rawTextSnippet: "",
                message: "خطأ أثناء تنفيذ كشط JavaScript: \(error.localizedDescription)"
            )
        }

        return .empty
    }

    // MARK: - الضغط على أزرار واجهة الراوتر برمجياً (Button Clicker)
    func pressButton(
        router: RouterProfile? = nil,
        selector: String? = nil,
        text: String? = nil,
        semanticAction: SemanticButtonAction? = nil,
        on targetWebView: WKWebView? = nil
    ) async -> (success: Bool, message: String) {
        let wv = targetWebView ?? headlessWebView
        guard let wv = wv else {
            return (false, "محرك الويب غير مهيأ")
        }

        // تجهيز المدخلات للسكريبت
        let selArg = (selector ?? "").replacingOccurrences(of: "\"", with: "\\\"")
        let txtArg = (text ?? "").replacingOccurrences(of: "\"", with: "\\\"")
        let actionStr = semanticAction?.rawValue ?? ""

        let js = """
        (function() {
            // تجاوز أي نوافذ تأكيد قبل الضغط
            window.confirm = function() { return true; };
            window.alert = function() { return true; };

            var targetSelector = "\(selArg)";
            var targetText = "\(txtArg)".toLowerCase().trim();
            var action = "\(actionStr)".toLowerCase();

            var btn = null;

            // 1. محاولة الوصول عبر CSS Selector المباشر
            if (targetSelector.length > 0) {
                try {
                    btn = document.querySelector(targetSelector);
                } catch(e) {}
            }

            // 2. محاولة البحث بالمعنى الدلالي للأمر (Reboot / Login / Apply)
            if (!btn && action.length > 0) {
                var candidates = document.querySelectorAll('button, input[type="button"], input[type="submit"], [role="button"], a');
                for (var i = 0; i < candidates.length; i++) {
                    var el = candidates[i];
                    var t = (el.innerText || el.textContent || el.value || el.id || el.getAttribute('name') || '').toLowerCase();
                    if (action.indexOf('reboot') !== -1 || action.indexOf('إعادة') !== -1) {
                        if (t.indexOf('reboot') !== -1 || t.indexOf('restart') !== -1 || t.indexOf('إعادة') !== -1) {
                            btn = el;
                            break;
                        }
                    } else if (action.indexOf('login') !== -1 || action.indexOf('دخول') !== -1) {
                        if (t.indexOf('login') !== -1 || t.indexOf('signin') !== -1 || t.indexOf('دخول') !== -1) {
                            btn = el;
                            break;
                        }
                    } else if (action.indexOf('apply') !== -1 || action.indexOf('حفظ') !== -1) {
                        if (t.indexOf('apply') !== -1 || t.indexOf('save') !== -1 || t.indexOf('حفظ') !== -1 || t.indexOf('تطبيق') !== -1) {
                            btn = el;
                            break;
                        }
                    }
                }
            }

            // 3. محاولة البحث بنص الزر
            if (!btn && targetText.length > 0) {
                var all = document.querySelectorAll('button, input[type="button"], input[type="submit"], [role="button"], a, span');
                for (var j = 0; j < all.length; j++) {
                    var item = all[j];
                    var content = (item.innerText || item.textContent || item.value || '').toLowerCase().trim();
                    if (content.indexOf(targetText) !== -1) {
                        btn = item;
                        break;
                    }
                }
            }

            if (btn) {
                btn.scrollIntoView();
                // إرسال سلسلة أحداث الفأرة الكاملة لضمان استجابة سكريبت الراوتر
                btn.dispatchEvent(new MouseEvent('mouseenter', { bubbles: true }));
                btn.dispatchEvent(new MouseEvent('mousedown', { bubbles: true }));
                btn.dispatchEvent(new MouseEvent('mouseup', { bubbles: true }));
                btn.click();
                var label = (btn.innerText || btn.value || btn.id || 'زر').trim();
                return JSON.stringify({ success: true, message: 'تم الضغط بنجاح على: ' + label });
            }

            return JSON.stringify({ success: false, message: 'لم يتم العثور على زر مطابق في الصفحة' });
        })();
        """

        do {
            let res = try await wv.evaluateJavaScript(js)
            if let jsonStr = res as? String,
               let data = jsonStr.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let success = dict["success"] as? Bool,
               let msg = dict["message"] as? String {
                return (success, msg)
            }
            return (false, "استجابة غير متوقعة من المتصفح")
        } catch {
            return (false, "خطأ أثناء تنفيذ أمر الضغط: \(error.localizedDescription)")
        }
    }

    // MARK: - تنفيذ كود JavaScript مخصص
    func executeCustomScript(_ script: String, on targetWebView: WKWebView? = nil) async -> (success: Bool, output: String) {
        let wv = targetWebView ?? headlessWebView
        guard let wv = wv else {
            return (false, "محرك الويب غير متوفر")
        }
        do {
            let res = try await wv.evaluateJavaScript(script)
            if let str = res as? String {
                return (true, str)
            } else if let num = res as? NSNumber {
                return (true, "\(num)")
            } else if let dict = res as? [String: Any], let data = try? JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted) {
                return (true, String(data: data, encoding: .utf8) ?? "\(dict)")
            } else if let arr = res as? [Any], let data = try? JSONSerialization.data(withJSONObject: arr, options: .prettyPrinted) {
                return (true, String(data: data, encoding: .utf8) ?? "\(arr)")
            }
            return (true, "تم التنفيذ بنجاح")
        } catch {
            return (false, "خطأ في السكربت: \(error.localizedDescription)")
        }
    }
}
