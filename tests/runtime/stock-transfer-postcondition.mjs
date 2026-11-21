export async function inspectStockTransferAbsence({
  base,
  serviceRoleKey,
  transferNumber,
  idempotencyKey,
  fetchImpl = fetch,
}) {
  const queries = [
    { field: "transfer_number", value: transferNumber },
    { field: "idempotency_key", value: idempotencyKey },
  ];
  const checks = await Promise.all(queries.map(async ({ field, value }) => {
    const url = new URL("/rest/v1/stock_transfers", base);
    url.searchParams.set("select", "id");
    url.searchParams.set(field, `eq.${value}`);

    try {
      const response = await fetchImpl(url, {
        headers: {
          apikey: serviceRoleKey,
          authorization: `Bearer ${serviceRoleKey}`,
          accept: "application/json",
        },
      });
      if (!response.ok) {
        return { field, absent: false, httpStatus: response.status, rows: null };
      }

      const rows = await response.json();
      if (!Array.isArray(rows)) {
        return { field, absent: false, httpStatus: response.status, rows: null };
      }
      return { field, absent: rows.length === 0, httpStatus: response.status, rows: rows.length };
    } catch (error) {
      return {
        field,
        absent: false,
        httpStatus: null,
        rows: null,
        requestCompleted: false,
        errorType: error instanceof Error ? error.name : "UnknownError",
      };
    }
  }));

  return {
    passed: checks.every((check) => check.absent && check.httpStatus === 200),
    evidence: {
      databasePostcondition: {
        table: "stock_transfers",
        checks: checks.map(({ field, absent, httpStatus, rows, requestCompleted, errorType }) => ({
          field,
          absent,
          httpStatus,
          rows,
          ...(requestCompleted === undefined ? {} : { requestCompleted }),
          ...(errorType === undefined ? {} : { errorType }),
        })),
      },
    },
  };
}
