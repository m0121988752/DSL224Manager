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
  4. **مُخصّص الكشط المرئي بدون كود (No-Code Scraper Builder UI)**:
     - واجهة تتيح للمستخدم أو الوكيل الذكي تخصيص:
       - `customUsageSelector`: محدد CSS لعداد الاستهلاك.
       - `customUsageRegex`: نمط الاستخراج المطابق للأرقام.
       - `customUsageUnit`: وحدة الاستهلاك (`Auto`, `GB`, `MB`, `Bytes`).
       - `customDeviceTableSelector`: محدد جدول الأجهزة المتصلة.
       - `customRebootButtonSelector`: محدد زر إعادة التشغيل.
     - قوالب سريعة مسبقة الإعداد (Presets) لـ Huawei Flybox و D-Link DSL-224 و Realtek Boaform.

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
