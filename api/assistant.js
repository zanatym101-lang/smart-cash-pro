const crypto = require("crypto");

const GEMINI_API_BASE =
  "https://generativelanguage.googleapis.com/v1beta/models";
const GEMINI_MODELS = [
  "gemini-2.5-flash",
  "gemini-2.5-flash-lite",
  "gemini-2.0-flash",
  "gemini-2.0-flash-lite",
];

const REQUEST_TIMEOUT_MS = 30000;
const MAX_QUESTION_LENGTH = 1800;
const RATE_LIMIT_WINDOW_MS = 60 * 1000;
const RATE_LIMIT_MAX_REQUESTS = 40;
const AUTH_MAX_AGE_MS = 5 * 60 * 1000;
const NONCE_TTL_MS = 10 * 60 * 1000;
const DAILY_QUOTA_LIMIT = readPositiveInt(
  process.env.ASSISTANT_DAILY_QUOTA,
  1500,
);
const MONTHLY_QUOTA_LIMIT = readPositiveInt(
  process.env.ASSISTANT_MONTHLY_QUOTA,
  20000,
);

const requestBuckets = new Map();
const nonceCache = new Map();
const quotaBuckets = new Map();

function readPositiveInt(value, fallback) {
  const parsed = Number.parseInt(String(value || ""), 10);
  if (!Number.isFinite(parsed) || parsed <= 0) return fallback;
  return parsed;
}

function allowedOrigins() {
  const raw = process.env.ASSISTANT_ALLOWED_ORIGINS || "";
  return raw
    .split(",")
    .map((x) => x.trim())
    .filter(Boolean);
}

function setCors(req, res) {
  const origin = safeString(req.headers.origin);
  const allowList = allowedOrigins();

  const hasOrigin = origin.length > 0;
  const originAllowed = !hasOrigin
    ? true
    : allowList.length > 0 && allowList.includes(origin);

  if (originAllowed && hasOrigin) {
    res.setHeader("Access-Control-Allow-Origin", origin);
    res.setHeader("Vary", "Origin");
  }
  res.setHeader("Access-Control-Allow-Methods", "POST, OPTIONS");
  res.setHeader(
    "Access-Control-Allow-Headers",
    "Content-Type, Authorization, X-SCP-TS, X-SCP-Nonce, X-SCP-Signature, X-SCP-Client-Token, X-SCP-Client-Id",
  );

  return { origin, allowList, originAllowed };
}

function nowMs() {
  return Date.now();
}

function getClientIp(req) {
  const fwd = req.headers["x-forwarded-for"];
  if (Array.isArray(fwd) && fwd.length > 0) return fwd[0];
  if (typeof fwd === "string" && fwd.trim()) {
    return fwd.split(",")[0].trim();
  }
  return req.socket?.remoteAddress || "unknown";
}

function getClientId(req) {
  return safeString(req.headers["x-scp-client-id"]);
}

function quotaClientId(req) {
  const clientId = getClientId(req);
  if (clientId) return clientId;
  return `ip:${getClientIp(req)}`;
}

function getRateKey(req) {
  return `${getClientIp(req)}|${quotaClientId(req)}`;
}

function isRateLimited(rateKey) {
  const now = nowMs();
  const previous = requestBuckets.get(rateKey) || [];
  const fresh = previous.filter((t) => now - t <= RATE_LIMIT_WINDOW_MS);
  fresh.push(now);
  requestBuckets.set(rateKey, fresh);
  return fresh.length > RATE_LIMIT_MAX_REQUESTS;
}

function safeString(value) {
  return (value ?? "").toString().trim();
}

function sanitizeQuestion(question) {
  return question.replace(/\u0000/g, "").trim().slice(0, MAX_QUESTION_LENGTH);
}

function normalizeQuestion(question) {
  return safeString(question)
    .toLowerCase()
    .replace(/\s+/g, " ")
    .trim();
}

function includesAny(question, keywords) {
  return keywords.some((k) => question.includes(k));
}

function toNumber(value) {
  const n = Number(value);
  return Number.isFinite(n) ? n : null;
}

function formatMoney(value) {
  const n = toNumber(value);
  if (n == null) return "غير متاح";
  return n.toFixed(2);
}

function classifyIntent(question) {
  const q = normalizeQuestion(question);

  if (
    includesAny(q, [
      "شرح التطبيق",
      "طريقة عمل",
      "كيف يعمل",
      "اشرح النظام",
      "explain",
      "how it works",
    ])
  ) {
    return "how";
  }

  if (
    includesAny(q, [
      "السيولة المتاحة",
      "السيولة",
      "available liquidity",
      "liquidity now",
    ])
  ) {
    return "liquidity";
  }

  if (
    includesAny(q, [
      "الخزنة الفعلية",
      "الخزنة",
      "actual treasury",
      "treasury",
    ])
  ) {
    return "treasury";
  }

  if (
    includesAny(q, [
      "رأس المال",
      "راس المال",
      "المال الحقيقي",
      "real capital",
      "capital",
    ])
  ) {
    return "capital";
  }

  if (
    includesAny(q, [
      "المستحقات",
      "لنا",
      "علينا",
      "receivable",
      "payable",
      "claims",
    ])
  ) {
    return "claims";
  }

  if (
    includesAny(q, ["ربح اليوم", "أرباح اليوم", "daily profit", "today profit"])
  ) {
    return "profit_daily";
  }

  if (
    includesAny(q, [
      "ربح الشهر",
      "أرباح الشهر",
      "monthly profit",
      "month profit",
    ])
  ) {
    return "profit_monthly";
  }

  if (
    includesAny(q, [
      "الدرج",
      "المحافظ",
      "رصيد فوري",
      "fawry",
      "wallets",
      "drawer",
    ])
  ) {
    return "balances";
  }

  const isVeryShort = q.length <= 4 || q.split(" ").length <= 1;
  if (isVeryShort || includesAny(q, ["اين", "فين", "where", "what"])) {
    return "clarify";
  }

  return "llm";
}

function buildHowAnswer(body) {
  const guide = body?.programGuide || {};
  const principles = Array.isArray(guide.principles) ? guide.principles : [];
  const formulas = guide.liquidityFormulas || {};

  const lines = [];
  lines.push("طريقة عمل البرنامج باختصار:");
  if (principles.length) {
    for (const p of principles.slice(0, 6)) {
      lines.push(`- ${p}`);
    }
  }
  if (Object.keys(formulas).length) {
    lines.push("");
    lines.push("المعادلات الأساسية:");
    if (formulas.actualTreasuryApproved) {
      lines.push(`- الخزنة الفعلية = ${formulas.actualTreasuryApproved}`);
    }
    if (formulas.availableLiquidityNow) {
      lines.push(`- السيولة المتاحة = ${formulas.availableLiquidityNow}`);
    }
    if (formulas.realCapitalApproved) {
      lines.push(`- رأس المال الحقيقي = ${formulas.realCapitalApproved}`);
    }
  }
  lines.push("");
  lines.push("لو تريد شرح جزء محدد (تحويل/استلام/فوري/مستحقات)، اكتب اسمه مباشرة.");
  return lines.join("\n");
}

function buildDeterministicAnswer(question, body) {
  const intent = classifyIntent(question);
  const snap = body?.snapshot || {};
  const claims = body?.claims || {};
  const currency = safeString(body?.meta?.currency || "EGP");

  if (intent === "clarify") {
    return {
      mode: intent,
      answer:
        "سؤالك قصير وغير واضح. اكتب المطلوب بشكل مباشر، مثال:\n- كم السيولة المتاحة الآن؟\n- كم لنا وعلينا؟\n- اشرح طريقة عمل البرنامج.",
    };
  }

  if (intent === "how") {
    return { mode: intent, answer: buildHowAnswer(body) };
  }

  if (intent === "liquidity") {
    const v = formatMoney(snap.availableLiquidityNow);
    const t = formatMoney(snap.actualTreasuryApproved);
    const p = formatMoney(snap.pendingNet);
    return {
      mode: intent,
      answer:
        `النتيجة: ${v} ${currency}\n` +
        `المعادلة: الخزنة الفعلية (${t}) + صافي المعلّق (${p}) = ${v}\n` +
        "المصدر: snapshot.availableLiquidityNow / snapshot.actualTreasuryApproved / snapshot.pendingNet",
    };
  }

  if (intent === "treasury") {
    const v = formatMoney(snap.actualTreasuryApproved);
    return {
      mode: intent,
      answer:
        `النتيجة: ${v} ${currency}\n` +
        "المعادلة: الدرج الفعلي + المحافظ الفعلية + فوري الفعلي\n" +
        "المصدر: snapshot.actualTreasuryApproved",
    };
  }

  if (intent === "capital") {
    const v = formatMoney(snap.realCapitalApproved);
    const r = formatMoney(claims.openReceivable);
    const p = formatMoney(claims.openPayable);
    return {
      mode: intent,
      answer:
        `النتيجة: ${v} ${currency}\n` +
        `المعادلة: الخزنة الفعلية + (لنا ${r} - علينا ${p})\n` +
        "المصدر: snapshot.realCapitalApproved + claims.openReceivable/openPayable",
    };
  }

  if (intent === "claims") {
    const r = formatMoney(claims.openReceivable);
    const p = formatMoney(claims.openPayable);
    const n = formatMoney(claims.openNet);
    return {
      mode: intent,
      answer:
        `لنا: ${r} ${currency}\n` +
        `علينا: ${p} ${currency}\n` +
        `الصافي: ${n} ${currency}\n` +
        `المعادلة: ${r} - ${p} = ${n}\n` +
        "المصدر: claims.openReceivable / claims.openPayable / claims.openNet",
    };
  }

  if (intent === "profit_daily") {
    const v = formatMoney(snap.dailyProfit);
    return {
      mode: intent,
      answer:
        `ربح اليوم: ${v} ${currency}\n` +
        "المصدر: snapshot.dailyProfit",
    };
  }

  if (intent === "profit_monthly") {
    const v = formatMoney(snap.monthlyProfit);
    return {
      mode: intent,
      answer:
        `ربح الشهر: ${v} ${currency}\n` +
        "المصدر: snapshot.monthlyProfit",
    };
  }

  if (intent === "balances") {
    return {
      mode: intent,
      answer:
        `الدرج الفعلي: ${formatMoney(snap.drawerActualBalance)} ${currency}\n` +
        `المحافظ الفعلية: ${formatMoney(snap.walletsActualTotal)} ${currency}\n` +
        `فوري الفعلي: ${formatMoney(snap.fawryActualBalance)} ${currency}\n` +
        "المصدر: snapshot.drawerActualBalance / walletsActualTotal / fawryActualBalance",
    };
  }

  return null;
}

function utcDayKey(ms) {
  const d = new Date(ms);
  return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(
    2,
    "0",
  )}-${String(d.getUTCDate()).padStart(2, "0")}`;
}

function utcMonthKey(ms) {
  const d = new Date(ms);
  return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(
    2,
    "0",
  )}`;
}

function consumeQuota(req) {
  const clientId = quotaClientId(req);
  const now = nowMs();
  const dayKey = utcDayKey(now);
  const monthKey = utcMonthKey(now);

  const current = quotaBuckets.get(clientId) || {
    dayKey,
    dayCount: 0,
    monthKey,
    monthCount: 0,
  };

  if (current.dayKey !== dayKey) {
    current.dayKey = dayKey;
    current.dayCount = 0;
  }
  if (current.monthKey !== monthKey) {
    current.monthKey = monthKey;
    current.monthCount = 0;
  }

  if (current.dayCount >= DAILY_QUOTA_LIMIT) {
    return {
      ok: false,
      status: 429,
      error: "daily_quota_exceeded",
      dayRemaining: 0,
      monthRemaining: Math.max(0, MONTHLY_QUOTA_LIMIT - current.monthCount),
      clientId,
    };
  }
  if (current.monthCount >= MONTHLY_QUOTA_LIMIT) {
    return {
      ok: false,
      status: 429,
      error: "monthly_quota_exceeded",
      dayRemaining: Math.max(0, DAILY_QUOTA_LIMIT - current.dayCount),
      monthRemaining: 0,
      clientId,
    };
  }

  current.dayCount += 1;
  current.monthCount += 1;
  quotaBuckets.set(clientId, current);
  return {
    ok: true,
    clientId,
    dayRemaining: Math.max(0, DAILY_QUOTA_LIMIT - current.dayCount),
    monthRemaining: Math.max(0, MONTHLY_QUOTA_LIMIT - current.monthCount),
  };
}

function cleanupNonceCache(now) {
  for (const [key, ts] of nonceCache.entries()) {
    if (now - ts > NONCE_TTL_MS) {
      nonceCache.delete(key);
    }
  }
}

function safeEqual(a, b) {
  const left = Buffer.from(a || "", "utf8");
  const right = Buffer.from(b || "", "utf8");
  if (left.length !== right.length) return false;
  return crypto.timingSafeEqual(left, right);
}

function expectedClientToken() {
  return (
    process.env.ASSISTANT_CLIENT_TOKEN ||
    process.env.CLOUD_ASSISTANT_CLIENT_TOKEN ||
    ""
  );
}

function verifyClientAuth(req) {
  const serverToken = expectedClientToken();
  if (!serverToken) {
    return {
      ok: false,
      status: 500,
      error: "missing_server_auth_token",
    };
  }

  const clientToken = safeString(req.headers["x-scp-client-token"]);
  const tsRaw = safeString(req.headers["x-scp-ts"]);
  const nonce = safeString(req.headers["x-scp-nonce"]);
  const signature = safeString(req.headers["x-scp-signature"]);
  const clientId = getClientId(req);

  if (!clientToken || !tsRaw || !nonce || !signature) {
    return { ok: false, status: 401, error: "missing_client_auth_headers" };
  }
  if (!clientId) {
    return { ok: false, status: 401, error: "missing_client_id" };
  }

  if (!safeEqual(clientToken, serverToken)) {
    return { ok: false, status: 401, error: "invalid_client_token" };
  }

  const ts = Number.parseInt(tsRaw, 10);
  if (!Number.isFinite(ts)) {
    return { ok: false, status: 401, error: "invalid_timestamp" };
  }

  const now = nowMs();
  if (Math.abs(now - ts) > AUTH_MAX_AGE_MS) {
    return { ok: false, status: 401, error: "expired_timestamp" };
  }

  cleanupNonceCache(now);
  const nonceKey = `${getClientId(req)}:${nonce}`;
  if (nonceCache.has(nonceKey)) {
    return { ok: false, status: 409, error: "replayed_request" };
  }

  const expectedSig = crypto
    .createHmac("sha256", serverToken)
    .update(`${tsRaw}.${nonce}`)
    .digest("hex");
  if (!safeEqual(signature, expectedSig)) {
    return { ok: false, status: 401, error: "invalid_signature" };
  }

  nonceCache.set(nonceKey, now);
  return { ok: true };
}

function toJsonText(value) {
  try {
    return JSON.stringify(value, null, 2);
  } catch (_) {
    return String(value);
  }
}

function toTextBlock(title, value) {
  if (value == null) return "";
  const text = typeof value === "string" ? value.trim() : toJsonText(value);
  if (!text) return "";
  return `${title}:\n${text}`;
}

function joinAnswerParts(candidate) {
  const parts = candidate?.content?.parts;
  if (!Array.isArray(parts)) return "";
  return parts
    .map((p) => (typeof p?.text === "string" ? p.text : ""))
    .join("\n")
    .trim();
}

function detectResponseMode(question) {
  const q = normalizeQuestion(question);
  if (
    includesAny(q, [
      "كم",
      "كام",
      "السيولة",
      "الخزنة",
      "المستحقات",
      "ارباح",
      "أرباح",
      "ربح",
      "balances",
      "liquidity",
      "profit",
    ])
  ) {
    return "numeric";
  }
  if (
    includesAny(q, ["اشرح", "شرح", "طريقة عمل", "كيف", "explain", "how"])
  ) {
    return "how";
  }
  if (
    includesAny(q, ["تحليل", "تشخيص", "مشكلة", "لماذا", "diagnose", "why"])
  ) {
    return "diagnostic";
  }
  return "detailed";
}

function responsePolicy(mode) {
  const common = [
    "أنت مساعد مالي داخل Smart Cash Pro.",
    "التزم بالبيانات المرسلة فقط ولا تخمن أي رقم.",
    "اللغة: العربية الفصحى الواضحة.",
    "إذا كانت البيانات غير كافية، اذكر ذلك صراحة واطلب العنصر الناقص.",
  ];

  if (mode === "numeric") {
    return [
      ...common,
      "تنسيق الرد الإلزامي:",
      "النتيجة: ...",
      "المعادلة: ...",
      "المصدر: ...",
      "الرد مختصر (3-5 أسطر).",
    ].join("\n");
  }

  if (mode === "how") {
    return [
      ...common,
      "اشرح بشكل عملي مختصر في نقاط مرتبة.",
      "اربط الشرح بقواعد PROGRAM_GUIDE ومعادلات SNAPSHOT.",
      "اختم بسطر: ما الذي تريدني أن أشرحه بعد ذلك؟",
    ].join("\n");
  }

  if (mode === "diagnostic") {
    return [
      ...common,
      "قدّم تحليل سبب/أثر/حل.",
      "اذكر أي تناقض رقمي إن وجد.",
      "اختم بخطوة تنفيذية واحدة واضحة.",
    ].join("\n");
  }

  return [
    ...common,
    "قدّم إجابة متوسطة الطول مرتبة بعناوين قصيرة.",
  ].join("\n");
}

function buildPrompt(question, body) {
  const mode = detectResponseMode(question);
  const system = [
    "??? ????? ???? ??? ???? ????? Smart Cash Pro.",
    "???? ??????? ?????? ?? ???????? ??????? ?? ??? ?????.",
    responsePolicy(mode),
  ].join("\n\n");

  const blocks = [
    toTextBlock("META", body?.meta),
    toTextBlock("PROGRAM_GUIDE", body?.programGuide),
    toTextBlock("SNAPSHOT", body?.snapshot),
    toTextBlock("WALLETS", body?.wallets),
    toTextBlock("CLAIMS", body?.claims),
    toTextBlock("TXNS_SUMMARY", body?.txnsSummary),
    toTextBlock("RECENT_TXNS", body?.recentTxns),
  ].filter(Boolean);

  return `${system}\n\nRESPONSE_MODE:\n${mode}\n\n${blocks.join("\n\n")}\n\nQUESTION:\n${question}`;
}

async function callGemini({ model, prompt, apiKey }) {
  const url = `${GEMINI_API_BASE}/${model}:generateContent?key=${apiKey}`;
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);
  try {
    const response = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      signal: controller.signal,
      body: JSON.stringify({
        contents: [{ role: "user", parts: [{ text: prompt }] }],
        generationConfig: {
          temperature: 0.1,
          topP: 0.8,
          maxOutputTokens: 1000,
        },
      }),
    });
    const data = await response.json();
    return { ok: response.ok, status: response.status, data };
  } finally {
    clearTimeout(timeout);
  }
}

module.exports = async (req, res) => {
  const cors = setCors(req, res);

  if (!cors.originAllowed) {
    return res.status(403).json({ error: "origin_not_allowed" });
  }

  if (req.method === "OPTIONS") return res.status(204).end();
  if (req.method !== "POST") {
    return res.status(405).json({ error: "method_not_allowed" });
  }

  const auth = verifyClientAuth(req);
  if (!auth.ok) {
    return res.status(auth.status).json({ error: auth.error });
  }

  const rateKey = getRateKey(req);
  if (isRateLimited(rateKey)) {
    return res.status(429).json({ error: "rate_limited" });
  }

  const quota = consumeQuota(req);
  res.setHeader("X-SCP-Quota-Day-Remaining", String(quota.dayRemaining ?? 0));
  res.setHeader(
    "X-SCP-Quota-Month-Remaining",
    String(quota.monthRemaining ?? 0),
  );
  if (!quota.ok) {
    return res.status(quota.status).json({
      error: quota.error,
      dayRemaining: quota.dayRemaining,
      monthRemaining: quota.monthRemaining,
      clientId: quota.clientId,
    });
  }

  const apiKey = process.env.GEMINI_API_KEY;
  if (!apiKey) return res.status(500).json({ error: "missing_api_key" });

  let body = req.body;
  if (typeof body === "string") {
    try {
      body = JSON.parse(body);
    } catch (_) {
      return res.status(400).json({ error: "invalid_json" });
    }
  }
  if (!body || typeof body !== "object") {
    return res.status(400).json({ error: "invalid_body" });
  }

  const question = sanitizeQuestion(
    safeString(body.question || body.prompt || body.message || ""),
  );
  if (!question) return res.status(400).json({ error: "missing_question" });

  const startedAt = nowMs();
  const deterministic = buildDeterministicAnswer(question, body);
  if (deterministic) {
    return res.status(200).json({
      answer: deterministic.answer,
      model: "deterministic-local",
      mode: deterministic.mode,
      latencyMs: nowMs() - startedAt,
    });
  }

  const prompt = buildPrompt(question, body);
  const tried = [];

  try {
    let lastError = "gemini_failed";
    let lastStatus = 502;

    for (const model of GEMINI_MODELS) {
      const { ok, status, data } = await callGemini({ model, prompt, apiKey });
      const answer = joinAnswerParts(data?.candidates?.[0]);
      tried.push({ model, status, ok: !!ok, hasAnswer: !!answer });

      if (!ok) {
        lastStatus = status || 502;
        lastError = data?.error?.message || "gemini_failed";
        continue;
      }
      if (!answer) {
        lastStatus = 502;
        lastError = "empty_answer";
        continue;
      }

      return res.status(200).json({
        answer,
        model,
        latencyMs: nowMs() - startedAt,
      });
    }

    return res.status(502).json({
      error: "gemini_error",
      status: lastStatus,
      details: lastError,
      tried,
    });
  } catch (error) {
    return res.status(502).json({
      error: "proxy_failed",
      details: String(error),
      tried,
    });
  }
};
