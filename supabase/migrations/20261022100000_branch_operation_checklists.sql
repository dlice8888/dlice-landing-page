-- Branch opening/closing checklist foundation (staging-first).
-- Operational rows are accessible only through the authenticated Edge Function.
CREATE TABLE IF NOT EXISTS public.branch_operation_checklist_runs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  branch_id uuid NOT NULL REFERENCES public.branches(id) ON DELETE RESTRICT,
  business_date date NOT NULL,
  checklist_type text NOT NULL CHECK (checklist_type IN ('opening', 'closing')),
  template_version integer NOT NULL DEFAULT 1 CHECK (template_version > 0),
  items jsonb NOT NULL DEFAULT '[]'::jsonb CHECK (jsonb_typeof(items) = 'array'),
  status text NOT NULL DEFAULT 'in_progress' CHECK (status IN ('in_progress', 'completed', 'blocked')),
  notes text,
  started_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  completed_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  started_at timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz,
  version integer NOT NULL DEFAULT 1 CHECK (version > 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT branch_operation_checklist_run_unique UNIQUE (branch_id, business_date, checklist_type),
  CONSTRAINT branch_operation_checklist_completion_consistent CHECK (
    (status = 'completed' AND completed_at IS NOT NULL AND completed_by IS NOT NULL)
    OR (status <> 'completed' AND completed_at IS NULL)
  )
);

CREATE INDEX IF NOT EXISTS branch_operation_checklist_branch_date_idx
  ON public.branch_operation_checklist_runs (branch_id, business_date DESC, checklist_type);

ALTER TABLE public.branch_operation_checklist_runs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS deny_direct_client_access ON public.branch_operation_checklist_runs;
CREATE POLICY deny_direct_client_access
  ON public.branch_operation_checklist_runs
  AS RESTRICTIVE FOR ALL TO anon, authenticated
  USING (false) WITH CHECK (false);

REVOKE ALL ON TABLE public.branch_operation_checklist_runs FROM anon, authenticated;
GRANT ALL ON TABLE public.branch_operation_checklist_runs TO service_role;
