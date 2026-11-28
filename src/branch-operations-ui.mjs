/**
 * Branch Operations UI mount point.
 * The host app supplies its authenticated browser Supabase client; no privileged
 * key is accepted or stored here. Every command is sent to the authenticated Edge API.
 */
const el = (tag, attrs = {}, text = "") => {
  const node = document.createElement(tag);
  for (const [key, value] of Object.entries(attrs)) {
    if (key === "className") node.className = value;
    else if (key.startsWith("on") && typeof value === "function") node.addEventListener(key.slice(2).toLowerCase(), value);
    else if (value != null) node.setAttribute(key, String(value));
  }
  if (text) node.textContent = text;
  return node;
};
const field = (labelText, name, type = "text", required = true) => {
  const wrap = el("label", { className: "branch-ops-field" });
  wrap.append(el("span", {}, labelText));
  const input = el(type === "textarea" ? "textarea" : "input", { name, type: type === "textarea" ? null : type, required: required ? "" : null });
  wrap.append(input);
  return wrap;
};
const section = (title) => {
  const node = el("section", { className: "branch-ops-section" });
  node.append(el("h3", {}, title));
  return node;
};
const makeList = (items, label) => {
  const list = el("ul", { className: "branch-ops-list" });
  if (!items.length) list.append(el("li", {}, "Belum ada data."));
  for (const item of items) {
    const primary = item.title || item.category || item.asset_code || item.source_revision || item.id;
    const detail = item.description || item.status || item.score != null ? (item.description || item.status || `Skor ${item.score}`) : "";
    const li = el("li");
    li.append(el("strong", {}, String(primary ?? label)));
    if (detail) li.append(el("span", {}, ` — ${String(detail)}`));
    list.append(li);
  }
  return list;
};
const formButton = (text) => el("button", { type: "submit", className: "branch-ops-submit" }, text);

export function mountBranchOperationsUI({ root, supabase, tenantId, branchId, onError = () => {} }) {
  if (!root || !supabase?.functions?.invoke || !tenantId || !branchId) {
    throw new TypeError("root, authenticated Supabase client, tenantId and branchId are required");
  }
  let destroyed = false;
  const shell = el("div", { className: "branch-operations" });
  const header = el("header");
  header.append(el("h2", {}, "Branch Operations"));
  header.append(el("p", {}, "Tugas harian, insiden, pemeliharaan aset, bukti privat, dan audit kepatuhan."));
  const notice = el("p", { role: "status", "aria-live": "polite", className: "branch-ops-notice" });
  const refreshButton = el("button", { type: "button" }, "Muat ulang");
  header.append(refreshButton);
  shell.append(header, notice);
  const style = el("style");
  style.textContent = ".branch-operations{display:grid;gap:18px}.branch-ops-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(260px,1fr));gap:14px}.branch-ops-section,.branch-ops-form{background:var(--surface,#fff);border:1px solid var(--border,#ead7d8);border-radius:14px;padding:16px;min-width:0}.branch-ops-section h3,.branch-ops-form h3{margin:0 0 12px}.branch-ops-list{padding-left:20px;margin:0;display:grid;gap:9px}.branch-ops-list li span{display:block;color:var(--muted,#806b70);font-size:12px}.branch-ops-field{display:grid;gap:6px;margin:10px 0;font-size:12px}.branch-ops-field input,.branch-ops-field textarea,.branch-ops-field select{width:100%;min-width:0;padding:10px;border:1px solid var(--border,#ead7d8);border-radius:8px;background:var(--surface,#fff);color:inherit}.branch-ops-submit,.branch-ops-review{border:0;border-radius:8px;padding:10px 14px;background:var(--wine,#59152b);color:#fff;cursor:pointer}.branch-ops-submit:disabled,.branch-ops-review:disabled{opacity:.55;cursor:wait}.branch-ops-check{display:grid;grid-template-columns:minmax(0,1fr) auto;gap:10px;padding:10px 0;border-bottom:1px solid var(--border,#ead7d8)}";
  shell.append(style);

  const grids = el("div", { className: "branch-ops-grid" });
  const lists = {};
  for (const [key, title] of [["tasks","Tugas"],["incidents","Insiden"],["maintenance","Work order"],["equipment","Equipment"],["compliance-checks","Pemeriksaan kepatuhan"],["compliance","Snapshot kepatuhan"]]) {
    const panel = section(title);
    lists[key] = el("div");
    panel.append(lists[key]);
    grids.append(panel);
  }
  shell.append(grids);

  const forms = el("div", { className: "branch-ops-grid" });
  const taskForm = el("form", { className: "branch-ops-form" });
  taskForm.append(el("h3", {}, "Buat tugas cabang"), field("Judul", "title"), field("ID assignee", "assignee_id"),
    field("Jatuh tempo", "due_at", "datetime-local"), field("Prioritas", "priority"));
  taskForm.querySelector('[name="priority"]').value = "normal";
  taskForm.append(formButton("Simpan tugas"));

  const incidentForm = el("form", { className: "branch-ops-form" });
  incidentForm.append(el("h3", {}, "Catat insiden"), field("Kategori", "category"), field("Deskripsi", "description", "textarea"),
    field("Tingkat keparahan", "severity"), field("Waktu kejadian", "occurred_at", "datetime-local"),
    field("Bukti (JPG/PNG/PDF, maks. 8 MB)", "file", "file", false));
  incidentForm.querySelector('[name="severity"]').value = "medium";
  incidentForm.append(formButton("Unggah bukti & catat insiden"));

  const equipmentForm = el("form", { className: "branch-ops-form" });
  equipmentForm.append(el("h3", {}, "Daftarkan equipment"), field("Kode aset", "asset_code"),
    field("Nama equipment", "name"));
  equipmentForm.append(formButton("Simpan equipment"));

  const maintenanceForm = el("form", { className: "branch-ops-form" });
  maintenanceForm.append(el("h3", {}, "Buat work order"), field("ID equipment", "equipment_id"),
    field("Jenis", "maintenance_type"), field("Jadwal", "scheduled_at", "datetime-local"),
    field("Deskripsi", "description", "textarea"), field("Assignee (opsional)", "assigned_to", "text", false));
  maintenanceForm.querySelector('[name="maintenance_type"]').value = "preventive";
  maintenanceForm.append(formButton("Simpan work order"));

  const complianceCheckForm = el("form", { className: "branch-ops-form" });
  complianceCheckForm.append(el("h3", {}, "Kirim pemeriksaan kepatuhan"), field("Kode pemeriksaan", "check_key"),
    field("Nama pemeriksaan", "title"), field("Bobot", "weight", "number"), field("Tanggal bisnis", "business_date", "date"),
    field("Bukti (JPG/PNG/PDF, maks. 8 MB)", "file", "file", false));
  complianceCheckForm.querySelector('[name="weight"]').value = "1";
  complianceCheckForm.append(formButton("Unggah bukti & kirim pemeriksaan"));

  const complianceForm = el("form", { className: "branch-ops-form" });
  complianceForm.append(el("h3", {}, "Publikasikan audit kepatuhan"), field("Mulai periode", "period_start", "date"),
    field("Akhir periode", "period_end", "date"), field("Source revision", "source_revision"));
  complianceForm.append(formButton("Publikasikan snapshot"));
  forms.append(taskForm, incidentForm, equipmentForm, maintenanceForm, complianceCheckForm, complianceForm);
  shell.append(forms);
  root.replaceChildren(shell);

  const request = async (body) => {
    const { data, error } = await supabase.functions.invoke("branch-operations", {
      body: { tenant_id: tenantId, branch_id: branchId, ...body },
    });
    if (error) throw error;
    if (data?.error) throw new Error(data.error);
    return data;
  };
  const submit = (form, handler) => form.addEventListener("submit", async (event) => {
    event.preventDefault();
    const button = form.querySelector('button[type="submit"]');
    button.disabled = true;
    try {
      await handler(new FormData(form));
      form.reset();
      if (form === taskForm) taskForm.querySelector('[name="priority"]').value = "normal";
      if (form === incidentForm) incidentForm.querySelector('[name="severity"]').value = "medium";
      if (form === maintenanceForm) maintenanceForm.querySelector('[name="maintenance_type"]').value = "preventive";
      if (form === complianceCheckForm) complianceCheckForm.querySelector('[name="weight"]').value = "1";
      notice.textContent = "Perubahan tersimpan.";
      await refresh();
    } catch (error) {
      notice.textContent = error?.message || "Workflow gagal diproses.";
      onError(error);
    } finally { button.disabled = false; }
  });
  const renderActionList = (items, kind) => {
    const list = el("div");
    if (!items.length) list.append(el("p", {}, "Belum ada data."));
    const transitions = {
      tasks: { open: [["in_progress","Mulai"],["completed","Selesaikan"]], in_progress: [["completed","Selesaikan"]] },
      incidents: { open: [["investigating","Investigasi"],["resolved","Selesaikan"]], investigating: [["resolved","Selesaikan"]], resolved: [["closed","Tutup"]] },
      maintenance: { scheduled: [["in_progress","Mulai"],["cancelled","Batalkan"]], in_progress: [["completed","Selesai"],["cancelled","Batalkan"]] },
    };
    for (const item of items) {
      const row = el("div", { className: "branch-ops-check" });
      const info = el("div");
      info.append(el("strong", {}, String(item.title || item.category || item.id)));
      info.append(el("div", {}, `${item.status} · ${item.due_at || item.scheduled_at || item.created_at || ""}`));
      if (item.description) info.append(el("small", {}, String(item.description)));
      row.append(info);
      const controls = el("div");
      if (kind === "incidents" && Array.isArray(item.evidence_asset_ids)) {
        item.evidence_asset_ids.forEach((evidenceId, index) => {
          const evidenceButton = el("button", { type: "button", className: "branch-ops-review" }, `Bukti ${index + 1}`);
          evidenceButton.addEventListener("click", async () => {
            evidenceButton.disabled = true;
            try {
              const result = await request({ action: "get-evidence-url", evidence_asset_id: evidenceId });
              const link = el("a", { href: result.signed_url, target: "_blank", rel: "noopener noreferrer" }, "Buka bukti");
              controls.append(link);
            } catch (error) { notice.textContent = error?.message || "Bukti tidak dapat diakses."; onError(error); }
            finally { evidenceButton.disabled = false; }
          });
          controls.append(evidenceButton);
        });
      }
      for (const [status, label] of transitions[kind]?.[item.status] || []) {
        const button = el("button", { type: "button", className: "branch-ops-review" }, label);
        button.addEventListener("click", async () => {
          button.disabled = true;
          try {
            const action = kind === "tasks" ? "update-task-status" : kind === "incidents" ? "update-incident-status" : "update-work-order-status";
            const idKey = kind === "tasks" ? "task_id" : kind === "incidents" ? "incident_id" : "work_order_id";
            await request({ action, [idKey]: item.id, status });
            await refresh();
          } catch (error) { notice.textContent = error?.message || "Perubahan status ditolak."; onError(error); }
          finally { button.disabled = false; }
        });
        controls.append(button);
      }
      row.append(controls); list.append(row);
    }
    return list;
  };
  const renderComplianceChecks = (items) => {
    const list = el("div");
    if (!items.length) list.append(el("p", {}, "Belum ada pemeriksaan."));
    for (const item of items) {
      const row = el("div", { className: "branch-ops-check" });
      const info = el("div");
      info.append(el("strong", {}, String(item.title || item.check_key || item.id)));
      info.append(el("div", {}, `${item.business_date} · ${item.status} · hasil: ${item.result}`));
      row.append(info);
      if (item.status === "submitted") {
        const controls = el("div");
        const result = el("select", { "aria-label": "Hasil pemeriksaan" });
        for (const [value, label] of [["pass","Lulus"],["fail","Gagal"],["not_applicable","Tidak berlaku"]]) result.append(el("option", { value }, label));
        const button = el("button", { type: "button", className: "branch-ops-review" }, "Review");
        button.addEventListener("click", async () => {
          button.disabled = true;
          try { await request({ action: "review-compliance-check", check_id: item.id, result: result.value }); await refresh(); }
          catch (error) { notice.textContent = error?.message || "Review gagal."; onError(error); }
          finally { button.disabled = false; }
        });
        controls.append(result, button); row.append(controls);
      }
      list.append(row);
    }
    return list;
  };
  const refresh = async () => {
    try {
      for (const kind of Object.keys(lists)) {
        const result = await request({ action: "list", kind });
        lists[kind].replaceChildren(kind === "compliance-checks" ? renderComplianceChecks(result.items || []) : ["tasks","incidents","maintenance"].includes(kind) ? renderActionList(result.items || [], kind) : makeList(result.items || [], kind));
      }
      if (!destroyed) notice.textContent = "Data cabang berhasil dimuat.";
    } catch (error) {
      notice.textContent = error?.message || "Data cabang belum dapat dimuat.";
      onError(error);
    }
  };
  const uploadEvidence = async (file, purpose) => {
    const form = new FormData();
    form.set("tenant_id", tenantId); form.set("branch_id", branchId);
    form.set("action", "upload-evidence"); form.set("purpose", purpose); form.set("file", file);
    const { data, error } = await supabase.functions.invoke("branch-operations", { body: form });
    if (error || data?.error) throw error || new Error(data.error);
    return data.evidence_asset_id;
  };
  submit(taskForm, async (data) => {
    const due = new Date(String(data.get("due_at")));
    if (Number.isNaN(due.valueOf())) throw new Error("Tanggal jatuh tempo tidak valid.");
    await request({
      action: "create-task", title: data.get("title"), assignee_id: data.get("assignee_id"),
      due_at: due.toISOString(), priority: data.get("priority"),
      idempotency_key: `branch-task:${crypto.randomUUID()}`,
    });
  });
  submit(incidentForm, async (data) => {
    const file = data.get("file");
    let evidenceIds = [];
    if (file instanceof File && file.size > 0) evidenceIds = [await uploadEvidence(file, "branch_incident")];
    await request({
      action: "record-incident", category: data.get("category"), description: data.get("description"),
      severity: data.get("severity"), occurred_at: data.get("occurred_at") ? new Date(String(data.get("occurred_at"))).toISOString() : null,
      evidence_asset_ids: evidenceIds, idempotency_key: `branch-incident:${crypto.randomUUID()}`,
    });
  });
  submit(equipmentForm, async (data) => {
    await request({ action: "register-equipment", asset_code: data.get("asset_code"), name: data.get("name") });
  });
  submit(maintenanceForm, async (data) => {
    await request({
      action: "create-maintenance-order", equipment_id: data.get("equipment_id"),
      maintenance_type: data.get("maintenance_type"),
      scheduled_at: new Date(String(data.get("scheduled_at"))).toISOString(),
      description: data.get("description"), assigned_to: data.get("assigned_to") || null,
      idempotency_key: `branch-maintenance:${crypto.randomUUID()}`,
    });
  });
  submit(complianceCheckForm, async (data) => {
    const file = data.get("file");
    if (!(file instanceof File) || file.size < 1) throw new Error("Bukti pemeriksaan wajib diunggah.");
    const evidenceAssetId = await uploadEvidence(file, "branch_compliance");
    await request({
      action: "submit-compliance-check", check_key: data.get("check_key"), title: data.get("title"),
      weight: Number(data.get("weight")), business_date: data.get("business_date"),
      evidence_asset_id: evidenceAssetId,
    });
  });
  submit(complianceForm, async (data) => {
    await request({
      action: "publish-compliance", period_start: data.get("period_start"), period_end: data.get("period_end"),
      source_revision: data.get("source_revision"), idempotency_key: `branch-compliance:${crypto.randomUUID()}`,
    });
  });
  refreshButton.addEventListener("click", refresh);
  refresh();
  return () => { destroyed = true; root.replaceChildren(); };
}
