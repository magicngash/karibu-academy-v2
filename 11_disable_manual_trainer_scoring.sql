-- Karibu Academy V2: keep written-answer scoring assessment-only for now.
-- Run after 10_manager_review_fixes.sql. This is reversible by restoring the grant.
revoke all on function public.review_assessment_written_answer(uuid,integer,integer,text,text) from public, anon, authenticated;
