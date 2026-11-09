const json = (statusCode, body) => new Response(JSON.stringify(body), {
  status: statusCode,
  headers: { "Content-Type": "application/json" }
});

export default async function handler(request) {
  if (request.method !== "POST") return json(405, { error: "method_not_allowed" });
  if (!process.env.DEEPSEEK_API_KEY) return json(500, { error: "deepseek_not_configured" });

  let input;
  try { input = await request.json(); } catch (_) { return json(400, { error: "invalid_json" }); }
  const { question, rubric, sample, answer } = input || {};
  if (![question, rubric, sample, answer].every(value => typeof value === "string" && value.trim())) {
    return json(400, { error: "missing_marking_input" });
  }

  const response = await fetch("https://api.deepseek.com/chat/completions", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${process.env.DEEPSEEK_API_KEY}`
    },
    body: JSON.stringify({
      model: "deepseek-flash",
      temperature: 0,
      max_tokens: 250,
      response_format: { type: "json_object" },
      messages: [
        {
          role: "system",
          content: "You are a fair restaurant training assessor. Return only valid JSON with exactly two fields: score (integer 0, 1, or 2) and feedback (short string). Use the rubric strictly. Do not award credit for irrelevant text."
        },
        {
          role: "user",
          content: JSON.stringify({ question, rubric, sample_answer: sample, learner_answer: answer })
        }
      ]
    })
  });
  const payload = await response.json().catch(() => null);
  if (!response.ok) return json(502, { error: "deepseek_request_failed", details: payload?.error?.message || "DeepSeek request failed." });

  let result;
  try { result = JSON.parse(payload?.choices?.[0]?.message?.content || ""); } catch (_) { return json(502, { error: "invalid_deepseek_response" }); }
  const score = Number(result.score);
  if (![0, 1, 2].includes(score) || typeof result.feedback !== "string") return json(502, { error: "invalid_marking_result" });
  return json(200, { score, feedback: result.feedback });
}
