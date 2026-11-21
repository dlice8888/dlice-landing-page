import { checkPwnedPassword } from "./password-security.ts";

const hex = (bytes: Uint8Array) =>
  Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join("").toUpperCase();

Deno.test("uses only the five-character SHA-1 prefix and blocks a breached password", async () => {
  const password = "password";
  const digest = await crypto.subtle.digest("SHA-1", new TextEncoder().encode(password));
  const hash = hex(new Uint8Array(digest));
  const prefix = hash.slice(0, 5);
  const suffix = hash.slice(5);
  let requestedUrl = "";
  let paddingHeader = "";
  const result = await checkPwnedPassword(password, async (input, init) => {
    requestedUrl = String(input);
    paddingHeader = new Headers(init?.headers).get("Add-Padding") || "";
    return new Response(`${suffix}:1000\n${"A".repeat(35)}:0\n`, { status: 200 });
  });
  if (result !== "compromised") throw new Error("Expected a known breached password to be blocked");
  if (requestedUrl !== `https://api.pwnedpasswords.com/range/${prefix}`) {
    throw new Error("Only the first five SHA-1 characters may be sent to the API");
  }
  if (requestedUrl.endsWith(suffix) || requestedUrl.endsWith(hash)) {
    throw new Error("The full hash suffix or full digest must never leave the runtime");
  }
  if (paddingHeader !== "true") throw new Error("The Add-Padding header must be enabled");
});

Deno.test("accepts a password absent from the range response", async () => {
  const result = await checkPwnedPassword("a-unique-test-password-2026", async () =>
    new Response(`${"0".repeat(35)}:0\n`, { status: 200 })
  );
  if (result !== "clear") throw new Error(`Expected clear result, got ${result}`);
});

Deno.test("fails closed when the free breach-check service is unavailable", async () => {
  const failed = await checkPwnedPassword("another-test-password", async () => {
    throw new Error("network unavailable");
  });
  const httpError = await checkPwnedPassword("another-test-password", async () =>
    new Response("unavailable", { status: 503 })
  );
  if (failed !== "unavailable" || httpError !== "unavailable") {
    throw new Error("Network/API failure must fail closed");
  }
});
