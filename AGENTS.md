# DSL224Manager - Architecture & Multi-Platform Reference (AGENTS.md)

هذا الملف مخصص للوكلاء الذكيين (AI Agents) والمطورين لفهم هيكلية المنظومة عبر المنصتين (**iOS** و **Android**)، بما في ذلك البروتوكولات المشتركة، وحلول التشفير الحساسة، وقواعد الرموز الأمنية (CSRF & Tokens)، ومحرك الـ No-Code، وروابط المستودعات.

---

## 🌐 منظومة المستودعات (Repositories Ecosystem)

المشروع ينقسم إلى مستودعين منفصلين على حساب GitHub (`m0121988752`):

1. **مستودع iOS الأصيل**:
   - **الرابط**: `https://github.com/m0121988752/DSL224Manager`
   - **التقنيات**: Swift, SwiftUI, WidgetKit (الشاشة الرئيسية وشاشة القفل), BGAppRefreshTask, CommonCrypto, WebKit (WKWebView).
   - **البناء التلقائي**: GitHub Actions (ينتج ملف `DSL224Manager.ipa` متوافق مع TrollStore و AltStore).

2. **مستودع Android الأصيل**:
   - **الرابط**: `https://github.com/m0121988752/DSL224Manager-Android`
   - **التقنيات**: Kotlin, Jetpack Compose, Material 3 (Dark Theme + RTL), OkHttp, Coroutines, SharedPreferences, Android WebView.
   - **البناء التلقائي**: GitHub Actions (ينتج ملف `app-debug.apk` كـ Artifact باسم `DSL224Manager-Android-APK`).

---

## 📡 مواصفات بروتوكولات الراوترات (Router Protocols Reference)

### 1. راوتر Huawei B311-221 (Airbox / Flybox - HiLink API)

#### نقاط النهاية الرئيسية (Endpoints):
- **`GET /api/webserver/SesTokInfo`**:
  - جلب `SesInfo` (قيمة Cookie الأولية بصيغة `SessionID=...`) و `TokInfo` (رمز CSRF الأولي).
- **`GET /api/user/state-login`**:
  - فحص حالة جلسة تسجيل الدخول الحالية (`<State>0</State>` تعني مسجل الدخول بنجاح).
- **`POST /api/user/challenge_login`**:
  - مدخلات: `<username>`, `<firstnonce>` (24 إلى 32 بايت عشوائي hex), `<mode>1</mode>`.
  - مخرجات: `<salt>` (بصيغة Hex), `<servernonce>`, `<iterations>` (افتراضياً 100).
- **`POST /api/user/authentication_login`**:
  - مدخلات: `<clientproof>`, `<finalnonce>`.
  - مخرجات: `<response>OK</response>` أو `<error><code>108901</code></error>`.
- **`POST /api/wlan/multi-macfilter-settings`**:
  - حظر وفصل الأجهزة أو إعادتها عبر قائمة الـ MAC Filter المفهرسة من `0` إلى `9` (`WifiMacFilterStatus`: 2 للـ Blacklist، و 0 للإيقاف).
- **`GET /api/monitoring/traffic-statistics`**:
  - السرعات اللحظية للرفع والتحميل بالكيلوبايت/ثانية.
- **`GET /api/monitoring/month_statistics`**:
  - استهلاك الباقة التراكمي المدمج في الراوتر للشهر الحالي (`CurrentMonthDownload` + `CurrentMonthUpload`).
- **`GET /api/wlan/host-list`**:
  - قائمة الأجهزة المتصلة (`HostName`, `IpAddress`, `MacAddress`).
- **`GET /api/webserver/token`**:
  - توليد رمز حماية طازج جديد (Single-use CSRF Token).

#### ⚠️ حلول أمنية وتشفيرية دقيقة لراوتر هواوي (مستخرجة ومطابقة 100% لسورس كود الراوتر):
1. **خوارزمية SCRAM-SHA256**:
   - نص المصادقة: `authMsg = firstNonce + "," + finalNonce + "," + finalNonce`
   - عكس معاملات HMAC (بسبب مكتبة CryptoJS لهواوي):
     - `clientKey = HMAC-SHA256(key: "Client Key", data: saltedPassword)`
     - `storedKey = SHA256(clientKey)`
     - `clientSig = HMAC-SHA256(key: authMsg, data: storedKey)`
     - `clientProof = hexFromData(clientKey ^ clientSig)` (يرسل كـ Hex-string وليس Base64).
2. **قواعد رموز التحقق والـ Tokens لتفادي أخطاء (125003 و 100003)**:
   - **اقتطاع آخر 32 خانة**: استدعاء `/api/webserver/token` يعيد رمزاً من 64 خانة. يقبل الراوتر في طلبات POST **آخر 32 خانة فقط** (`token.substr(32)`).
   - **ربط الـ Token بالجلسة (`Session-Bound Token`)**: عند استدعاء `/api/webserver/token` يجب تمرير ترويسة `Cookie: SessionID=...` الخاصة بالجلسة الموثقة، وإلا سيعتبرها الراوتر جلسة ضيف ويعيد خطأ `125003 (ERROR_WRONG_SESSION_TOKEN)`.
   - **الترويسة المطلوبة في POST**: إضافة ترويسة `_ResponseSource: Broswer` مع كل طلب حظر.
3. **أكواد الاستجابة الشائعة**:
   - `108901`: كلمة المرور غير صحيحة (Wrong Password).
   - `100003`: جلسة غير مصادق عليها أو منتهية الصلاحية (`ERROR_SYSTEM_NO_RIGHTS`).
   - `125001`: رمز Token غير صحيح (`ERROR_WRONG_TOKEN`).
   - `125003`: رمز Token لا يطابق الجلسة الحالية (`ERROR_WRONG_SESSION_TOKEN`).

---

### 2. راوتر D-Link DSL-224 (ME_1.10 Boa / Generic Realtek)

- **تسجيل الدخول**: `POST /login.cgi` أو `POST /boaform/admin/formLogin`.
- **قراءة العداد**: `GET /status_traffic.html` أو `GET /tc.html` واستخراج البايتات التراكمية عبر Regex.
- **التحكم وحظر الأجهزة**: `POST /form2WlanSetup.cgi`.
- **تحديد السرعة (Traffic Control)**: `POST /tc.cgi`.

---

### 3. محرك الكشط والتحكم البديل عبر المتصفح (WebUI Fallback & Button Automation)

- **الهدف**: عندما تفشل طلبات API المباشرة أو يختلف إصدار السوفتوير أو تكون الجلسة معقدة، يعمل محرك `WebUIFallbackService` تلقائياً عبر متصفح الويب المدمج (WebKit في iOS و WebView في Android).
- **القدرات**:
  1. **تسجيل الدخول التلقائي (Auto-Login)**:
     - فحص وحقن اسم المستخدم وكلمة المرور في حقول النموذج وتفعيل أحداث `input` و `change` ثم محاكاة النقر على زر الدخول.
  2. **كشط محتوى DOM (DOM Scraping)**:
     - استخراج عدادات بايتات الـ WAN التراكمية، جداول الأجهزة، والسرعات الحية.
  3. **الضغط التلقائي على الأزرار (Button Automation)**:
     - الضغط بالمعنى الدلالي (`Semantic Action`): أزرار إعادة التشغيل (`Reboot` / `Restart`)، الحفظ (`Apply` / `Save`)، التحديث، والدخول.
     - الضغط عبر محدد CSS المباشر (`#btn_reboot`, `#reboot_apply_button`).
     - تجاوز مربعات التأكيد التنبيهية (`window.confirm = () => true`).
  4. **مُخصّص الكشط المرئي ومُلتقِط العناصر بدون كود لأي راوتر (Universal No-Code Visual Element Picker)**:
     - يتيح لأي مستخدم ربط تطبيقه بأي راوتر في العالم (Huawei, D-Link, TP-Link, ZTE, Vodafone, Orange, WE, Netgear, Xiaomi, Tenda, إلخ) دون كتابة سطر كود واحد:
     - **وضع الالتقاط البصري التفاعلي (Interactive Picker Mode)**:
       - تفعيل وضع الالتقاط بنقرة زر في شريط أدوات المتصفح المدمج.
       - طبقة إبراز عائمة بلون أخضر تتبع مؤشر اللمس (`Highlight Overlay & Badge`).
       - منع التنفيذ التلقائي للأزرار والروابط أثناء الالتقاط لتجنب إعادة التشغيل غير المقصودة (`e.preventDefault()`).
       - توليد محدد CSS فريد ودقيق بذكاء (`#id`, `tag[name=...]`, مسار تراتبي).
     - **اقتراح ذكي وتعيين فوري (Smart Type Detection & 1-Tap Assignment)**:
       - نافذة فورية تقترح نوع العنصر تلقائياً بناءً على نصه ومكانه:
         - 📊 **عداد استهلاك الباقة**: يستخرج المحدد ويكتشف الوحدة تلقائياً (`GB`, `MB`, `Bytes`).
         - 📱 **جدول الأجهزة المتصلة**: يكشف جداول الـ MAC/IP وحصر الأجهزة.
         - 🔄 **زر إعادة التشغيل**: يعين زر الـ Reboot لأتمتة إعادة التشغيل.
         - 🔑 **حقل اسم المستخدم**: لملء الدخول التلقائي في أي راوتر.
         - 🔒 **حقل كلمة المرور**: لملء كلمة السر التلقائية.
         - 🚪 **زر تسجيل الدخول**: للنقر عليه تلقائياً بعد ملء النموذج.
     - **تخزين المحددات**:
       - `customUsageSelector`, `customUsageRegex`, `customUsageUnit`
       - `customDeviceTableSelector`, `customRebootButtonSelector`
       - `customUsernameSelector`, `customPasswordSelector`, `customLoginButtonSelector`
  5. **مكتبة قوالب الراوترات الجاهزة ومشاركتها الآمنة (Router Presets & Template Sharing)**:
     - توفير 6 قوالب جاهزة ومعتمدة مسبقاً لأشهر راوترات مصر والشرق الأوسط:
       - **D-Link DSL-224** (ME_1.10 Boa)
       - **ZTE ZXHN H168N / H188A** (VDSL الأكثر انتشاراً لـ WE وفودافون وأورنج)
       - **Huawei B311-221** (HiLink 4G Flybox)
       - **Vodafone VDSL** (H300s / DG8045)
       - **TP-Link Archer / VR600** (VDSL & 4G)
       - **Orange Home 4G Flybox** (MF283+)
     - تصدير واستيراد القوالب بضغطة زر كملفات JSON عبر الحافظة (Clipboard) مع **تجريد وحذف كلمة المرور والبيانات الحساسة تماماً** لضمان الخصوصية عند المشاركة بين المستخدمين عبر المنصتين (iOS و Android).
  6. **المعاينة الفورية الذكية واختبار النقر المباشر (Live Instant Preview & Test Click)**:
     - شارة فحص فورية في نافذة تعيين العنصر تحسب القيمة المستخرجة لحظياً (الجيجابايت أو عداد البايتات أو جدول الأجهزة).
     - زر `⚡ اختبار النقر المباشر (Test Click)` لتشغيل كود المحاكاة مباشرة في المتصفح وإبراز العنصر بلون أحمر والتأكد من استجابته قبل اعتماده.

---

## 🎨 معايير واجهة المستخدم (UI/UX Standards)

1. **نظام التبويبات الرباعي في Android & iOS**:
   - **الشبكة (Dashboard)**: بطاقة الباقة الكبيرة، سرعات الرفع والتحميل الحية، شريط البحث، شرائح الفلترة (الكل / متصل / محظور)، وبطاقات الأجهزة مع زر حظر سريع وزر تعديل الاسم.
   - **الراوترات (Routers)**: إدارة وتعدد الراوترات وإضافة وحذف الملفات.
   - **الإحصائيات والسجل (Stats & Logs)**: بطاقة مواصفات الراوتر وسجل الأحداث اللحظي الملون.
   - **الإعدادات (Settings)**: بيانات الدخول، إظهار/إخفاء كلمة المرور، كشط WebUI، وباني الـ No-Code.
2. **التحديث الفوري المتفائل (`Optimistic UI Updates`)**:
   - عند الضغط على زر الحظر أو فك الحظر، يتم تحديث واجهة القائمة فورياً في جزء من الثانية، مع تزويد `items()` في `LazyColumn` بالمفتاح الفريد `key = { it.macAddress }` لمنع تأخر إعادة البناء.
3. **تخزين الإعدادات وكلمات المرور**:
   - في Android: حفظ البيانات محلياً في `SharedPreferences` عبر `RouterStorage.kt` لضمان عدم فقدان كلمة المرور والإعدادات عند الإغلاق.
   - في iOS: حفظ البيانات في `UserDefaults` التابعة للـ App Group لدعم الودجت والتطبيق معاً.
4. **معالج الإعداد الذكي التلقائي لأول مرة (First-Time Setup Wizard)**:
   - يظهر تلقائياً عند فتح التطبيق لأول مرة أو يدويّاً من شريط الإجراءات السريعة وتبويب الإعدادات.
   - يتضمن 4 خطوات انسيابية:
     1. **الكشف التلقائي (Auto-Detection)**: فحص عناوين البوابات الشائعة (`192.168.1.1`, `192.168.8.1`, `192.168.0.1`, `192.168.2.1`) والتعرف التلقائي على طراز الراوتر ونظامه مع ربطه بالقالب المناسب.
     2. **بيانات الدخول واختبار الاتصال اللحظي (Credentials & Live Test)**: إدخال اسم المستخدم وكلمة السر مع زر `⚡ اختبار الاتصال بكلمة المرور الآن` للتحقق الفوري من صحتها قبل الحفظ.
     3. **إعداد الباقة الشهرية (Monthly Plan & Cycle)**: شرائح سريعة لحجم الباقة (140, 200, 250, 300, 400 GB)، يوم التجديد الشهري، والاستهلاك المبدئي لمنتصف الشهر.
     4. **المراجعة والتطبيق (Finish & Apply)**: ملخص شامل وتطبيق فوري للإعدادات وبدء المزامنة.
5. **معايير شريط التطبيق والسرعات الحية وشريط الإجراءات**:
   - **منع تداخل العنوان مع الأزرار في الشريط العلوي**: حصر الإجراءات الثانوية داخل قائمة منسدلة (`DropdownMenu`) لتوفير مساحة كاملة لعنوان الراوتر مع `maxLines = 1, overflow = Ellipsis`.
   - **الظهور الدائم لسرعات الرفع والتحميل الحية**: عرض شارات ملونة ثابتة (↓ أزرق للتحميل، ↑ أخضر للرفع) على بطاقة الباقة دائماً حتى أثناء الخمول (`0.0 KB/s`) مع تنسيق رقمي برمجياً (`Locale.US`) يمنع التداخل أو انقلاب الأرقام مع واجهة الـ RTL العربية.
   - **شريط الإجراءات السريعة (Quick Actions Bar)**: صف أفقي أسفل بطاقة الباقة للوصول السريع بضغطة زر إلى: متصفح الراوتر 🌐، معالج الإعداد 🪄، قوالب الراوترات 📋، تحديث البيانات 🔄، وإعادة التشغيل ⏻.
   - **تحسين شاشة الأجهزة الفارغة**: تقديم أزرار استرشادية واضحة لطلب التحديث أو إعادة تشغيل معالج الإعداد الذكي.
