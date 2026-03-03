const GEMINI_API_BASE =
  "https://generativelanguage.googleapis.com/v1/models";
const GEMINI_MODELS = [
  // Prefer latest fast models first (from your available list)
  "gemini-2.5-flash",
  "gemini-2.5-pro",
  "gemini-2.0-flash",
  "gemini-2.0-flash-001",
  "gemini-2.0-flash-lite-001",
  "gemini-1.5-flash",
  "gemini-1.5-flash-latest",
  "gemini-1.5-pro",
  "gemini-1.5-pro-latest",
  "gemini-1.0-pro",
  "gemini-pro",
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

  const prompt = `${blocks.join("\n\n")}\n\nQUESTION:\n${question}`.trim();

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
