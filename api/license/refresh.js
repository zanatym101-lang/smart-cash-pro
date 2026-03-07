const {
  issueLicenseToken,
  verifyLicenseToken,
  setLicenseCors,
  readJsonBody,
  safeString,
  nowIso,
  tokenFromRequest,
  licenseTokenConfig,
  findLicenseById,
  findActivation,
  supabaseRequest,
  logEvent,
  json,
} = require("../_lib/license_common");

function isExpired(expiresAt) {
  if (!expiresAt) return false;
  const t = Date.parse(expiresAt);
  return Number.isFinite(t) && t < Date.now();
}

module.exports = async (req, res) => {
  setLicenseCors(req, res);
  if (req.method === "OPTIONS") return res.status(204).end();
  if (req.method !== "POST") return json(res, 405, { error: "method_not_allowed" });

  const body = readJsonBody(req);
  if (!body) return json(res, 400, { error: "invalid_json" });

  const tokenCfg = licenseTokenConfig();
  if (!tokenCfg.secret) {
    return json(res, 500, { error: "missing_license_token_secret" });
  }

  const token = tokenFromRequest(req, body);
  if (!token) return json(res, 400, { error: "missing_token" });

  const verified = verifyLicenseToken(token, tokenCfg.secret);
  if (!verified.ok) return json(res, 401, { error: verified.error });

  const payload = verified.payload;
  const deviceId = safeString(body.deviceId || payload.deviceId);
  const appVersion = safeString(body.appVersion);

  try {
    const license = await findLicenseById(payload.licenseId);
    if (!license) return json(res, 404, { error: "license_not_found" });
    if (license.status !== "active") {
      return json(res, 403, { error: "license_not_active", status: license.status });
    }
    if (isExpired(license.expires_at)) {
      return json(res, 403, { error: "license_expired" });
    }

    const activation = await findActivation(license.id, deviceId);
    if (!activation || activation.revoked_at) {
      return json(res, 403, { error: "activation_not_found_or_revoked" });
    }

    const now = nowIso();
    await supabaseRequest({
      method: "PATCH",
      table: "license_activations",
      prefer: "return=minimal",
      query: { id: `eq.${activation.id}` },
      body: {
        last_seen_at: now,
        app_version: appVersion || activation.app_version || null,
      },
    });

    const newToken = issueLicenseToken(
      {
        typ: "license",
        licenseId: license.id,
        code: license.code,
        deviceId,
      },
      tokenCfg.secret,
      tokenCfg.ttlSeconds,
    );

    await logEvent({
      licenseId: license.id,
      deviceId,
      eventType: "refresh",
      payload: { appVersion },
    });

    return json(res, 200, {
      ok: true,
      token: newToken,
      expiresAt: license.expires_at || null,
    });
  } catch (error) {
    return json(res, error.status || 500, {
      error: "refresh_failed",
      details: error.details || String(error),
    });
  }
};

