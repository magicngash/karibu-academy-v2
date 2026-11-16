-- The learner app calls this RPC directly using its custom staff session token.
-- The SECURITY DEFINER function validates that token with private.auth and
-- returns an attempt only when the authenticated staff member owns it.
revoke all on function public.get_assessment_attempt_for_staff(uuid, text)
  from public, anon, authenticated;
grant execute on function public.get_assessment_attempt_for_staff(uuid, text)
  to anon, authenticated, service_role;
