/** Server-authoritative cart pricing contract. Client-supplied prices are never read. */
const integer=(v,n)=>{if(!Number.isSafeInteger(v)||v<0)throw new TypeError(n+"_invalid");return v;};
export function buildValidatedCart({ requestedItems, catalogItems, branchId, availableStockByProduct }) {
  if (!Array.isArray(requestedItems) || requestedItems.length === 0) throw new Error("cart_empty");
  if (typeof branchId !== "string" || !branchId) throw new Error("cart_branch_required");
  const catalog = new Map((catalogItems || []).map((product) => [product.id, product]));
  const seenLines = new Set();
  const requestedByProduct = new Map();

  for (const requested of requestedItems) {
    if (!requested?.productId || !Number.isInteger(requested.quantity) ||
        requested.quantity < 1 || requested.quantity > 100) throw new Error("quantity_invalid");
    const ids = Array.isArray(requested.modifierIds) ? requested.modifierIds : [];
    if (ids.some((id) => typeof id !== "string" || !id) || new Set(ids).size !== ids.length) {
      throw new Error("modifier_selection_invalid");
    }
    const note = typeof requested.note === "string" ? requested.note.trim().slice(0, 300) : "";
    const lineKey = JSON.stringify([requested.productId, [...ids].sort(), note]);
    if (seenLines.has(lineKey)) throw new Error("cart_duplicate_line");
    seenLines.add(lineKey);
    requestedByProduct.set(requested.productId, (requestedByProduct.get(requested.productId) || 0) + requested.quantity);
  }

  const items = requestedItems.map((requested) => {
    const product = catalog.get(requested.productId);
    if (!product || product.is_active !== true) throw new Error("product_unavailable");
    if (!product.allowed_branch_ids?.includes(branchId)) throw new Error("product_branch_forbidden");
    const totalRequested = requestedByProduct.get(product.id);
    const stock = availableStockByProduct?.[product.id];
    if (Number.isInteger(stock) && totalRequested > stock) throw new Error("insufficient_available_stock");

    const unit = integer(product.unit_price_idr, "server_price");
    const modifierOptions = new Map((product.modifiers || []).filter((modifier) => modifier.is_active).map((modifier) => [modifier.id, modifier]));
    const selected = (requested.modifierIds || []).map((id) => {
      const modifier = modifierOptions.get(id);
      if (!modifier) throw new Error("modifier_unavailable");
      return Object.freeze({ id: modifier.id, name: modifier.name, price_idr: integer(modifier.price_idr || 0, "modifier_price") });
    });
    for (const group of product.required_modifier_groups || []) {
      if (!selected.some((modifier) => (group.option_ids || []).includes(modifier.id))) {
        throw new Error("required_modifier_missing");
      }
    }
    const modifierTotal = selected.reduce((sum, modifier) => sum + modifier.price_idr, 0);
    const lineTotal = (unit + modifierTotal) * requested.quantity;
    if (!Number.isSafeInteger(lineTotal)) throw new RangeError("cart_total_out_of_range");
    return Object.freeze({
      product_id: product.id,
      product_name_snapshot: product.name,
      quantity: requested.quantity,
      unit_price_idr: unit,
      modifier_snapshot: selected,
      line_total_idr: lineTotal,
      note: typeof requested.note === "string" ? requested.note.trim().slice(0, 300) : "",
    });
  });
  const subtotal = items.reduce((sum, item) => sum + item.line_total_idr, 0);
  if (!Number.isSafeInteger(subtotal)) throw new RangeError("cart_total_out_of_range");
  return Object.freeze({ branch_id: branchId, items: Object.freeze(items), subtotal_idr: subtotal });
}
