import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const edge=readFileSync(new URL("../../supabase/functions/dlice-orders/index.ts",import.meta.url),"utf8");
const erp=readFileSync(new URL("../../erp.html",import.meta.url),"utf8");

test("employee lifecycle RPCs are registered behind the existing Platform Owner HR gate",()=>{
 assert.match(edge,/"erp-hr-create-employee-record"/);
 assert.match(edge,/"erp-hr-apply-employee-lifecycle-event"/);
 assert.match(edge,/if \(hrActions\.has\(action\)\)/);
 assert.match(edge,/if \(!isPlatformOwner\) return fail\("Modul HR sementara dibatasi/);
 assert.match(edge,/hr_create_employee_record/);
 assert.match(edge,/hr_apply_employee_lifecycle_event/);
});

test("HR UI exposes employee record creation and the full lifecycle transition set",()=>{
 assert.match(erp,/id="hrEmployeeRecordForm"/);
 assert.match(erp,/id="hrLifecycleForm"/);
 for(const event of ["transfer","position_change","leave_started","leave_ended","offboarding_requested","terminated","reactivated"])
   assert.match(erp,new RegExp('value="'+event+'"'));
 assert.match(erp,/erp-hr-create-employee-record/);
 assert.match(erp,/erp-hr-apply-employee-lifecycle-event/);
});

test("employee lifecycle UI does not expose global Auth deactivation",()=>{
 assert.match(erp,/Terminasi mencabut membership tenant dan assignment, bukan menonaktifkan Auth global/);
});
