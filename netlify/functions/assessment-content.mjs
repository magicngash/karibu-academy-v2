// Server-only assessment guidance. Do not import this file from browser code.
const MODULE_GUIDANCE = {
  1: "Warm welcomes, first impressions, entrance awareness, professional presence, guest mood, and managing arrivals.",
  2: "Menu knowledge, ingredients, preparation methods, substitutions, dietary needs, allergy safety, and explaining value.",
  3: "Product knowledge, guest preferences, recommendations, seasonal products, premium alternatives, and complementary pairings.",
  4: "Safe carrying and serving, clearing tables, service timing, coordinating orders, and resetting tables for the next guest.",
  5: "Cash and card safety, bill accuracy, payment disputes, waiting guests, transparency, and professional payment handling.",
  6: "Complaint recovery, empathy, delays, responsibility, follow-up, calm communication, and learning from repeated complaints.",
  7: "Clear language, operational limitations, adapting communication, avoiding jargon, and combining verbal and non-verbal reassurance.",
  8: "Adapting service interaction, recognising stress, empathy, disappointment, emotional awareness, and building guest trust.",
  9: "Shift handovers, internal communication, ownership of mistakes, escalation, reporting lines, and supporting colleagues.",
  10: "Readiness checks, workstation organisation, quality checks, self-auditing, supervisor feedback, and consistent standards."
};

export function getWrittenMarkingPrompt(moduleId, questionIndex, question) {
  const guidance = MODULE_GUIDANCE[moduleId];
  if (!guidance) throw new Error("unknown_module");
  return {
    question,
    rubric: `Assess this Module ${moduleId} written answer about ${guidance} Award 2/2 when the answer directly addresses the question with accurate, safe and practical actions relevant to the topic. Award 1/2 when it shows partial understanding but omits an important point or practical step. Award 0/2 when it is incorrect, unsafe, irrelevant, evasive or unanswered. Question number: ${questionIndex + 1}.`,
    sample: `A strong answer directly answers the question, applies the Module ${moduleId} service standard, explains the practical action, and protects guest experience, safety and trust where relevant.`
  };
}

export function getModuleGuidance(moduleId) {
  return MODULE_GUIDANCE[moduleId] || null;
}
