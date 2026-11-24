  assert.match(edge, /audit_events/);
  assert.match(edge, /branchAccess\(branchId\)/);
});

test("manual staging E2E covers the required POS to report vertical slice", () => {
  for (const action of ["erp-create-pos-sale","erp-sync-offline-operation","erp-list-kitchen-tickets","erp-transition-kitchen-ticket","erp-list-sales","erp-reconcile-pos-sale"]) {
    assert.match(kdsE2E, new RegExp(action));
  }
  assert.match(kdsE2E, /idempotent_replay/);
  assert.match(kdsE2E, /50, "Recipe must consume 50g flour/);
  assert.match(kdsE2E, /10, "Recipe must consume 10g second ingredient/);
  assert.match(kdsE2E, /finally/);
  for (const unrelatedAction of ["erp-record-waste","erp-create-shift-handover","erp-acknowledge-shift-handover","erp-start-branch-checklist","erp-update-branch-checklist-item","erp-complete-branch-checklist"]) {
    assert.doesNotMatch(kdsE2E, new RegExp(unrelatedAction));
  }
  assert.match(kdsWorkflow, /workflow_dispatch:/);
  const triggerHeader = kdsWorkflow.split(/^permissions:\s*$/m, 1)[0];
  assert.match(triggerHeader, /push:\s*\n\s+branches:\s*\n\s+- feat\/pos-checkout-lifecycle-20261124/);
  assert.doesNotMatch(triggerHeader, /^\s+schedule:/m, "POS staging E2E must not run on an unattended schedule");
  assert.match(kdsWorkflow, /github\.ref\s*==\s*'refs\/heads\/feat\/pos-checkout-lifecycle-20261124'/);
  assert.match(kdsWorkflow, /github\.event_name\s*==\s*'push'/);
  assert.match(kdsWorkflow, /github\.event\.head_commit\.message, '\[staging-e2e\]'/);
  assert.match(kdsWorkflow, /github\.ref\s*==\s*'refs\/heads\/staging'/);
  assert.match(kdsWorkflow, /github\.event_name\s*==\s*'workflow_dispatch'/);
  assert.match(kdsWorkflow, /confirm_staging_mutations:/);
  assert.match(kdsWorkflow, /inputs\.confirm_staging_mutations\s*==\s*true/);
  assert.match(kdsWorkflow, /STAGING_SUPABASE_SERVICE_ROLE_KEY/);
  assert.doesNotMatch(kdsWorkflow, /STAGING_TEST_OWNER_(?:USERNAME|PASSWORD)/);
  assert.match(kdsE2E, /findActiveOwnerUserId/);
  assert.match(kdsE2E, /tokenForExistingUser/);
  assert.match(kdsE2E, /STAGING_SUPABASE_SERVICE_ROLE_KEY/);
  assert.doesNotMatch(kdsE2E, /STAGING_TEST_OWNER_(?:USERNAME|PASSWORD)/);
  assert.doesNotMatch(kdsE2E, /STAGING_TEST_BRANCH_A_(?:USERNAME|PASSWORD)/);
  assert.doesNotMatch(kdsE2E, /erp-create-tenant/);
  assert.doesNotMatch(kdsE2E, /erp-invite-tenant-member/);
  assert.doesNotMatch(kdsWorkflow, /STAGING_TEST_BRANCH_A_(?:USERNAME|PASSWORD)/);