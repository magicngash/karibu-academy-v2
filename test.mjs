import { readFile } from "node:fs/promises";
import { spawn } from "node:child_process";
import completeAssessment from "./netlify/functions/complete-assessment.mjs";

const read = (file) => readFile(file, "utf8");
const assert = (condition, message) => {
  if (!condition) throw new Error(message);
};

const baseSchema = await read("01_schema.sql");
const baseFunctions = await read("02_functions.sql");
const baseSecurity = await read("03_security.sql");
const baseVerification = await read("04_verification.sql");
const index = await read("index.html");
const endpoint = await read("netlify/functions/mark-written-answer.mjs");
const completionEndpoint = await read("netlify/functions/complete-assessment.mjs");
const markingMigration = await read("15_assessment_marking_progress.sql");
const resumeMigration = await read("16_training_resume.sql");
const attemptAccessMigration = await read("17_assessment_attempt_rpc_access.sql");
const retakeMigration = await read("18_atomic_retake_attempt.sql");
const blankRetakeMigration = await read("19_recover_blank_retake_attempt.sql");
const whitespaceMigration = await read("20_preserve_written_draft_whitespace.sql");
const guideAcknowledgementMigration = await read("21_course_guide_acknowledgements.sql");
const passMarkMigration = await read("22_temporary_test_pass_mark_20.sql");
const staffProfileMigration = await read("23_staff_profile_fields.sql");
const profileUpdateMigration = await read("24_update_staff_profile.sql");
const migration = await read("08_security_and_review_fixes.sql");
const verification = await read("09_security_verification.sql");
const pkg = JSON.parse(await read("package.json"));
const retakeHandler = index.slice(index.indexOf("async function retake()"), index.indexOf("function persistWrittenCache"));
const writtenDraftSaveHandler = index.slice(index.indexOf("async function saveWrittenDraft("), index.indexOf("async function submitShortAnswer("));
const resumeTrainingHandler = index.slice(index.indexOf("async function handleResumeTraining()"), index.indexOf("async function retryResumeLookup"));
const blankRetakeHelper = index.slice(index.indexOf("function isBlankUnstartedRetake(resume)"), index.indexOf("function getResumeLocationLabel(resume)"));

assert(!/\bcorrect\s*:/.test(index), "frontend still contains MCQ answer keys");
assert(!/\bmodelAnswer\s*:/.test(index), "frontend still contains case-study model answers");
assert(!/\brubric\s*:/.test(index), "frontend still contains written-answer rubrics");
assert(!/\bsample\s*:/.test(index), "frontend still contains written-answer samples");
assert(index.includes('callRpc("save_assessment_written_answer"'), "written answers are not saved against the active assessment attempt");
assert(index.includes('role: "alert"') && index.includes("Retry save"), "written-answer save failures are not visible and retryable");
assert(index.includes("Your draft autosaves as you type. Press Save response to submit it.") && index.includes('callRpc("save_assessment_written_draft"'), "written-answer draft autosave is not explained");
assert(index.includes("await onDraftSave(value);") && index.includes("current.onDraftSave(current.draft, { keepalive: true })") && !index.includes("onDraftSave(value.trim())") && !index.includes("current.onDraftSave(current.draft.trim()"), "written-answer autosave trims whitespace before saving and can join words when a learner pauses");
assert(index.includes('"aria-live": "polite"') && index.includes('position: "absolute"') && !index.includes("Your draft is being saved to your account.") && !index.includes("Draft saved to your account. Press Save response before continuing."), "normal autosave status messages still pop up visually while typing");
assert(index.includes("const writtenResponsesRef = React.useRef(restoredWrittenResponses)") && index.includes("writtenResponsesRef.current = nextResponses") && !index.includes('setDraft(answer || "")'), "active written-answer input is resynced from parent state and can lose in-progress typing");
assert(writtenDraftSaveHandler.includes("writtenResponsesRef.current[shortIndex] === response") && !writtenDraftSaveHandler.includes("setWrittenResponses(") && !writtenDraftSaveHandler.includes("persistWrittenCache("), "a stale autosave response can overwrite newer written text or local cache");
assert(whitespaceMigration.includes("security definer") && whitespaceMigration.includes("for update") && whitespaceMigration.includes("values(p_attempt_id,p_question_index,p_answer,now())") && whitespaceMigration.includes("length(btrim(coalesce(p_answer,'')))=0"), "the database draft saver does not preserve meaningful whitespace while validating and clearing blank drafts");
assert(index.includes('window.addEventListener("pagehide", saveDraftOnPageHide)') && index.includes("keepalive: true"), "the latest written draft is not flushed when the learner leaves the page");
assert(index.includes('callRpc("get_latest_training_resume"') && index.includes("getResumeLocationLabel") && index.includes('"Resume Training"'), "signed-in landing does not offer a server-backed resume action");
assert(index.includes("resumeLookupError") && index.includes("onRetryResume") && index.includes("Check again"), "a failed resume lookup is hidden instead of retryable");
assert(index.includes('const COURSE_GUIDE_VERSION = "service-training-guide-v1"') && !index.includes("/course-guide.pdf") && index.includes("function CourseGuideReader({ branding, onBack })") && index.includes("function getBrandingLabel(branding)") && index.includes("document.title = screen === \"course-guide\" ? `${appName} · Course Guide` : `${appName} · ${restaurantName} Training`"), "tenant branding or the in-app Course Guide reader is missing");
assert(index.includes("RESTAURANT_BRANDING = { name: data.name, app_name: data.app_name }") && index.includes("branding?.name ? `${branding.name} Training` : \"Training\"") && index.includes("${branding?.app_name || \"training\"}"), "tenant slug or stored restaurant/app names are not wired into the learner landing and home screen");
assert(index.includes('callRpc("get_course_guide_acknowledgement"') && index.includes('callRpc("acknowledge_course_guide"') && index.includes('if (!courseGuideAcknowledged) {\n      setScreen("signed-in");'), "course-guide acknowledgement is not checked before saved-screen restoration");
const guideGate = index.slice(index.indexOf("function CourseGuideGate({"), index.indexOf("function SignedInLanding({"));
assert(guideGate.includes("onClick: onOpenCourseGuide") && guideGate.includes("Read the full Course Guide") && guideGate.includes("disabled: !guideOpened || !guideConfirmed || busy") && guideGate.includes("I have read and understand the Course Guide."), "the gate does not open the in-app guide or require confirmation before continuing");
const guideReader = index.slice(index.indexOf("function CourseGuideReader({ branding, onBack })"), index.indexOf("function CourseGuideGate({"));
assert(["Warmth —", "Honesty —", "Attentiveness —", "Teamwork —", "Module 1: Warm Welcomes", "Module 10: Service Standards", "the multiple-choice questions for that module and five written questions", "at least 80%", "Retake exam", "another browser or device", "contact your manager or coach"].every(text => guideReader.includes(text)) && !guideReader.includes("five multiple-choice questions") && guideReader.includes("onClick: onBack"), "the in-app guide is missing learner guidance, has an incorrect fixed MCQ count, or lacks a way back to the landing page");
assert(!index.includes("ASSESSMENT_PASS_MARK_PERCENT") && !index.includes("TEMPORARY ASSESSMENT TEST MODE") && !index.includes("Temporary test pass mark") && !index.includes("temporary workflow testing only") && index.includes("The pass mark is 80%.") && guideReader.includes("You need at least 80%"), "temporary test-mode wording remains visible instead of the normal 80% learner UI");
assert(["public.complete_assessment_internal(uuid,text,jsonb)", "public.finalize_assessment_marking(uuid,text,uuid)", "public.recalculate_assessment_attempt(uuid,text)"].every(signature => passMarkMigration.includes(signature)) && passMarkMigration.includes("v_passed[[:space:]]*:=[[:space:]]*v_overall[[:space:]]*>=[[:space:]]*80") && passMarkMigration.includes("v_passed:=v_overall>=20") && passMarkMigration.includes("threshold_matches <> 1"), "the temporary migration does not guard and update every server-side assessment pass decision");
assert(index.includes('"Department"') && index.includes('"Age range (optional)"') && index.includes('"Sex (optional)"') && index.includes('maxLength: 80,\n    required: true') && index.includes("p_department: newDepartment.trim()") && index.includes("p_age_range: newAgeRange || null") && index.includes("p_sex: newSex || null") && index.includes("Ask the staff member rather than guessing") && index.includes("only managers at this restaurant can view them") && index.includes('setNewDepartment("")') && index.includes('setNewAgeRange("")') && index.includes('setNewSex("")') && index.includes("profileSummary"), "manager staff creation does not enforce the required department, preserve optionality/privacy, reset state, and display saved profile details");
assert(["under_18", "18_24", "25_34", "35_44", "45_54", "55_plus", "prefer_not_to_say", "female", "male", "intersex"].every(value => index.includes(`value: \"${value}\"`) && staffProfileMigration.includes(value) && baseFunctions.includes(value)), "UI and database do not share the complete validated age-range and sex option sets");
assert(staffProfileMigration.includes("add column if not exists department text") && staffProfileMigration.includes("add column if not exists age_range text") && staffProfileMigration.includes("add column if not exists sex text") && staffProfileMigration.includes("staff_age_range_valid") && staffProfileMigration.includes("staff_sex_valid"), "staff-profile migration lacks validated profile columns");
assert(staffProfileMigration.includes("create function public.manager_dashboard") && staffProfileMigration.includes("s.department") && staffProfileMigration.includes("s.age_range") && staffProfileMigration.includes("s.sex") && staffProfileMigration.includes("m.role='manager'") && staffProfileMigration.includes("grant execute on function public.manager_dashboard(uuid,text) to anon, authenticated, service_role"), "profile fields are not retrieved through the tenant-scoped manager-only dashboard RPC");
assert(staffProfileMigration.includes("if p_pin is null or p_pin !~") && baseFunctions.includes("if p_pin is null or p_pin !~"), "staff creation does not reject an absent PIN safely");
assert(index.includes("async function handleSaveProfile(e, staffId)") && index.includes('callRpc("update_staff_profile"') && index.includes("Save Profile") && index.includes("Edit Profile") && index.includes("await loadDashboard()"), "manager cannot save and refresh an existing staff profile in the browser");
assert(index.includes('saving ? "Saving..." : "Save & Add Staff"'), "the new-staff form does not clearly label its save/create action");
assert(["p_full_name: profileFullName.trim()", "p_department: profileDepartment.trim()", "p_age_range: profileAgeRange || null", "p_sex: profileSex || null"].every(value => index.includes(value)), "profile editor does not submit the complete profile fields");
assert(profileUpdateMigration.includes("private.auth(p_auth_token)") && profileUpdateMigration.includes("m.role='manager'") && profileUpdateMigration.includes("target_restaurant_id is distinct from a.restaurant_id") && profileUpdateMigration.includes("set full_name=btrim(p_full_name)") && profileUpdateMigration.includes("invalid_department") && profileUpdateMigration.includes("invalid_age_range") && profileUpdateMigration.includes("invalid_sex") && profileUpdateMigration.includes("unique_violation"), "profile update RPC lacks manager/tenant authorization or field validation");
assert(baseFunctions.includes("create or replace function public.update_staff_profile(") && baseSecurity.includes("update_staff_profile(uuid,text,text,text,text,text)") && baseVerification.includes("update_staff_profile") && baseVerification.includes("authenticates_manager"), "bootstrap grants or verification omit the profile update RPC");
assert(baseSchema.includes("department text") && baseSchema.includes("age_range text") && baseSchema.includes("sex text") && baseFunctions.includes("p_department text default 'Unassigned'") && baseFunctions.includes("returns table(staff_id uuid,full_name text,role text,department text,age_range text,sex text"), "fresh-install schema and functions do not include the staff profile fields or older-client fallback");
assert(baseSecurity.includes("create_staff(uuid,text,text,text,text,text,text,text)") && baseVerification.includes("uuid, text, text, text, text, text, text, text") && baseVerification.includes("validates_department") && baseVerification.includes("handles_age_range") && baseVerification.includes("handles_sex") && staffProfileMigration.includes("p_department text default 'Unassigned'"), "security grants, verification, or migration compatibility are stale for the extended staff-creation RPC");
assert(index.includes("function openCourseGuide(returnScreen)") && index.includes("setCourseGuideReturnScreen(returnScreen === \"home\" ? \"home\" : \"signed-in\")") && index.includes('screen === "course-guide" && session') && index.includes('onOpenCourseGuide: () => openCourseGuide("home")'), "Course Guide navigation cannot open and return from both the landing and course home");
assert(!index.includes('screen === "welcome"') && !index.includes('setScreen("welcome")') && !index.includes(":onboarding`"), "the old device-local onboarding flow can bypass the account-backed guide gate");
assert(guideAcknowledgementMigration.includes("staff_course_guide_acknowledgements") && guideAcknowledgementMigration.includes("primary key (staff_id, guide_version)") && guideAcknowledgementMigration.includes("private.auth(p_auth_token)") && guideAcknowledgementMigration.includes("v_auth.principal_id") && guideAcknowledgementMigration.includes("enable row level security") && guideAcknowledgementMigration.includes("grant execute on function public.acknowledge_course_guide(text,text)"), "guide acknowledgement is not stored per authenticated staff account with least-privilege RPC access");
assert(blankRetakeMigration.includes("create or replace function public.recover_blank_assessment_retake") && blankRetakeMigration.includes("for update") && blankRetakeMigration.includes("previous_attempt.status='failed'") && ["assessment_mcq_answers", "assessment_written_answers", "assessment_written_drafts"].every(table => blankRetakeMigration.includes(table)) && blankRetakeMigration.includes("grant execute on function public.recover_blank_assessment_retake") && blankRetakeMigration.includes("to anon,authenticated,service_role"), "blank-retake recovery is not transactionally guarded and narrowly granted");
assert(blankRetakeHelper.includes('attempt.status === "in_progress"') && blankRetakeHelper.includes("Number(attempt.attempt_number) > 1") && blankRetakeHelper.includes("Number(attempt.current_step) === 0") && ["resume?.mcq_answers", "resume?.written_answers", "resume?.written_drafts"].every(key => blankRetakeHelper.includes(key)), "blank-retake recovery does not require an active later attempt with no saved answer or draft rows");
assert(resumeTrainingHandler.includes('callRpc("recover_blank_assessment_retake"') && resumeTrainingHandler.includes("p_step_index: quizStartStep") && resumeTrainingHandler.includes("Number(savedPosition.current_step) !== quizStartStep") && resumeTrainingHandler.includes("setModuleResumeSnapshot(snapshot)"), "Resume Training does not atomically persist and verify the recovered exam position before opening it");
assert(index.includes("· Retake exam"), "the resume card does not label a pristine later attempt as a retake");
assert(index.includes('callRpc("save_assessment_resume_step"') && index.includes("resumeSnapshot?.mcq_answers") && index.includes("resumeSnapshot?.written_answers"), "server resume does not save the current step and restore submitted answers");
assert(index.includes("async function persistResumeStep") && index.includes("if (!await persistResumeStep(ns)) return"), "module navigation is not gated on saving the next resume position");
assert(index.includes('index === count - 1 && /*#__PURE__*/React.createElement(CompletionStatusBanner') && !index.includes('inQuiz && /*#__PURE__*/React.createElement(CompletionStatusBanner'), "completion status is not located with the final quiz action");
assert(resumeMigration.includes("current_step") && resumeMigration.includes("assessment_written_drafts") && resumeMigration.includes("get_latest_training_resume"), "resume migration lacks step, draft, or latest-resume persistence");
assert(resumeMigration.includes("enable row level security") && resumeMigration.includes("'cleared',true"), "resume migration does not protect draft rows or support clearing a draft");
assert(index.includes("marking_request_failed") && index.includes("incomplete_assessment"), "AI-marking and incomplete-assessment errors are not mapped for learners");
assert(index.includes("don’t click Complete Module again") && index.includes('"aria-live"'), "module completion does not announce a clear wait message accessibly");
assert(index.includes('"Processing…"') && index.includes("completionStarted.current"), "module completion does not prevent repeat taps or show processing feedback");
assert(index.includes("Scoring written answers:") && index.includes("of ${total}"), "learner status does not show persisted written-answer scoring progress as text");
assert(index.includes('callRpc("get_assessment_attempt_for_staff"') && index.includes("waitForAssessmentResult"), "completion state cannot be checked or recovered from saved server status");
assert(attemptAccessMigration.includes("revoke all on function public.get_assessment_attempt_for_staff(uuid, text)") && attemptAccessMigration.includes("from public, anon, authenticated") && attemptAccessMigration.includes("grant execute on function public.get_assessment_attempt_for_staff(uuid, text)") && attemptAccessMigration.includes("to anon, authenticated, service_role"), "attempt-status RPC is not granted narrowly to app roles with server role retained");
assert(retakeMigration.includes("create or replace function public.start_assessment_retake_attempt") && retakeMigration.includes("public.start_assessment_attempt") && retakeMigration.includes("set current_step=p_step_index") && retakeMigration.includes("revoke all on function public.start_assessment_retake_attempt") && retakeMigration.includes("from public,anon,authenticated") && retakeMigration.includes("grant execute on function public.start_assessment_retake_attempt") && retakeMigration.includes("to anon,authenticated,service_role"), "atomic retake RPC does not preserve custom-authenticated access and resume-position persistence");
assert(retakeHandler.includes('callRpc("start_assessment_retake_attempt"') && retakeHandler.includes("p_module_id: moduleId") && retakeHandler.includes("p_step_index: quizStartIndex") && retakeHandler.includes("setAssessmentAttemptId(data.attempt_id)") && retakeHandler.includes("setStep(quizStartIndex)"), "retake does not create a fresh server attempt and start at the first exam question");
assert(["setAnswers([])", "setSelectedOptions([])", "setWrittenResponses([])", "setWrittenSubmitted([])", "setWrittenDraftSaved([])"].every(reset => retakeHandler.includes(reset)), "retake does not clear previous MCQ answers, written responses, submitted flags, and drafts");
assert(retakeHandler.includes("completionStarted.current = false") && retakeHandler.includes("finalResultHandled.current = false") && retakeHandler.includes("pendingAnswerSaves.current = []") && retakeHandler.includes("pendingDraftSaves.current = []"), "retake does not reset assessment submission and marking state");
assert(!retakeHandler.includes('callRpc("save_assessment_resume_step"'), "retake still uses a separate, non-atomic resume-position write");
assert(retakeHandler.includes("assessmentAttemptIdRef.current = data.attempt_id") && index.includes("assessmentAttemptIdRef.current !== requestedAttemptId"), "status responses from the previous attempt can overwrite a retake");
assert(index.includes("disabled: submitted") && index.includes("Starting a fresh exam attempt…") && index.includes('"aria-live": "polite"'), "retake does not provide a blank writable response state and accessible startup feedback");
const completionButton = index.slice(index.indexOf("function Complete({"), index.indexOf("function ComingSoon({"));
assert(completionButton.includes("!completing && passed && nextModuleAvailable && onNextModule") && completionButton.includes("Continue to next module") && completionButton.includes("Back to modules"), "the next-module action is not limited to passed modules with an available next module");
const moduleAdvance = index.slice(index.indexOf("function getNextAvailableModule(moduleId)"), index.indexOf("async function finishModule("));
assert(moduleAdvance.includes("MODULES.find(module => module.id === Number(moduleId) + 1 && module.available) || null") && moduleAdvance.includes("setModuleResumeSnapshot(null)") && moduleAdvance.includes("setActiveMod(nextModule)") && moduleAdvance.includes("exitToHome()"), "Continue does not advance to an available next module or return safely when there is none");
const moduleRender = index.slice(index.indexOf('screen === "module" && activeMod && MODULE_DATA[activeMod.id]'), index.indexOf('screen === "coming-soon" && activeMod'));
assert(moduleRender.includes("key: activeMod.id") && moduleRender.includes("nextModuleAvailable: Boolean(getNextAvailableModule(activeMod.id))"), "changing modules may reuse stale ModuleFlow state or show the Continue button when no next module is available");
assert(completionEndpoint.includes('begin_assessment_marking') && completionEndpoint.includes('save_assessment_marking_score'), "completion endpoint does not start durable marking or save each score");
assert(completionEndpoint.includes('finalize_assessment_marking') && completionEndpoint.includes('pause_assessment_marking'), "completion endpoint does not finalize or safely pause resumable marking");
assert(markingMigration.includes("marking_lease_expires_at") && markingMigration.includes("marking_last_error"), "assessment marking migration lacks a recovery lease or saved error state");
assert(markingMigration.includes("grant execute on function public.begin_assessment_marking") && markingMigration.includes("to service_role"), "marking control RPCs are not restricted to the server role");
assert(endpoint.includes('missing_authentication'), "AI endpoint does not require authentication");
assert(endpoint.includes('manager_assessment_answer_context'), "AI endpoint does not use attempt-specific context");
assert(endpoint.includes('save_attempt_ai_mark'), "AI endpoint does not persist attempt-specific marks");
assert(migration.includes("server_authoritative_completion"), "progression migration missing completion protection");
assert(migration.includes("module_locked"), "progression migration missing module locking");
assert(migration.includes("owner_restaurants"), "tenant ownership migration missing");
assert(migration.includes("review_assessment_written_answer"), "attempt trainer override missing");
assert(verification.includes("assessment_mcq_keys"), "extended verification missing answer-key checks");
assert(pkg.scripts?.test === "node test.mjs", "test script is not registered");

const savedScores = new Array(5).fill(null);
let aiCalls = 0;
let scoreSaves = 0;
let pauseCalls = 0;
let finalizeCalls = 0;
let failOnAiCall = null;
let requestNumber = 0;
const originalFetch = globalThis.fetch;
const originalEnv = Object.fromEntries(["KARIBU_SUPABASE_URL", "SUPABASE_URL", "SUPABASE_SERVICE_ROLE_KEY", "DEEPSEEK_API_KEY"].map(key => [key, process.env[key]]));
process.env.KARIBU_SUPABASE_URL = "https://supabase.invalid";
process.env.SUPABASE_SERVICE_ROLE_KEY = "test-service-key";
process.env.DEEPSEEK_API_KEY = "test-ai-key";
globalThis.fetch = async (url, options = {}) => {
  if (String(url).includes("api.deepseek.com")) {
    aiCalls += 1;
    if (aiCalls === failOnAiCall) return new Response(JSON.stringify({ error: "temporary" }), { status: 503 });
    return new Response(JSON.stringify({ choices: [{ message: { content: JSON.stringify({ score: 2, feedback: "Good response." }) } }] }), { status: 200 });
  }
  const name = new URL(String(url)).pathname.split("/").pop();
  const body = JSON.parse(options.body || "{}");
  if (name === "begin_assessment_marking") {
    requestNumber += 1;
    return new Response(JSON.stringify({
      success: true,
      module_id: 1,
      lease_token: `lease-${requestNumber}`,
      written_answers: savedScores.map((saved, question_index) => ({
        attempt_id: "attempt-test",
        question_index,
        answer: `Learner answer ${question_index + 1}`,
        ai_score: saved?.score ?? null,
        ai_feedback: saved?.feedback ?? null
      }))
    }), { status: 200 });
  }
  if (name === "renew_assessment_marking_lease") return new Response(JSON.stringify({ success: true }), { status: 200 });
  if (name === "save_assessment_marking_score") {
    savedScores[body.p_question_index] = { score: body.p_ai_score, feedback: body.p_ai_feedback };
    scoreSaves += 1;
    return new Response(JSON.stringify({ success: true, score: body.p_ai_score, feedback: body.p_ai_feedback }), { status: 200 });
  }
  if (name === "pause_assessment_marking") {
    pauseCalls += 1;
    return new Response(JSON.stringify({ success: true }), { status: 200 });
  }
  if (name === "finalize_assessment_marking") {
    finalizeCalls += 1;
    const complete = savedScores.every(Boolean);
    return new Response(JSON.stringify(complete
      ? { success: true, status: "passed", attempt_id: "attempt-test", mcq_score: 5, mcq_total: 5, written_score: 10, written_total: 10, overall_percent: 100, passed: true }
      : { success: false, error: "incomplete_assessment" }), { status: 200 });
  }
  throw new Error(`Unexpected mock RPC ${name}`);
};

async function callCompletion() {
  return completeAssessment(new Request("https://karibu.invalid/.netlify/functions/complete-assessment", {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: "Bearer staff-session-token" },
    body: JSON.stringify({ attempt_id: "attempt-test", questions: ["Q1", "Q2", "Q3", "Q4", "Q5"] })
  }));
}

try {
  let response = await callCompletion();
  assert(response.status === 200 && (await response.json()).passed === true, "successful scoring did not finalize the attempt");
  assert(scoreSaves === 5 && finalizeCalls === 1, "successful scoring did not persist all five answers before finalization");

  savedScores.fill(null);
  aiCalls = 0;
  scoreSaves = 0;
  pauseCalls = 0;
  finalizeCalls = 0;
  failOnAiCall = 3;
  response = await callCompletion();
  assert(response.status === 502 && scoreSaves === 2 && pauseCalls === 1, "a failed scoring request did not preserve prior scores and release its lease");

  failOnAiCall = null;
  const callsBeforeRetry = aiCalls;
  response = await callCompletion();
  assert(response.status === 200 && (await response.json()).passed === true, "resumed scoring did not complete the attempt");
  assert(aiCalls - callsBeforeRetry === 3 && scoreSaves === 5 && finalizeCalls === 1, "retry rescored saved answers instead of only scoring the remaining responses");
} finally {
  globalThis.fetch = originalFetch;
  for (const [key, value] of Object.entries(originalEnv)) {
    if (value === undefined) delete process.env[key];
    else process.env[key] = value;
  }
}

for (const file of ["build.mjs", "netlify/functions/mark-written-answer.mjs", "netlify/functions/complete-assessment.mjs"]) {
  await new Promise((resolve, reject) => {
    const child = spawn(process.execPath, ["--check", file], { stdio: "inherit" });
    child.on("error", reject);
    child.on("exit", (code) => code === 0 ? resolve() : reject(new Error(`${file} syntax check failed`)));
  });
}
console.log("Assessment and in-app Course Guide regression checks passed.");
