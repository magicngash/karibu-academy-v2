-- TEMPORARY TEST SETTING: applies a 20% pass mark to all accounts and manager recalculations.
-- Restore the standard 80% threshold with a follow-up migration when workflow testing is complete.
-- Historical pass records created during this window remain passed after restoration.
DO $passmark$
DECLARE
  target regprocedure;
  function_definition text;
  updated_definition text;
  threshold_matches integer;
  target_functions regprocedure[] := ARRAY[
    'public.complete_assessment_internal(uuid,text,jsonb)'::regprocedure,
    'public.finalize_assessment_marking(uuid,text,uuid)'::regprocedure,
    'public.recalculate_assessment_attempt(uuid,text)'::regprocedure
  ];
BEGIN
  FOREACH target IN ARRAY target_functions LOOP
    function_definition := pg_get_functiondef(target::oid);
    SELECT count(*) INTO threshold_matches
    FROM regexp_matches(
      function_definition,
      'v_passed[[:space:]]*:=[[:space:]]*v_overall[[:space:]]*>=[[:space:]]*80',
      'g'
    ) AS matches;
    IF threshold_matches <> 1 THEN
      RAISE EXCEPTION 'Expected exactly one 80%% pass threshold in %, found %', target, threshold_matches;
    END IF;

    updated_definition := regexp_replace(
      function_definition,
      'v_passed[[:space:]]*:=[[:space:]]*v_overall[[:space:]]*>=[[:space:]]*80',
      'v_passed:=v_overall>=20',
      'g'
    );
    IF updated_definition = function_definition THEN
      RAISE EXCEPTION 'Could not apply the temporary pass threshold to %', target;
    END IF;
    EXECUTE updated_definition;
  END LOOP;
END;
$passmark$;
