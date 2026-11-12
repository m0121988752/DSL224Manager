# DSL224Manager - Architecture & Multi-Platform Reference (AGENTS.md)

هذا الملف مخصص للوكلاء الذكيين (AI Agents) والمطورين لفهم هيكلية المنظومة عبر المنصتين (**iOS** و **Android**)، بما في ذلك البروتوكولات المشتركة، وحلول التشفير الحساسة، وروابط المستودعات.

---

## 🌐 منظومة المستودعات (Repositories Ecosystem)

المشروع ينقسم إلى مستودعين منفصلين على حساب GitHub (`m0121988752`):

1. **مستودع iOS الأصيل**:
   - **الرابط**: `https://github.com/m0121988752/DSL224Manager`
   - **التقنيات**: Swift, SwiftUI, WidgetKit (الشاشة الرئيسية وشاشة القفل), BGAppRefreshTask, CommonCrypto.
   - **البناء التلقائي**: GitHub Actions (ينتج ملف `DSL224Manager.ipa` متوافق مع TrollStore و AltStore).

2. **مستودع Android الأصيل**:
   - **الرابط**: `https://github.com/m0121988752/DSL224Manager-Android`
   - **التقنيات**: Kotlin, Jetpack Compose, Material 3 (Dark Theme), OkHttp, Coroutines, Java Security/Crypto.
   - **البناء التلقائي**: GitHub Actions (ينتج ملف `app-debug.apk` كـ Artifact باسم `DSL224Manager-Android-APK`).

---

## 📡 مواصفات بروتوكولات الراوترات (Router Protocols Reference)

### 1. راوتر Huawei B311-221 (Airbox / Flybox - HiLink API)

#### نقاط النهاية الرئيسية (Endpoints):
- **`GET /api/webserver/SesTokInfo`**:
  - جلب `SesInfo` (قيمة Cookie الأولية بصيغة `SessionID=...`) و `TokInfo` (رمز CSRF الأولي).
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

#### ⚠️ الحل الدقيق لخوارزمية Huawei SCRAM-SHA256 (مستخرج ومطابق 100% لسورس كود الراوتر):
1. **صيغة نص المصادقة (`authMsg`)**:
   ```
   authMsg = firstNonce + "," + finalNonce + "," + finalNonce
   ```
2. **عكس معاملات HMAC بسبب بنية مكتبة CryptoJS في راوتر هواوي**:
   - دالة هواوي في `scram.js`:
     ```javascript
     clientKey: function(saltPwd) { return this.cfg.hmac(saltPwd, "Client Key"); }
     signature: function(storedKey, authMessage) { return this.cfg.hmac(storedKey, authMessage); }
     ```
   - وحيث أن `HmacSHA256(message, key)` في نسختهم تستقبل `message` أولاً ثم `key`، فإن التشفير الفعلي هو:
     - `clientKey = HMAC-SHA256(key: "Client Key", data: saltedPassword)`
     - `storedKey = SHA256(clientKey)`
     - `clientSig = HMAC-SHA256(key: authMsg, data: storedKey)`
     - `clientProof = hexFromData(clientKey ^ clientSig)`
3. **صيغة `clientproof`**:
   - ترسل كـ **Hex-encoded string** (وليس Base64).
4. **أكواد الاستجابة**:
   - `108901`: كلمة المرور غير صحيحة (Wrong Password).
   - `100003`: جلسة غير مصادق عليها أو منتهية.

---

### 2. راوتر D-Link DSL-224 (ME_1.10 Boa / Generic Realtek)

- **تسجيل الدخول**: `POST /login.cgi` أو `POST /boaform/admin/formLogin`.
- **قراءة العداد**: `GET /status_traffic.html` أو `GET /tc.html` واستخراج البايتات التراكمية عبر Regex.
- **التحكم وحظر الأجهزة**: `POST /form2WlanSetup.cgi`.
- **تحديد السرعة (Traffic Control)**: `POST /tc.cgi`.

---

## ⚙️ قواعد وإرشادات عامة للمطورين والوكلاء (Agent Rules)

1. **قاعدة الجلسة الأحادية (Single-Session)**:
   - الراوترات تسمح بمدير واحد فقط متصل. أي دخول عبر المتصفح أثناء عمل التطبيق يلغي الجلسة تلقائياً.
2. **تحديث الرموز الأمنية (CSRF Tokens)**:
   - كل استجابة لطلب POST تحمل رمزا جديدا في ترويسة `__RequestVerificationToken` يجب استخدامه للطلب التالي.
3. **سلامة بناء الأندرويد**:
   - مشروع الأندرويد يتطلب `android.useAndroidX=true` في `gradle.properties`.
   - إعداد المستودعات يتم مركزياً في `settings.gradle.kts` عبر `pluginManagement` و `dependencyResolutionManagement`.
