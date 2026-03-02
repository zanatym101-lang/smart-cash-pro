const { onRequest } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");

const GEMINI_API_KEY = defineSecret("GEMINI_API_KEY");

exports.assistantAsk = onRequest(
  {
    cors: true,
    secrets: [GEMINI_API_KEY],
  },
  async (req, res) => {
    if (req.method !== "POST") {
      return res.status(405).json({ error: "Method not allowed" });
    }

    const body = req.body || {};
    const question = (body.question || "").toString().trim();
    if (!question) {
      return res.status(400).json({ error: "Missing question" });
    }

    const context = {
      snapshot: body.snapshot || {},
      claims: body.claims || {},
      recentTxns: Array.isArray(body.recentTxns) ? body.recentTxns : [],
    };

    const prompt =
      "أنت مساعد ذكي لتطبيق Smart Cash Pro لإدارة المحافظ والخزنة." +
      " أجب بالعربية باختصار وبدقة، واعتبر أن البيانات المقدمة هي المصدر الوحيد." +
      " إذا لم تكن الإجابة ممكنة من البيانات، قل ذلك بوضوح.";

    const userText =
      `السؤال: ${question}\n\n` +
      `بيانات النظام (JSON مختصر): ${JSON.stringify(context)}`;

    const apiKey = GEMINI_API_KEY.value();
    const url =
      "https://generativelanguage.googleapis.com/v1beta/models/" +
      "gemini-1.5-flash:generateContent?key=" +
      apiKey;

    const payload = {
      contents: [{ role: "user", parts: [{ text: `${prompt}\n\n${userText}` }] }],
      generationConfig: { temperature: 0.2 },
    };

    try {
      const resp = await fetch(url, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload),
      });

      if (!resp.ok) {
        const txt = await resp.text();
        return res.status(500).json({ error: "AI error", details: txt });
      }

      const data = await resp.json();
      const answer =
        data?.candidates?.[0]?.content?.parts
          ?.map((p) => p.text || "")
          .join("")
          .trim() || "";

      if (!answer) {
        return res.status(500).json({ error: "Empty answer" });
      }

      return res.json({ answer });
    } catch (e) {
      return res.status(500).json({ error: "Server error", details: `${e}` });
    }
  }
);
