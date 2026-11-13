import { readFile } from "node:fs/promises";
import { spawn } from "node:child_process";

const read = (file) => readFile(file, "utf8");
const assert = (condition, message) => {
  if (!condition) throw new Error(message);
};

const index = await read("index.html");
const endpoint = await read("netlify/functions/mark-written-answer.mjs");
const migration = await read("08_security_and_review_fixes.sql");
const verification = await read("09_security_verification.sql");
const pkg = JSON.parse(await read("package.json"));

assert(!/\bcorrect\s*:/.test(index), "frontend still contains MCQ answer keys");
assert(!/\bmodelAnswer\s*:/.test(index), "frontend still contains case-study model answers");
assert(!/\brubric\s*:/.test(index), "frontend still contains written-answer rubrics");
assert(!/\bsample\s*:/.test(index), "frontend still contains written-answer samples");
assert(index.includes('callRpc("save_assessment_written_answer"'), "written answers are not saved against the active assessment attempt");
assert(index.includes('role: "alert"') && index.includes("Retry save"), "written-answer save failures are not visible and retryable");
assert(index.includes("not been confirmed in the server yet"), "locally cached answers may be mistaken for server-persisted answers");
assert(index.includes("marking_request_failed") && index.includes("incomplete_assessment"), "AI-marking and incomplete-assessment errors are not mapped for learners");
assert(index.includes("don’t tap Complete Module again") && index.includes('"aria-live"'), "module completion does not announce a clear wait message accessibly");
assert(index.includes('"Processing…"') && index.includes("completionStarted.current"), "module completion does not prevent repeat taps or show processing feedback");
assert(endpoint.includes('missing_authentication'), "AI endpoint does not require authentication");
assert(endpoint.includes('manager_assessment_answer_context'), "AI endpoint does not use attempt-specific context");
assert(endpoint.includes('save_attempt_ai_mark'), "AI endpoint does not persist attempt-specific marks");
assert(migration.includes("server_authoritative_completion"), "progression migration missing completion protection");
assert(migration.includes("module_locked"), "progression migration missing module locking");
assert(migration.includes("owner_restaurants"), "tenant ownership migration missing");
assert(migration.includes("review_assessment_written_answer"), "attempt trainer override missing");
assert(verification.includes("assessment_mcq_keys"), "extended verification missing answer-key checks");
assert(pkg.scripts?.test === "node test.mjs", "test script is not registered");

for (const file of ["build.mjs", "netlify/functions/mark-written-answer.mjs", "netlify/functions/complete-assessment.mjs"]) {
  await new Promise((resolve, reject) => {
    const child = spawn(process.execPath, ["--check", file], { stdio: "inherit" });
    child.on("error", reject);
    child.on("exit", (code) => code === 0 ? resolve() : reject(new Error(`${file} syntax check failed`)));
  });
}
console.log("Static security checks passed.");
