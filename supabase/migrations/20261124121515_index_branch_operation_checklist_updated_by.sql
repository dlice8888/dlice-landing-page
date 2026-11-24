-- Cover the nullable updated_by FK introduced by the atomic branch checklist audit migration.
CREATE INDEX IF NOT EXISTS idx_branch_operation_checklist_runs_updated_by
  ON public.branch_operation_checklist_runs (updated_by);
