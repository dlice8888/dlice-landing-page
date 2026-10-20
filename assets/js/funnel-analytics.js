/* D'Lice privacy-preserving funnel analytics.
 * Sends only a fixed event name to the project's own Edge Function.
 * No cookies, local storage, user IDs, order IDs, phone numbers, addresses, or third-party analytics.
 */
(() => {
  const host = location.hostname;
  const productionHosts = new Set(["dlice.vercel.app", "dlice-landing-page.vercel.app"]);
  const project = productionHosts.has(host)
    ? "https://gdjlkrmlsurcdbwnmqgg.supabase.co"
    : "https://higoadrzxnhzbbwhdbmh.supabase.co";
  const endpoint = project + "/functions/v1/dlice-orders";
  const allowed = new Set(["page_view", "menu_view", "add_to_order", "checkout_start", "order_created", "proof_uploaded", "whatsapp_click"]);
  window.dliceTrack = (eventName) => {
    if (!allowed.has(eventName)) return;
    try {
      fetch(endpoint, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action: "record-funnel-event", event_name: eventName }),
        keepalive: true,
        credentials: "omit"
      }).catch(() => {});
    } catch (_) { /* Analytics must never interrupt checkout. */ }
  };
  const start = () => {
    window.dliceTrack("page_view");
    const menu = document.getElementById("menu");
    if (menu && "IntersectionObserver" in window) {
      const observer = new IntersectionObserver((entries) => {
        if (entries.some((entry) => entry.isIntersecting)) {
          window.dliceTrack("menu_view");
          observer.disconnect();
        }
      }, { threshold: 0.15 });
      observer.observe(menu);
    }
    document.addEventListener("click", (event) => {
      if (event.target.closest("#menu .add")) window.dliceTrack("add_to_order");
      if (event.target.closest("#finalWhatsAppBtn, a[href^='https://wa.me/']")) window.dliceTrack("whatsapp_click");
    }, { passive: true });
    const form = document.getElementById("orderForm");
    if (form) form.addEventListener("submit", () => window.dliceTrack("checkout_start"), { passive: true });
    const proof = document.getElementById("uploadProofBtn");
    if (proof) proof.addEventListener("click", () => {
      // This event records an upload attempt only when the existing upload flow is invoked.
      // Successful uploads also call dliceTrack from the checkout success handler.
    }, { passive: true });
  };
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", start, { once: true });
  else start();
})();
