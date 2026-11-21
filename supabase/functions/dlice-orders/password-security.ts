export type PwnedPasswordCheck = "compromised" | "clear" | "unavailable";

type RangeFetcher = (input: RequestInfo | URL, init?: RequestInit) => Promise<Response>;

/**
 * Uses the Pwned Passwords range API's k-anonymity model:
 * only the first five hex characters of the SHA-1 digest leave this runtime.
 * The password and full digest are never sent.
 */
export async function checkPwnedPassword(
  password: string,
  fetcher: RangeFetcher = fetch,
): Promise<PwnedPasswordCheck> {
  if (!password) return "unavailable";
  try {
    const digest = await crypto.subtle.digest("SHA-1", new TextEncoder().encode(password));
    const hash = Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("").toUpperCase();
    const prefix = hash.slice(0, 5);
    const suffix = hash.slice(5);
    const response = await fetcher(`https://api.pwnedpasswords.com/range/${prefix}`, {
      headers: { "Add-Padding": "true" },
      signal: AbortSignal.timeout(3000),
    });
    if (!response.ok) return "unavailable";
    const matches = (await response.text()).split(/\r?\n/);
    const compromised = matches.some((line) => {
      const [candidate, countRaw] = line.trim().split(":");
      return candidate?.toUpperCase() === suffix && Number(countRaw) > 0;
    });
    return compromised ? "compromised" : "clear";
  } catch {
    return "unavailable";
  }
}
