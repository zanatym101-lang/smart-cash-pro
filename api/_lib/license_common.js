const crypto = require("crypto");

function json(res, status, body) {
  res.status(status).json(body);
}

function safeString(value) {
  return (value ?? "").toString().trim();
}

function b64urlEncode(input) {
  const buf = Buffer.isBuffer(input) ? input : Buffer.from(String(input), "utf8");
  return buf
    .toString("base64")
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/g, "");
}

function b64urlDecode(input) {
  const normalized = String(input)
    .replace(/-/g, "+")
    .replace(/_/g, "/");
  const pad = normalized.length % 4 === 0 ? 0 : 4 - (normalized.length % 4);
  return Buffer.from(normalized + "=".repeat(pad), "base64").toString("utf8");
}

function signText(secret, text) {
  return b64urlEncode(crypto.createHmac("sha256", secret).update(text).digest());
}

function issueLicenseToken(payload, secret, ttlSeconds) {
  const now = Math.floor(Date.now() / 1000);
  const exp = now + ttlSeconds;
  const body = { ...payload, iat: now, exp };
  const encoded = b64urlEncode(JSON.stringify(body));
  const sig = signText(secret, encoded);
  return `${encoded}.${sig}`;
}

function verifyLicenseToken(token, secret) {
  const raw = safeString(token);
  if (!raw.includes(".")) {
    return { ok: false, error: "invalid_token_format" };
  }
  const [encoded, sig] = raw.split(".", 2);
  const expected = signText(secret, encoded);
  if (!crypto.timingSafeEqual(Buffer.from(sig), Buffer.from(expected))) {
    return { ok: false, error: "invalid_token_signature" };
  }
  let payload;
  try {
    payload = JSON.parse(b64urlDecode(encoded));
  } catch (_) {
    return { ok: false, error: "invalid_token_payload" };
  }
  const now = Math.floor(Date.now() / 1000);
  if (!payload?.exp || Number(payload.exp) < now) {
    return { ok: false, error: "token_expired" };
  }
  return { ok: true, payload };
}

function getSupabaseConfig() {
  const url = safeString(process.env.SUPABASE_URL);
  const key = safeString(process.env.SUPABASE_SERVICE_ROLE_KEY);
  if (!url || !key) return null;
  return { url, key };
}

async function supabaseRequest({ method, table, query, body, prefer }) {
  const cfg = getSupabaseConfig();
  if (!cfg) {
    const err = new Error("missing_supabase_config");
    err.status = 500;
    throw err;
  }

  const url = new URL(`${cfg.url}/rest/v1/${table}`);
  if (query && typeof query === "object") {
    for (const [k, v] of Object.entries(query)) {
      if (v == null) continue;
      url.searchParams.set(k, String(v));
    }
  }

  const headers = {
    apikey: cfg.key,
    Authorization: `Bearer ${cfg.key}`,
  };
  if (prefer) headers.Prefer = prefer;
  if (body != null) headers["Content-Type"] = "application/json";

  const response = await fetch(url.toString(), {
    method,
    headers,
    body: body == null ? undefined : JSON.stringify(body),
  });

  const text = await response.text();
  let data = null;
  if (text) {
    try {
      data = JSON.parse(text);
    } catch (_) {
      data = text;
    }
  }

  if (!response.ok) {
    const err = new Error("supabase_request_failed");
    err.status = response.status;
    err.details = data;
    throw err;
  }

  return data;
}

function setLicenseCors(req, res) {
  const origin = safeString(req.headers.origin);
  if (origin) {
    res.setHeader("Access-Control-Allow-Origin", origin);
    res.setHeader("Vary", "Origin");
  }
  res.setHeader("Access-Control-Allow-Methods", "POST, OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type, Authorization, X-License-Admin-Key");
}

function readJsonBody(req) {
  if (!req.body) return {};
  if (typeof req.body === "string") {
    try {
      return JSON.parse(req.body);
    } catch (_) {
      return null;
    }
  }
  if (typeof req.body === "object") return req.body;
  return null;
}

function nowIso() {
  return new Date().toISOString();
}

function tokenFromRequest(req, body) {
  const auth = safeString(req.headers.authorization);
  if (auth.toLowerCase().startsWith("bearer ")) {
    return safeString(auth.slice(7));
  }
  return safeString(body?.token);
}

function licenseTokenConfig() {
  const secret = safeString(process.env.LICENSE_TOKEN_SECRET || process.env.ASSISTANT_CLIENT_TOKEN);
  const ttlHours = Number.parseInt(String(process.env.LICENSE_TOKEN_TTL_HOURS || "168"), 10);
  const ttlSeconds = Number.isFinite(ttlHours) && ttlHours > 0 ? ttlHours * 3600 : 168 * 3600;
  return { secret, ttlSeconds };
}

async function findLicenseByCode(code) {
  const rows = await supabaseRequest({
    method: "GET",
    table: "licenses",
    query: {
      select: "id,code,status,max_devices,expires_at,created_at",
      code: `eq.${code}`,
      limit: 1,
    },
  });
  return Array.isArray(rows) && rows.length ? rows[0] : null;
}

async function findLicenseById(id) {
  const rows = await supabaseRequest({
    method: "GET",
    table: "licenses",
    query: {
      select: "id,code,status,max_devices,expires_at,created_at",
      id: `eq.${id}`,
      limit: 1,
    },
  });
  return Array.isArray(rows) && rows.length ? rows[0] : null;
}

async function listActiveActivations(licenseId) {
  const rows = await supabaseRequest({
    method: "GET",
    table: "license_activations",
    query: {
      select: "id,license_id,device_id,app_version,activated_at,last_seen_at,revoked_at",
      license_id: `eq.${licenseId}`,
      revoked_at: "is.null",
      order: "activated_at.asc",
    },
  });
  return Array.isArray(rows) ? rows : [];
}

async function findActivation(licenseId, deviceId) {
  const rows = await supabaseRequest({
    method: "GET",
    table: "license_activations",
    query: {
      select: "id,license_id,device_id,app_version,activated_at,last_seen_at,revoked_at",
      license_id: `eq.${licenseId}`,
      device_id: `eq.${deviceId}`,
      limit: 1,
    },
  });
  return Array.isArray(rows) && rows.length ? rows[0] : null;
}

async function logEvent({ licenseId, deviceId, eventType, payload }) {
  try {
    await supabaseRequest({
      method: "POST",
      table: "license_events",
      prefer: "return=minimal",
      body: {
        license_id: licenseId || null,
        device_id: deviceId || null,
        event_type: eventType,
        payload: payload || {},
      },
    });
  } catch (_) {
    // Ignore logging failures to avoid breaking license flow.
  }
}

module.exports = {
  issueLicenseToken,
  verifyLicenseToken,
  getSupabaseConfig,
  supabaseRequest,
  setLicenseCors,
  readJsonBody,
  safeString,
  nowIso,
  tokenFromRequest,
  licenseTokenConfig,
  findLicenseByCode,
  findLicenseById,
  listActiveActivations,
  findActivation,
  logEvent,
  json,
};

