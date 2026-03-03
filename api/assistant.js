const GEMINI_API_BASE =
  "https://generativelanguage.googleapis.com/v1beta/models";
const GEMINI_MODELS = [
  // Known available model for this account
  "gemini-2.5-flash",
];

function setCors(res) {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Methods", "POST, OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type, Authorization");
}

function toTextBlock(title, value) {
  if (value == null) return "";
  const text =
    typeof value === "string" ? value.trim() : JSON.stringify(value);
  if (!text) return "";
  return `${title}:\n${text}`;
}

module.exports = async (req, res) => {
  setCors(res);
  if (req.method === "OPTIONS") {
    return res.status(200).end();
  }
  if (req.method !== "POST") {
    return res.status(405).json({ error: "method_not_allowed" });
  }

  const apiKey = process.env.GEMINI_API_KEY;
  if (!apiKey) {
    return res.status(500).json({ error: "missing_api_key" });
  }

  let body = req.body;
  if (typeof body === "string") {
    try {
      body = JSON.parse(body);
    } catch (_) {
      return res.status(400).json({ error: "invalid_json" });
    }
  }

  const question =
    (body?.question || body?.prompt || body?.message || "").toString().trim();
  if (!question) {
    return res.status(400).json({ error: "missing_question" });
  }

  const blocks = [
    toTextBlock("SNAPSHOT", body?.snapshot),
    toTextBlock("CLAIMS", body?.claims),
    toTextBlock("RECENT_TXNS", body?.recentTxns),
  ].filter(Boolean);

  const system = [
    "أنت مساعد مالي لتطبيق Smart Cash Pro.",
    "أجب بالعربية فقط وبأسلوب احترافي.",
    "التزم بالبيانات المرفقة فقط ولا تستخدم أي معرفة خارجية.",
    "إذا كانت البيانات غير كافية أو غير موجودة، اكتب: لا تتوفر بيانات كافية للإجابة.",
    "اجعل الرد على قدر السؤال:",
    "• إذا كان السؤال مباشرًا ويطلب رقمًا واحدًا: أجب في سطرين فقط (النتيجة + تفسير مختصر).",
    "• إذا كان السؤال تحليليًا أو متعدد الجوانب: استخدم الأقسام التالية عند الحاجة فقط:",
    "  ملخص → الأرقام → التحليل → ملاحظات.",
    "لا تكرر نفس الرقم في أكثر من قسم إلا إذا كان ذلك ضروريًا للفهم.",
  ].join("\n");

  const prompt = `${system}\n\n${blocks.join("\n\n")}\n\nQUESTION:\n${question}`.trim();

  try {
    let lastError = "unknown";
    for (const model of GEMINI_MODELS) {
      const url = `${GEMINI_API_BASE}/${model}:generateContent?key=${apiKey}`;
      const geminiRes = await fetch(url, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          contents: [{ role: "user", parts: [{ text: prompt }] }],
          generationConfig: { temperature: 0.2, maxOutputTokens: 512 },
        }),
      });

      const data = await geminiRes.json();
      if (!geminiRes.ok) {
        lastError = data?.error?.message || "unknown";
        continue;
      }

      const answer =
        data?.candidates?.[0]?.content?.parts?.[0]?.text?.trim() || "";
      if (!answer) {
        lastError = "no_answer";
        continue;
      }

      return res.status(200).json({ answer, model });
    }

    return res.status(502).json({
      error: "gemini_error",
      status: 404,
      details: lastError,
    });
  } catch (e) {
    return res.status(502).json({ error: "proxy_failed", details: `${e}` });
  }
};
