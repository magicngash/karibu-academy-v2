-- RESTORE STANDARD SETTING: return all server-side assessment decisions to an 80% pass mark.
-- Existing assessment attempts are preserved; this only affects future finalization and recalculation.
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
      'v_passed[[:space:]]*:=[[:space:]]*v_overall[[:space:]]*>=[[:space:]]*(20|80)',
      'g'
    ) AS matches;
    IF threshold_matches <> 1 THEN
      RAISE EXCEPTION 'Expected exactly one assessment pass threshold in %, found %', target, threshold_matches;
    END IF;

    updated_definition := regexp_replace(
      function_definition,
      'v_passed[[:space:]]*:=[[:space:]]*v_overall[[:space:]]*>=[[:space:]]*20',
      'v_passed:=v_overall>=80',
      'g'
    );
    IF updated_definition <> function_definition THEN
      EXECUTE updated_definition;
    END IF;
  END LOOP;
END;
$passmark$;
