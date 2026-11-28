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

  const grids = el("div", { className: "branch-ops-grid" });
  const lists = {};
  for (const [key, title] of [["tasks","Tugas"],["incidents","Insiden"],["maintenance","Work order"],["compliance","Snapshot kepatuhan"]]) {
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

  const maintenanceForm = el("form", { className: "branch-ops-form" });
  maintenanceForm.append(el("h3", {}, "Buat work order"), field("ID equipment", "equipment_id"),
    field("Jenis", "maintenance_type"), field("Jadwal", "scheduled_at", "datetime-local"),
    field("Deskripsi", "description", "textarea"), field("Assignee (opsional)", "assigned_to", "text", false));
  maintenanceForm.querySelector('[name="maintenance_type"]').value = "preventive";
  maintenanceForm.append(formButton("Simpan work order"));

  const complianceForm = el("form", { className: "branch-ops-form" });
  complianceForm.append(el("h3", {}, "Publikasikan audit kepatuhan"), field("Mulai periode", "period_start", "date"),
    field("Akhir periode", "period_end", "date"), field("Source revision", "source_revision"));
  complianceForm.append(formButton("Publikasikan snapshot"));
  forms.append(taskForm, incidentForm, maintenanceForm, complianceForm);
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
      notice.textContent = "Perubahan tersimpan.";
      await refresh();
    } catch (error) {
      notice.textContent = error?.message || "Workflow gagal diproses.";
      onError(error);
    } finally { button.disabled = false; }
  });
  const refresh = async () => {
    try {
      for (const kind of Object.keys(lists)) {
        const result = await request({ action: "list", kind });
        lists[kind].replaceChildren(makeList(result.items || [], kind));
      }
      if (!destroyed) notice.textContent = "Data cabang berhasil dimuat.";
    } catch (error) {
      notice.textContent = error?.message || "Data cabang belum dapat dimuat.";
      onError(error);
    }
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
    if (file instanceof File && file.size > 0) {
      const form = new FormData();
      form.set("tenant_id", tenantId); form.set("branch_id", branchId);
      form.set("action", "upload-evidence"); form.set("purpose", "branch_incident"); form.set("file", file);
      const { data: upload, error } = await supabase.functions.invoke("branch-operations", { body: form });
      if (error || upload?.error) throw error || new Error(upload.error);
      evidenceIds = [upload.evidence_asset_id];
    }
    await request({
      action: "record-incident", category: data.get("category"), description: data.get("description"),
      severity: data.get("severity"), occurred_at: data.get("occurred_at") ? new Date(String(data.get("occurred_at"))).toISOString() : null,
      evidence_asset_ids: evidenceIds, idempotency_key: `branch-incident:${crypto.randomUUID()}`,
    });
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
