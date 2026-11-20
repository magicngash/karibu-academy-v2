-- Update staff profile choices to the current age bands and binary sex options.
-- Existing values outside the new choices are cleared because they cannot be
-- mapped accurately to the requested ranges.
UPDATE public.staff
SET age_range = NULL
WHERE age_range IS NOT NULL
  AND age_range NOT IN ('18_25', '26_30', '31_35', 'over_35');

UPDATE public.staff
SET sex = NULL
WHERE sex IS NOT NULL
  AND sex NOT IN ('female', 'male');

ALTER TABLE public.staff
  DROP CONSTRAINT IF EXISTS staff_age_range_valid,
  DROP CONSTRAINT IF EXISTS staff_sex_valid;

ALTER TABLE public.staff
  ADD CONSTRAINT staff_age_range_valid
    CHECK (age_range IS NULL OR age_range IN ('18_25', '26_30', '31_35', 'over_35')),
  ADD CONSTRAINT staff_sex_valid
    CHECK (sex IS NULL OR sex IN ('female', 'male'));

DO $profile_options$
DECLARE
  target regprocedure;
  function_definition text;
  updated_definition text;
  target_functions regprocedure[] := ARRAY[
    'public.create_staff(uuid,text,text,text,text,text,text,text)'::regprocedure,
    'public.update_staff_profile(uuid,text,text,text,text,text)'::regprocedure
  ];
BEGIN
  FOREACH target IN ARRAY target_functions LOOP
    function_definition := pg_get_functiondef(target::oid);
    updated_definition := regexp_replace(
      function_definition,
      '''under_18'',''18_24'',''25_34'',''35_44'',''45_54'',''55_plus'',''prefer_not_to_say''',
      '''18_25'',''26_30'',''31_35'',''over_35''',
      'g'
    );
    updated_definition := regexp_replace(
      updated_definition,
      '''female'',''male'',''intersex'',''prefer_not_to_say''',
      '''female'',''male''',
      'g'
    );
    IF updated_definition <> function_definition THEN
      EXECUTE updated_definition;
    END IF;
  END LOOP;
END;
$profile_options$;
