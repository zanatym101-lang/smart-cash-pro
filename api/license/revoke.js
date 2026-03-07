const {
  setLicenseCors,
  readJsonBody,
  safeString,
  nowIso,
  findLicenseByCode,
  findLicenseById,
  supabaseRequest,
  logEvent,
  json,
} = require("../_lib/license_common");

function adminKeyFromReq(req) {
  return safeString(req.headers["x-license-admin-key"]);
}

function adminKeyExpected() {
  return safeString(process.env.LICENSE_ADMIN_KEY);
}

module.exports = async (req, res) => {
  setLicenseCors(req, res);
  if (req.method === "OPTIONS") return res.status(204).end();
  if (req.method !== "POST") return json(res, 405, { error: "method_not_allowed" });

  const expected = adminKeyExpected();
  const provided = adminKeyFromReq(req);
  if (!expected) return json(res, 500, { error: "missing_license_admin_key" });
  if (provided !== expected) return json(res, 401, { error: "unauthorized_admin_key" });

  const body = readJsonBody(req);
  if (!body) return json(res, 400, { error: "invalid_json" });

  const licenseCode = safeString(body.licenseCode).toUpperCase();
  const licenseIdInput = safeString(body.licenseId);
  const deviceId = safeString(body.deviceId);
  const revokeAll = !!body.revokeAll;

  if (!licenseCode && !licenseIdInput) {
    return json(res, 400, { error: "license_code_or_id_required" });
  }

  try {
    let license = null;
    if (licenseCode) {
      license = await findLicenseByCode(licenseCode);
    } else {
      license = await findLicenseById(licenseIdInput);
    }
    if (!license) return json(res, 404, { error: "license_not_found" });

    const now = nowIso();

    if (revokeAll || !deviceId) {
      await supabaseRequest({
        method: "PATCH",
        table: "licenses",
        prefer: "return=minimal",
        query: { id: `eq.${license.id}` },
        body: { status: "revoked" },
      });

      await supabaseRequest({
        method: "PATCH",
        table: "license_activations",
        prefer: "return=minimal",
        query: {
          license_id: `eq.${license.id}`,
          revoked_at: "is.null",
        },
        body: { revoked_at: now, last_seen_at: now },
      });

      await logEvent({
        licenseId: license.id,
        deviceId: null,
        eventType: "revoke_all",
        payload: {},
      });

      return json(res, 200, { ok: true, mode: "revoke_all", licenseId: license.id });
    }

    const updated = await supabaseRequest({
      method: "PATCH",
      table: "license_activations",
      prefer: "return=representation",
      query: {
        license_id: `eq.${license.id}`,
        device_id: `eq.${deviceId}`,
        revoked_at: "is.null",
      },
      body: { revoked_at: now, last_seen_at: now },
    });

    const count = Array.isArray(updated) ? updated.length : 0;
    if (count === 0) {
      return json(res, 404, { error: "active_device_not_found" });
    }

    await logEvent({
      licenseId: license.id,
      deviceId,
      eventType: "revoke_device",
      payload: {},
    });

    return json(res, 200, {
      ok: true,
      mode: "revoke_device",
      licenseId: license.id,
      deviceId,
    });
  } catch (error) {
    return json(res, error.status || 500, {
      error: "revoke_failed",
      details: error.details || String(error),
    });
  }
};

