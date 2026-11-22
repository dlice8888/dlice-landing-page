// Supabase API-key compatibility for the staging-only passwordless harness.
// New secret keys are opaque and must be sent only as apikey; legacy service_role
// JWTs may be sent as both apikey and Bearer credentials.
function decodeJwtPayload(value) {
  try {
    const parts = value.split(".");
    if (parts.length !== 3) return null;
    return JSON.parse(Buffer.from(parts[1], "base64url").toString("utf8"));
  } catch {
    return null;
  }
}

export function isServiceRoleKey(value) {
  if (typeof value !== "string") return false;
  if (/^sb_secret_[A-Za-z0-9_-]{20,}$/.test(value)) return true;
  return decodeJwtPayload(value)?.role === "service_role";
}

export function serviceRoleHeaders(value) {
  if (!isServiceRoleKey(value)) throw new TypeError("Unsupported Supabase service-role key format");
  return value.startsWith("sb_secret_")
    ? { apikey: value }
    : { apikey: value, authorization: `Bearer ${value}` };
}
