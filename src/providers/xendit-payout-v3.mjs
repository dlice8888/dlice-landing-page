import { createHash, timingSafeEqual } from "node:crypto";

const API_VERSION = "2025-09-01";
const PAYOUTS_URL = "https://api.xendit.co/v3/payouts";
const WEBHOOK_EVENTS = new Set([
  "v3_payout.succeeded",
  "v3_payout.failed",
  "v3_payout.reversed",
  "v3_payout.rejected",
  "v3_payout.pending_compliance",
]);
const EVENT_STATUS = Object.freeze({
  "v3_payout.succeeded": "SUCCEEDED",
  "v3_payout.failed": "FAILED",
  "v3_payout.reversed": "REVERSED",
  "v3_payout.rejected": "REJECTED",
  "v3_payout.pending_compliance": "PENDING_COMPLIANCE_ASSESSMENT",
});

function requiredString(value, name) {
  if (typeof value !== "string" || value.trim() === "") {
    throw Object.assign(new Error(`${name} is required`), { code: "XENDIT_PAYOUT_INPUT_INVALID" });
  }
  return value.trim();
}

function validatePayoutRequest(body) {
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    throw Object.assign(new Error("Payout request body must be an object"), { code: "XENDIT_PAYOUT_INPUT_INVALID" });
  }
  requiredString(body.reference_id, "reference_id");
  if (!body.recipient?.account_details || !body.payout_details) {
    throw Object.assign(new Error("Recipient account_details and payout_details are required"), { code: "XENDIT_PAYOUT_INPUT_INVALID" });
  }
  requiredString(body.recipient.account_details.account_number, "recipient.account_details.account_number");
  requiredString(body.recipient.account_details.account_holder_name, "recipient.account_details.account_holder_name");
  requiredString(body.recipient.account_details.routing_type_1, "recipient.account_details.routing_type_1");
  requiredString(body.recipient.account_details.routing_value_1, "recipient.account_details.routing_value_1");
  if (!Number.isSafeInteger(body.payout_details.source_amount) || body.payout_details.source_amount <= 0) {
    throw Object.assign(new Error("payout_details.source_amount must be a positive safe integer in currency minor units"), { code: "XENDIT_PAYOUT_INPUT_INVALID" });
  }
  if (body.payout_details.source_currency !== "IDR" || body.payout_details.destination_currency !== "IDR") {
    throw Object.assign(new Error("Payroll payout adapter currently supports IDR-to-IDR only"), { code: "XENDIT_PAYOUT_CURRENCY_UNSUPPORTED" });
  }
  requiredString(body.source_of_fund, "source_of_fund");
  requiredString(body.purpose_code, "purpose_code");
  return body;
}

function safeEqual(left, right) {
  const a = Buffer.from(left);
  const b = Buffer.from(right);
  return a.length === b.length && timingSafeEqual(a, b);
}

/**
 * Xendit Payout API v3 adapter.
 * Network dispatch is deliberately disabled unless explicitly enabled with a development key.
 * Never pass production credentials to this adapter.
 */
export function createXenditPayoutV3Adapter({
  secretApiKey,
  webhookToken,
  fetchImpl = globalThis.fetch,
  enableTestNetwork = false,
  endpoint = PAYOUTS_URL,
} = {}) {
  if (typeof fetchImpl !== "function") {
    throw Object.assign(new Error("fetch implementation is required"), { code: "XENDIT_FETCH_REQUIRED" });
  }

  async function executePayrollPaymentProvider({
    providerPayload,
    idempotencyKey,
  }) {
    if (enableTestNetwork !== true || !/^xnd_development_/.test(secretApiKey ?? "")) {
      throw Object.assign(new Error("Xendit payout dispatch is locked: explicit test-network enablement and a development API key are required"), {
        code: "XENDIT_PAYOUT_LIVE_LOCKED",
      });
    }
    requiredString(idempotencyKey, "idempotencyKey");
    if (idempotencyKey.length > 100) {
      throw Object.assign(new Error("Xendit idempotency key exceeds 100 characters"), { code: "XENDIT_PAYOUT_INPUT_INVALID" });
    }
    const body = validatePayoutRequest(providerPayload);
    const response = await fetchImpl(endpoint, {
      method: "POST",
      headers: {
        authorization: `Basic ${Buffer.from(`${secretApiKey}:`).toString("base64")}`,
        "content-type": "application/json",
        "api-version": API_VERSION,
        "idempotency-key": idempotencyKey,
      },
      body: JSON.stringify(body),
    });
    const responseBody = await response.json().catch(() => null);
    if (!response.ok) {
      const error = new Error("Xendit payout request was not accepted");
      error.code = "XENDIT_PAYOUT_PROVIDER_REJECTED";
      error.httpStatus = response.status;
      error.providerErrorCode = responseBody?.error_code ?? responseBody?.code ?? null;
      throw error;
    }
    if (!responseBody?.id || !responseBody?.reference_id || !responseBody?.status) {
      throw Object.assign(new Error("Xendit response lacks stable payout identity/status; outcome must be checked before retry"), {
        code: "XENDIT_PAYOUT_RESPONSE_UNVERIFIED",
      });
    }
    return Object.freeze({
      accepted: true,
      provider: "xendit",
      providerReference: responseBody.id,
      referenceId: responseBody.reference_id,
      providerStatus: responseBody.status,
      amountIdr: body.payout_details.source_amount,
      currency: "IDR",
      rawStatus: responseBody.status,
    });
  }

  function verifyPayrollPayoutWebhook({ rawBody, callbackToken }) {
    const expected = requiredString(webhookToken, "webhookToken");
    const received = requiredString(callbackToken, "x-callback-token");
    if (!safeEqual(received, expected)) {
      throw Object.assign(new Error("Xendit payout webhook token verification failed"), { code: "XENDIT_WEBHOOK_UNAUTHENTICATED" });
    }
    if (typeof rawBody !== "string" || rawBody.length === 0) {
      throw Object.assign(new Error("Raw webhook body is required"), { code: "XENDIT_WEBHOOK_INVALID" });
    }
    let payload;
    try {
      payload = JSON.parse(rawBody);
    } catch {
      throw Object.assign(new Error("Webhook body must be valid JSON"), { code: "XENDIT_WEBHOOK_INVALID" });
    }
    if (!WEBHOOK_EVENTS.has(payload?.event) || !payload?.business_id ||
        !payload?.created || !payload?.data?.payout_id ||
        !payload?.data?.reference_id || !payload?.data?.status) {
      throw Object.assign(new Error("Unsupported or incomplete Xendit payout webhook"), { code: "XENDIT_WEBHOOK_INVALID" });
    }
    const expectedStatus = EVENT_STATUS[payload.event];
    if (payload.data.status !== expectedStatus) {
      throw Object.assign(new Error("Webhook event and payout status do not match"), { code: "XENDIT_WEBHOOK_STATUS_MISMATCH" });
    }
    const eventFingerprint = createHash("sha256").update(rawBody).digest("hex");
    return Object.freeze({
      authenticated: true,
      provider: "xendit",
      event: payload.event,
      eventId: eventFingerprint,
      businessId: payload.business_id,
      providerReference: payload.data.payout_id,
      referenceId: payload.data.reference_id,
      providerStatus: payload.data.status,
      failureCode: payload.data.failure_code ?? null,
      occurredAt: payload.created,
      amountIdr: payload.data.source_currency === "IDR" ? payload.data.source_amount : null,
      currency: payload.data.source_currency ?? null,
      payload,
    });
  }

  return Object.freeze({
    providerId: "xendit",
    apiVersion: API_VERSION,
    executePayrollPaymentProvider,
    verifyPayrollPayoutWebhook,
  });
}

export const XENDIT_PAYOUT_V3_EVENTS = Object.freeze([...WEBHOOK_EVENTS]);
