# Staging Owner authorization audit

**Date:** 2026-11-17  
**Target:** Supabase staging `higoadrzxnhzbbwhdbmh`  
**Method:** Read-only SQL aggregate checks; no Auth metadata or secrets changed.

## Findings

| Check | Result | Status |
|---|---:|---|
| Active Owner profiles | 1 | PASS (profile exists) |
| Active Owner profile linked to non-deleted Auth user | 1 | PASS (identity link exists) |
| Linked Auth user has JSON boolean `app_metadata.platform_owner=true` | 0 | FAIL |
| Linked Auth user has string `app_metadata.platform_owner="true"` | 0 | PASS (no unsafe string grant found) |
| UUID allowlist membership | Not readable/verified | UNKNOWN |
| Owner login/runtime authorization | Not executed | NOT RUN |
| Non-Owner denial | Not executed | NOT RUN |
| Command Center Owner drill-down | Not executed | NOT RUN |

The query confirmed the linked Auth identity lacks the required platform-owner metadata. This report intentionally does not disclose the linked user UUID.

## Security interpretation

An active `admin_profiles.role='owner'` row is not sufficient to establish platform Owner authorization. The runtime requires the server-controlled Auth `raw_app_meta_data.platform_owner` boolean and the server-side UUID allowlist to agree. The allowlist's effective runtime value was not available through the connected tools.

## Required administrator action

1. Confirm the legitimate Owner identity using the approved account ownership process.
2. Through Supabase Auth Admin on staging only, preserve all existing app metadata and set `platform_owner` to JSON boolean `true` only for that verified identity.
3. Update the server-side `DLICE_PLATFORM_OWNER_USER_IDS` allowlist through its approved secret-management path.
4. Refresh/re-authenticate the account so JWT claims are current.
5. Run Owner and non-Owner runtime authorization tests, including server-side Command Center access and hierarchy drill-down.

Do not create a replacement Owner, elevate the wrong account, or alter metadata/allowlist to make tests pass. Production was not accessed for mutation.
