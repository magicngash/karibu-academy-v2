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
    headers: { "Content-Type": "application/json", apikey: key, Authorization: `Bearer ${key}` },
    body: JSON.stringify(body)
  });
  const result = await response.json().catch(() => null);
  if (!response.ok) throw new Error(result?.message || result?.error || `${name}_failed`);
  return result;
}

async function mark(prompt, answer) {
  const key = process.env.DEEPSEEK_API_KEY;
  if (!key) throw new Error("deepseek_not_configured");
  const response = await fetch("https://api.deepseek.com/chat/completions", {
    method: "POST",
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
  const payload = await response.json().catch(() => null);
  if (!response.ok) throw new Error(payload?.error?.message || "marking_request_failed");
  let result;
  try { result = JSON.parse(payload?.choices?.[0]?.message?.content || ""); } catch (_) { throw new Error("invalid_marking_response"); }
  const score = Number(result.score);
  if (![0, 1, 2].includes(score) || typeof result.feedback !== "string") throw new Error("invalid_marking_result");
  return { score, feedback: result.feedback };
}

export default async function handler(request) {
  if (request.method !== "POST") return json(405, { error: "method_not_allowed" });
  const auth = request.headers.get("authorization") || "";
  const token = auth.startsWith("Bearer ") ? auth.slice(7).trim() : "";
  if (!token) return json(401, { error: "missing_authentication" });

  let input;
  try { input = await request.json(); } catch (_) { return json(400, { error: "invalid_json" }); }
  const attemptId = typeof input?.attempt_id === "string" ? input.attempt_id : "";
  const questionIndex = Number(input?.question_index);
  const question = typeof input?.question === "string" ? input.question.trim() : "";
  if (!attemptId || !Number.isInteger(questionIndex) || questionIndex < 0 || questionIndex > 4 || !question) {
    return json(400, { error: "invalid_marking_request" });
  }

  try {
    const context = await rpc("manager_assessment_answer_context", {
      p_attempt_id: attemptId,
      p_question_index: questionIndex,
      p_auth_token: token
    });
    if (!context?.attempt || !context?.answer?.answer) return json(403, { error: "unauthorized_or_answer_not_found" });
    const prompt = getWrittenMarkingPrompt(context.attempt.module_id, questionIndex, question);
    const result = await mark(prompt, context.answer.answer);
    const saved = await rpc("save_attempt_ai_mark", {
      p_attempt_id: attemptId,
      p_question_index: questionIndex,
      p_ai_score: result.score,
      p_ai_feedback: result.feedback,
      p_auth_token: token
    });
    if (!saved?.success) return json(409, saved);
    return json(200, result);
  } catch (error) {
    const message = error.message || "manager_marking_failed";
    const status = message.includes("unauthorized") ? 403 : message.includes("not_configured") ? 503 : 502;
    return json(status, { error: message });
  }
}
