# DSL224Manager - Architecture & Agent Instructions (AGENTS.md)

هذا الملف مخصص للمطورين والوكلاء الذكيين (AI Agents) الذين يعملون على هذا المشروع لفهم الهيكلية والبروتوكولات والمحددات التقنية الحساسة.

---

## 🏗️ البنية العامة للمشروع (Project Structure)

المشروع مصمم حالياً كتطبيق iOS أصيل (Native Swift / SwiftUI) مع إعداد مسبق للتوسع لمنصات أخرى (مثل Android):

```
DSL224Manager/
├── App/
│   ├── DSL224ManagerApp.swift       // نقطة انطلاق التطبيق وتنسيق دورة الحياة
│   ├── RouterModels.swift           // هياكل البيانات (RouterProfile, NetworkDevice, FirmwareType)
│   ├── RouterService.swift          // النواة التقنية لإدارة اتصالات الراوترات والمصادقة
│   └── Views/                       // واجهات المستخدم SwiftUI (Dashboard, Devices, Settings, Logs)
├── Widgets/                         // ودجت iOS باستخدام WidgetKit
├── .github/workflows/
│   └── build.yml                    // خط أنابيب البناء السحابي التلقائي (GitHub Actions)
├── README.md                        // دليل المستخدم والمميزات
└── AGENTS.md                        // هذا الملف (مرجع الهيكلية والبروتوكولات)
```

---

## 📡 مواصفات بروتوكولات الراوترات (Router Protocols Reference)

### 1. راوتر Huawei B311-221 (Airbox / Flybox - HiLink API)

#### نقاط النهاية الرئيسية (Endpoints):
- **`GET /api/webserver/SesTokInfo`**:
  - جلب `SesInfo` (قيمة Cookie الأولي) و `TokInfo` (رمز الحماية CSRF token).
- **`POST /api/user/challenge_login`**:
  - مدخلات: `<username>`, `<firstnonce>`, `<mode>1</mode>`.
  - مخرجات: `<salt>` (بصيغة Hex), `<servernonce>`, `<iterations>` (افتراضياً 100).
- **`POST /api/user/authentication_login`**:
  - مدخلات: `<clientproof>`, `<finalnonce>`.
  - مخرجات: `<response>OK</response>` أو `<error><code>108901</code></error>`.
- **`POST /api/wlan/multi-macfilter-settings`**:
  - حظر وإلغاء حظر الأجهزة المتصلة عن طريق تزويد قائمة MAC Filter مصفوفة من `0` إلى `9`.
- **`GET /api/monitoring/traffic-statistics`**:
  - قراءة السرعات اللحظية (`CurrentDownloadRate`, `CurrentUploadRate`).
- **`GET /api/monitoring/month_statistics`**:
  - قراءة الاستهلاك المباشر للشهر من الراوتر.
- **`GET /api/wlan/host-list`**:
  - قائمة الأجهزة المتصلة بالشبكة بالـ IP و الـ MAC والاسم.

#### ⚠️ محددات حاسمة لخوارزمية Huawei SCRAM-SHA256:
1. **صيغة نص المصادقة**:
   ```
   authMsg = firstNonce + "," + finalNonce + "," + finalNonce
   ```
2. **ترتيب معاملات HMAC في CryptoJS المستخدم براوتر هواوي**:
   - `HmacSHA256(message, key)` في كود الراوتر يستقبل `saltPwd` كـ Message و `"Client Key"` كـ Key:
     - `ClientKey = HMAC(key: "Client Key", message: saltPwd)`
     - `ClientSig = HMAC(key: authMsg, message: StoredKey)`
3. **ترميز `clientproof`**:
   - يجب إرساله كـ **Hex-encoded string** (وليس Base64).
4. **أكواد الأخطاء**:
   - `108901`: كلمة المرور غير صحيحة (Wrong Password).
   - `100003`: الجلسة غير مصادق عليها أو منتهية الصلاحية (No Rights).

---

### 2. راوتر D-Link DSL-224 (ME_1.10 Boa / Generic Realtek)

#### نقاط النهاية:
- **تسجيل الدخول**:
  - `POST /login.cgi` أو `POST /boaform/admin/formLogin` (ببيانات `username` و `password`).
- **قراءة البيانات**:
  - `GET /status_traffic.html` أو `GET /tc.html`.
  - استخراج عداد البايتات التراكمي باستخدام Regex.
- **التحكم بالأجهزة**:
  - `POST /form2WlanSetup.cgi` لحظر الـ MAC.
  - `POST /tc.cgi` للتحكم في السرعات وتحديد الـ Bandwidth.

---

## ⚙️ قواعد العمل للوكلاء (Guidelines for Agents)

1. **التعامل مع جلسات الراوتر**:
   - راوترات هواوي وD-Link تسمح بـ **جلسة مدير واحدة فقط (Single Session Admin)** في نفس الوقت.
   - أي تسجيل دخول عبر المتصفح سيُسقط جلسة التطبيق تلقائياً.
2. **الرموز المؤقتة (CSRF Tokens)**:
   - كل طلب `POST` لراوتر هواوي يستهلك الـ `__RequestVerificationToken` المتاح ويتطلب قراءة الرمز الجديد من ترويسة الاستجابة `__RequestVerificationToken`.
3. **أمن الشبكة المحلية**:
   - الراوترات تدعم بروتوكول `HTTP` غير المشفر على المنافذ الافتراضية (`80`) داخل الشبكة المحلية (`192.168.1.1` أو `192.168.2.1`).
   - لا تحاول استخدام `HTTPS` المباشر ما لم يتم تأكيد دعمه في المنفذ `443`.
