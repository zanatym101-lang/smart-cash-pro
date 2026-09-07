# سياسة الخصوصية لتطبيق Smart Cash Pro (سمارت كاش برو)

**تاريخ آخر تحديث:** 8 سبتمبر 2026

تلتزم إدارة تطبيق **Smart Cash Pro** ("التطبيق"، "نحن") بحماية خصوصية وأمان بيانات مستخدمينا. توضح هذه السياسة كيفية جمع البيانات، واستخدامها، وحمايتها عند استخدامك للتطبيق.

---

### 1. البيانات المحاسبية والمالية (البيانات المحلية)
* **طبيعة البيانات:** تشمل أسماء العملاء، وأرقام المعاملات، وأرصدة المحافظ، ومحتويات الدرج النقدي، وسجلات القيود اليومية.
* **مكان التخزين:** تُخزن جميع هذه السجلات والبيانات المحاسبية محلياً على جهاز المستخدم (عبر قاعدة بيانات مشفرة SQLite). لا نطلع على هذه المعاملات المالية ولا نشاركها مع أي أطراف خارجية؛ فالأرقام المالية تظل ملكاً حصرياً لصاحب الحساب.

---

### 2. البيانات التي يتم جمعها تلقائياً (خدمات الطرف الثالث)
لتقديم وظائف التطبيق بكفاءة، نعتمد على خدمات معتمدة من Google قد تجمع بعض البيانات المحدودة لأغراض تشغيلية:

* **خدمات الإعلانات (Google AdMob):**
  * يعرض التطبيق إعلانات بمكافأة (Rewarded Ads) لتمديد الفترات التجريبية للمستخدمين.
  * قد تقوم Google AdMob بجمع واستخدام معرف الإعلانات الخاص بجهازك (Advertising ID)، ومعلومات الجهاز، وبيانات الأداء لتوفير إعلانات مناسبة ومكافحة الاحتيال البرمجي.
  * يمكنك مراجعة [سياسة خصوصية Google](https://policies.google.com/privacy).
* **المصادقة والمزامنة (Firebase Authentication & Firestore):**
  * في حال تسجيل الدخول بالبريد الإلكتروني أو ربط الترخيص السحابي، يتم حفظ بيانات الحساب الأساسية (البريد الإلكتروني، حالة تفعيل الترخيص، معرّف الجهاز) للتحقق من صلاحية الاشتراك وإمكانية استرجاع الحساب.

---

### 3. أذونات الجهاز المطلوبة
يطلب التطبيق الحد الأدنى من الصلاحيات الضرورية للعمل:
* **الاتصال بالإنترنت (`INTERNET`):** للتحقق من حالة التراخيص السحابية وتحميل الإعلانات وتحديث بيانات السحابة.
* **الوصول لحالة الشبكة (`ACCESS_NETWORK_STATE`):** للتأكد من توفر اتصال قبل إجراء المزامنة السحابية.

---

### 4. أمان البيانات (Data Security)
نطبق تدابير تقنية متقدمة لحماية بياناتك:
* تشفير قواعد البيانات المحلية ومنع التلاعب بالتطبيق عبر فحص التوقيع الرقمي (Signature Verification).
* استخدام قنوات اتصال مشفرة ومؤمنة ببروتوكول HTTPS في جميع عمليات نقل البيانات السحابية.

---

### 5. خصوصية الأطفال
تطبيق Smart Cash Pro مخصص للأعمال والأنشطة التجارية ونقاط البيع، ولا يستهدف ولا يجمع بيانات الأطفال دون سن 13 عاماً.

---

### 6. التعديلات على سياسة الخصوصية
قد نقوم بتحديث سياسة الخصوصية من وقت لآخر لمواكبة التحديثات البرمجية أو المتطلبات القانونية. يُنصح بمراجعة هذه الصفحة بشكل دوري.

---

### 7. التواصل معنا
إذا كانت لديك أي استفسارات أو أسئلة بخصوص سياسة الخصوصية أو إدارة بياناتك، يمكنك التواصل معنا عبر:
* **البريد الإلكتروني:** `zanatym101@gmail.com`
---
---

# Privacy Policy for Smart Cash Pro

**Last Updated:** September 8, 2026

**Smart Cash Pro** ("we", "our", or "the App") is committed to protecting your privacy. This Privacy Policy describes how your information is collected, used, and safeguarded when you use our POS and accounting application.

---

### 1. Financial & Business Data (Local Storage)
All ledger transactions, customer debt records, drawer balances, and wallet information entered into the App are stored locally on your device using encrypted local storage. We do not access, sell, or disclose your business financial records to any third party.

---

### 2. Third-Party Services & Automated Data Collection
To provide seamless licensing and in-app rewards, the App utilizes official Google services that may collect diagnostic and device identifiers:
* **Google AdMob:** We utilize Google Mobile Ads SDK to serve rewarded ads for trial extensions. AdMob may collect and process device advertising IDs, crash diagnostics, and performance data pursuant to [Google's Privacy & Terms](https://policies.google.com/privacy).
* **Firebase (Auth & Firestore):** Used exclusively for managing user accounts, cloud subscription statuses, and license verification.

---

### 3. Permissions Used
* `android.permission.INTERNET`: Required for cloud license validation and ad fetching.
* `android.permission.ACCESS_NETWORK_STATE`: Required to monitor network connectivity before attempting cloud synchronization.

---

### 4. Security
We enforce strict application integrity mechanisms, including ProGuard/R8 code obfuscation and cryptographic signature validation, to prevent unauthorized tampering and protect local assets.

---

### 5. Contact Us
For any inquiries regarding this Privacy Policy, contact us at:
* **Email:** zanatym101@gmail.com














