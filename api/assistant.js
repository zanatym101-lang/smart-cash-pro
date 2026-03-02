const GEMINI_URL =
  "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent";

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
    const geminiRes = await fetch(`${GEMINI_URL}?key=${apiKey}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contents: [{ role: "user", parts: [{ text: prompt }] }],
        generationConfig: { temperature: 0.2, maxOutputTokens: 512 },
      }),
    });

    const data = await geminiRes.json();
    if (!geminiRes.ok) {
      return res.status(502).json({
        error: "gemini_error",
        status: geminiRes.status,
        details: data?.error?.message || "unknown",
      });
    }

    const answer =
      data?.candidates?.[0]?.content?.parts?.[0]?.text?.trim() || "";
    if (!answer) {
      return res.status(502).json({ error: "no_answer" });
    }

    return res.status(200).json({ answer });
  } catch (e) {
    return res.status(502).json({ error: "proxy_failed", details: `${e}` });
  }
};
