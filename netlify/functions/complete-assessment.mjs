import { getWrittenMarkingPrompt } from "./assessment-content.mjs";

const json = (status, body) => new Response(JSON.stringify(body), {
  status,
  headers: { "Content-Type": "application/json", "Cache-Control": "no-store" }
});

async function rpc(name, body) {
  const url = process.env.KARIBU_SUPABASE_URL || process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) throw new Error("supabase_server_credentials_missing");
  const response = await fetch(`${url}/rest/v1/rpc/${name}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      apikey: key,
      Authorization: `Bearer ${key}`
    },
    body: JSON.stringify(body)
  });
  const result = await response.json().catch(() => null);
  if (!response.ok) throw new Error(result?.message || result?.error || `${name}_failed`);
  return result;
}

async function markAnswer(prompt, answer) {
  const key = process.env.DEEPSEEK_API_KEY;
  if (!key) throw new Error("deepseek_not_configured");
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 30000);
  let response;
  try {
    response = await fetch("https://api.deepseek.com/chat/completions", {
      method: "POST",
      signal: controller.signal,
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${key}` },
      body: JSON.stringify({
        model: "deepseek-flash",
        temperature: 0,
        max_tokens: 250,
        response_format: { type: "json_object" },
        messages: [
          { role: "system", content: "Return only JSON with exactly score (integer 0, 1, or 2) and feedback (short string). Apply the rubric strictly." },
          { role: "user", content: JSON.stringify({ ...prompt, learner_answer: answer }) }
        ]
      })
    });
  } catch (error) {
    if (error?.name === "AbortError") throw new Error("marking_request_timeout");
    throw new Error("marking_request_failed");
  } finally {
    clearTimeout(timer);
  }

  const payload = await response.json().catch(() => null);
  if (!response.ok) throw new Error("marking_request_failed");
  let result;
  try { result = JSON.parse(payload?.choices?.[0]?.message?.content || ""); } catch (_) { throw new Error("invalid_marking_response"); }
  const score = Number(result.score);
  if (![0, 1, 2].includes(score) || typeof result.feedback !== "string") throw new Error("invalid_marking_result");
  return { score, feedback: result.feedback };
}

function safeErrorCode(error) {
  const message = error?.message || "assessment_completion_failed";
  return /^[a-z0-9_]{1,80}$/.test(message) ? message : "assessment_completion_failed";
}

function errorStatus(code) {
  if (code === "deepseek_not_configured" || code === "supabase_server_credentials_missing") return 503;
  if (code === "unauthorized") return 403;
  if (code === "incomplete_assessment" || code === "marking_lease_lost" || code === "already_processing") return 409;
  return 502;
}

export default async function handler(request) {
  if (request.method !== "POST") return json(405, { error: "method_not_allowed" });
  const auth = request.headers.get("authorization") || "";
  const token = auth.startsWith("Bearer ") ? auth.slice(7).trim() : "";
  if (!token) return json(401, { error: "missing_authentication" });
  let input;
  try { input = await request.json(); } catch (_) { return json(400, { error: "invalid_json" }); }
  const attemptId = typeof input?.attempt_id === "string" ? input.attempt_id : "";
  if (!attemptId) return json(400, { error: "missing_attempt_id" });

  let leaseToken = null;
  try {
    const begin = await rpc("begin_assessment_marking", {
      p_attempt_id: attemptId,
      p_auth_token: token
    });
    if (!begin?.success) return json(begin?.error === "unauthorized" ? 403 : 409, begin || { error: "marking_start_failed" });
    if (begin.finalized) return json(200, begin);
    if (begin.processing) {
      return json(202, {
        success: true,
        processing: true,
        status: "marking",
        scored_count: begin.scored_count || 0,
        total: begin.total || 5,
        lease_expires_at: begin.lease_expires_at
      });
    }

    leaseToken = begin.lease_token;
    const written = Array.isArray(begin.written_answers) ? begin.written_answers : [];
    if (!leaseToken || written.length !== 5) throw new Error("incomplete_assessment");
    const moduleId = Number(begin.module_id);
    if (!Number.isInteger(moduleId) || moduleId < 1) throw new Error("unknown_module");
    const scores = new Array(5);

    for (const item of written.sort((a, b) => a.question_index - b.question_index)) {
      const index = item.question_index;
      if (!Number.isInteger(index) || index < 0 || index > 4) throw new Error("invalid_marking_result");
      if (Number.isInteger(item.ai_score) && typeof item.ai_feedback === "string") {
        scores[index] = { question_index: index, score: item.ai_score, feedback: item.ai_feedback };
        continue;
      }
      if (typeof item.answer !== "string" || !item.answer.trim()) throw new Error("incomplete_written_answers");

      const lease = await rpc("renew_assessment_marking_lease", {
        p_attempt_id: attemptId,
        p_lease_token: leaseToken,
        p_auth_token: token
      });
      if (!lease?.success) throw new Error(lease?.error || "marking_lease_lost");

      const question = typeof input?.questions?.[index] === "string" ? input.questions[index] : `Written assessment question ${index + 1}`;
      const marked = await markAnswer(getWrittenMarkingPrompt(moduleId, index, question), item.answer);
      const saved = await rpc("save_assessment_marking_score", {
        p_attempt_id: attemptId,
        p_question_index: index,
        p_ai_score: marked.score,
        p_ai_feedback: marked.feedback,
        p_lease_token: leaseToken,
        p_auth_token: token
      });
      if (!saved?.success) throw new Error(saved?.error || "assessment_score_save_failed");
      scores[index] = { question_index: index, score: saved.score, feedback: saved.feedback };
    }

    if (scores.some(score => !score)) throw new Error("incomplete_marking_batch");
    const result = await rpc("finalize_assessment_marking", {
      p_attempt_id: attemptId,
      p_auth_token: token,
      p_lease_token: leaseToken
    });
    if (!result?.success) throw new Error(result?.error || "assessment_finalization_failed");
    return json(200, result);
  } catch (error) {
    const code = safeErrorCode(error);
    if (leaseToken) {
      try {
        await rpc("pause_assessment_marking", {
          p_attempt_id: attemptId,
          p_lease_token: leaseToken,
          p_error_code: code,
          p_auth_token: token
        });
      } catch (_) {
        // The lease expires automatically if the database is temporarily unavailable.
      }
    }
    return json(errorStatus(code), { error: code });
  }
}
