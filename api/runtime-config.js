// Vercel serverless endpoint: expose only public Supabase client configuration.
module.exports = function runtimeConfig(req, res) {
  if (req.method !== "GET") {
    res.setHeader("Allow", "GET");
    return res.status(405).json({ error: "Method not allowed" });
  }

  const environment = process.env.VERCEL_ENV || (process.env.NODE_ENV === "development" ? "development" : "unknown");
  const supabaseUrl = process.env.SUPABASE_URL;
  const publishableKey = process.env.SUPABASE_PUBLISHABLE_KEY;

  if (!supabaseUrl || !publishableKey) {
    return res.status(503).json({ error: "Supabase public runtime configuration is missing." });
  }

  let parsedUrl;
  try {
    parsedUrl = new URL(supabaseUrl);
  } catch {
    return res.status(503).json({ error: "Supabase URL configuration is invalid." });
  }

  const projectRef = parsedUrl.hostname.endsWith(".supabase.co")
    ? parsedUrl.hostname.slice(0, -".supabase.co".length)
    : "";
  const expectedProject = {
    preview: "higoadrzxnhzbbwhdbmh",
    production: "gdjlkrmlsurcdbwnmqgg",
  }[environment];

  if (parsedUrl.protocol !== "https:" || parsedUrl.pathname !== "/" || parsedUrl.search || parsedUrl.hash ||
      !projectRef || (expectedProject && projectRef !== expectedProject) ||
      (environment !== "preview" && environment !== "production" && environment !== "development")) {
    return res.status(503).json({ error: "Supabase project does not match this deployment environment." });
  }

  // Browser clients may receive publishable keys only. Secret/service-role keys are rejected.
  if (!publishableKey.startsWith("sb_publishable_") || /service_role|sb_secret_/i.test(publishableKey)) {
    return res.status(503).json({ error: "A Supabase publishable key is required for browser access." });
  }

  res.setHeader("Cache-Control", "no-store, max-age=0");
  res.setHeader("Vary", "Host");
  return res.status(200).json({
    environment,
    supabaseUrl: parsedUrl.origin,
    publishableKey,
  });
};
