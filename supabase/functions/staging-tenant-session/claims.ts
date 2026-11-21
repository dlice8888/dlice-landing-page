export type GitHubWorkflowClaims = Record<string, unknown>;

export type StagingWorkflowTrustConfig = {
  repositoryId: string;
  ownerId: string;
};

export function isTrustedStagingWorkflowClaims(
  claims: GitHubWorkflowClaims,
  config: StagingWorkflowTrustConfig,
): boolean {
  const exact = (claim: string, expected: string) => claims[claim] === expected;
  const runId = String(claims.run_id ?? "");
  const runAttempt = String(claims.run_attempt ?? "");
  const jti = claims.jti;

  return Boolean(config.repositoryId && config.ownerId) &&
    exact("repository", "dlice8888/dlice-landing-page") &&
    exact("sub", "repo:dlice8888/dlice-landing-page:environment:staging") &&
    exact("repository_id", config.repositoryId) &&
    exact("repository_owner_id", config.ownerId) &&
    exact("ref", "refs/heads/staging") &&
    exact(
      "workflow_ref",
      "dlice8888/dlice-landing-page/.github/workflows/staging-tenant-isolation-acceptance.yml@refs/heads/staging",
    ) &&
    exact("environment", "staging") &&
    exact("event_name", "workflow_dispatch") &&
    /^[1-9]\d*$/.test(runId) &&
    /^[1-9]\d*$/.test(runAttempt) &&
    typeof jti === "string" &&
    jti.length >= 8 &&
    jti.length <= 256;
}
