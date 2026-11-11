import { getWrittenMarkingPrompt } from "./assessment-content.mjs";

const json = (status, body) => new Response(JSON.stringify(body), {
  status,
  headers: { "Content-Type": "application/json" }
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
  if (!attemptId) return json(400, { error: "missing_attempt_id" });

  try {
    const assessment = await rpc("get_assessment_attempt_for_staff", {
      p_attempt_id: attemptId,
      p_auth_token: token
    });
    if (!assessment?.success) return json(403, { error: assessment?.error || "unauthorized" });
    const attempt = assessment.attempt;
    const written = assessment.written_answers || [];
    if (written.length !== 5 || (assessment.mcq_answers || []).length !== 5) return json(409, { error: "incomplete_assessment" });
    const scores = [];
    for (const item of written.sort((a, b) => a.question_index - b.question_index)) {
      if (typeof item.answer !== "string" || !item.answer.trim()) return json(409, { error: "incomplete_written_answers" });
      const question = typeof input?.questions?.[item.question_index] === "string" ? input.questions[item.question_index] : `Written assessment question ${item.question_index + 1}`;
      scores.push({ question_index: item.question_index, ...(await markAnswer(getWrittenMarkingPrompt(attempt.module_id, item.question_index, question), item.answer)) });
    }
    const result = await rpc("complete_assessment_internal", {
      p_attempt_id: attemptId,
      p_auth_token: token,
      p_ai_scores: scores
    });
    return json(result?.success ? 200 : 409, result);
  } catch (error) {
    const message = error.message || "assessment_completion_failed";
    const status = message.includes("not_configured") || message.includes("supabase_server_credentials_missing") ? 503 : message.includes("unauthorized") ? 403 : 502;
    return json(status, { error: message });
  }
}
