import { isTrustedStagingWorkflowClaims } from "./claims.ts";

const config = { repositoryId: "12345678", ownerId: "87654321" };
const validClaims = {
  repository: "dlice8888/dlice-landing-page",
  sub: "repo:dlice8888/dlice-landing-page:environment:staging",
  repository_id: "12345678",
  repository_owner_id: "87654321",
  ref: "refs/heads/staging",
  workflow_ref: "dlice8888/dlice-landing-page/.github/workflows/staging-tenant-isolation-acceptance.yml@refs/heads/staging",
  environment: "staging",
  event_name: "workflow_dispatch",
  run_id: "44740000001",
  run_attempt: "1",
  jti: "github-oidc-jti-123456789",
};

Deno.test("accepts only the exact trusted staging workflow identity", () => {
  if (!isTrustedStagingWorkflowClaims(validClaims, config)) {
    throw new Error("valid staging workflow claims were rejected");
  }
});

Deno.test("rejects repository, owner, ref, workflow, environment and event substitutions", () => {
  const mutations: Array<[string, Partial<typeof validClaims>]> = [
    ["repository", { repository: "attacker/repository" }],
    ["repository id", { repository_id: "99999999" }],
    ["owner id", { repository_owner_id: "99999999" }],
    ["ref", { ref: "refs/heads/main" }],
    ["workflow", { workflow_ref: "dlice8888/dlice-landing-page/.github/workflows/other.yml@refs/heads/staging" }],
    ["environment", { environment: "production" }],
    ["event", { event_name: "push" }],
  ];
  for (const [label, patch] of mutations) {
    if (isTrustedStagingWorkflowClaims({ ...validClaims, ...patch }, config)) {
      throw new Error(`untrusted ${label} claim was accepted`);
    }
  }
});

Deno.test("rejects missing protected repository configuration and malformed replay claims", () => {
  if (isTrustedStagingWorkflowClaims(validClaims, { repositoryId: "", ownerId: config.ownerId })) {
    throw new Error("missing repository id configuration was accepted");
  }
  const mutations: Array<[string, Partial<typeof validClaims>]> = [
    ["run id", { run_id: "0" }],
    ["run attempt", { run_attempt: "not-a-number" }],
    ["jti", { jti: "short" }],
    ["jti length", { jti: "x".repeat(257) }],
  ];
  for (const [label, patch] of mutations) {
    if (isTrustedStagingWorkflowClaims({ ...validClaims, ...patch }, config)) {
      throw new Error(`malformed ${label} was accepted`);
    }
  }
});
