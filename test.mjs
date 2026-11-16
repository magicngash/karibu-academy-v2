import { readFile } from "node:fs/promises";
import { spawn } from "node:child_process";
import completeAssessment from "./netlify/functions/complete-assessment.mjs";

const read = (file) => readFile(file, "utf8");
const assert = (condition, message) => {
  if (!condition) throw new Error(message);
};

const index = await read("index.html");
const endpoint = await read("netlify/functions/mark-written-answer.mjs");
const completionEndpoint = await read("netlify/functions/complete-assessment.mjs");
const markingMigration = await read("15_assessment_marking_progress.sql");
const resumeMigration = await read("16_training_resume.sql");
const attemptAccessMigration = await read("17_assessment_attempt_rpc_access.sql");
const retakeMigration = await read("18_atomic_retake_attempt.sql");
const blankRetakeMigration = await read("19_recover_blank_retake_attempt.sql");
const migration = await read("08_security_and_review_fixes.sql");
const verification = await read("09_security_verification.sql");
const pkg = JSON.parse(await read("package.json"));
const retakeHandler = index.slice(index.indexOf("async function retake()"), index.indexOf("function persistWrittenCache"));
const resumeTrainingHandler = index.slice(index.indexOf("async function handleResumeTraining()"), index.indexOf("async function retryResumeLookup"));
const blankRetakeHelper = index.slice(index.indexOf("function isBlankUnstartedRetake(resume)"), index.indexOf("function getResumeLocationLabel(resume)"));

assert(!/\bcorrect\s*:/.test(index), "frontend still contains MCQ answer keys");
assert(!/\bmodelAnswer\s*:/.test(index), "frontend still contains case-study model answers");
assert(!/\brubric\s*:/.test(index), "frontend still contains written-answer rubrics");
assert(!/\bsample\s*:/.test(index), "frontend still contains written-answer samples");
assert(index.includes('callRpc("save_assessment_written_answer"'), "written answers are not saved against the active assessment attempt");
assert(index.includes('role: "alert"') && index.includes("Retry save"), "written-answer save failures are not visible and retryable");
assert(index.includes("Draft saved to your account") && index.includes('callRpc("save_assessment_written_draft"'), "written-answer drafts are not visibly confirmed after server autosave");
assert(index.includes('window.addEventListener("pagehide", saveDraftOnPageHide)') && index.includes("keepalive: true"), "the latest written draft is not flushed when the learner leaves the page");
assert(index.includes('callRpc("get_latest_training_resume"') && index.includes("getResumeLocationLabel") && index.includes('"Resume Training"'), "signed-in landing does not offer a server-backed resume action");
assert(index.includes("resumeLookupError") && index.includes("onRetryResume") && index.includes("Check again"), "a failed resume lookup is hidden instead of retryable");
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
console.log("Assessment flow regression checks passed.");
