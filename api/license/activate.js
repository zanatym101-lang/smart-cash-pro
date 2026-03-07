const {
  issueLicenseToken,
  setLicenseCors,
  readJsonBody,
  safeString,
  nowIso,
  licenseTokenConfig,
  findLicenseByCode,
  listActiveActivations,
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

  const code = safeString(body.code).toUpperCase();
  const deviceId = safeString(body.deviceId);
  const appVersion = safeString(body.appVersion);

  if (!code || !deviceId) {
    return json(res, 400, { error: "code_and_device_required" });
  }

  const tokenCfg = licenseTokenConfig();
  if (!tokenCfg.secret) {
    return json(res, 500, { error: "missing_license_token_secret" });
  }

  try {
    const license = await findLicenseByCode(code);
    if (!license) {
      return json(res, 404, { error: "license_not_found" });
    }
    if (license.status !== "active") {
      return json(res, 403, { error: "license_not_active", status: license.status });
    }
    if (isExpired(license.expires_at)) {
      return json(res, 403, { error: "license_expired" });
    }

    const now = nowIso();
    let activation = await findActivation(license.id, deviceId);
    if (activation && activation.revoked_at) {
      return json(res, 403, { error: "device_revoked" });
    }

    if (!activation) {
      const activeDevices = await listActiveActivations(license.id);
      const maxDevices = Number(license.max_devices || 1);
      if (activeDevices.length >= maxDevices) {
        return json(res, 403, {
          error: "device_limit_exceeded",
          maxDevices,
          activeDevices: activeDevices.length,
        });
      }

      const inserted = await supabaseRequest({
        method: "POST",
        table: "license_activations",
        prefer: "return=representation",
        body: {
          license_id: license.id,
          device_id: deviceId,
          app_version: appVersion || null,
          activated_at: now,
          last_seen_at: now,
        },
      });
      activation = Array.isArray(inserted) ? inserted[0] : null;
    } else {
      const updated = await supabaseRequest({
        method: "PATCH",
        table: "license_activations",
        prefer: "return=representation",
        query: { id: `eq.${activation.id}` },
        body: {
          app_version: appVersion || activation.app_version || null,
          last_seen_at: now,
        },
      });
      activation = Array.isArray(updated) && updated.length ? updated[0] : activation;
    }

    const token = issueLicenseToken(
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
      eventType: "activate",
      payload: { appVersion },
    });

    return json(res, 200, {
      ok: true,
      token,
      expiresAt: license.expires_at || null,
      activation: {
        id: activation?.id || null,
        deviceId,
        appVersion: activation?.app_version || appVersion || null,
        lastSeenAt: activation?.last_seen_at || now,
      },
    });
  } catch (error) {
    return json(res, error.status || 500, {
      error: "activate_failed",
      details: error.details || String(error),
    });
  }
};

