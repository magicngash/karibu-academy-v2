// Suggested answers for the Case Study & Role Play guide questions.
// The guidance follows Customer_Service_Case_Study_QA.pdf and the module lessons.
const CASE_STUDY_ANSWERS = {
  1: [
    "Keep part of your attention on the entrance while finishing the current task. Make eye contact, smile, and acknowledge each group within 30 seconds; then greet and seat them in turn. This prevents anyone from feeling invisible, even when the host is carrying a tray.",
    "Stand upright with relaxed shoulders, keep an open stance, make brief eye contact, smile, and use a calm tone. A small nod or raised finger can acknowledge the next group while you finish the immediate task without creating panic."
  ],
  2: [
    "Guessing can expose the guest to a serious allergic reaction, cross-contact, or an unsafe ingredient. It also damages trust: once the guest learns the answer was guessed, they may doubt every other safety assurance from the restaurant.",
    "It is honest, specific, and action-oriented. The server does not invent an answer; they take responsibility for verifying it with the kitchen and return with accurate information. That protects the guest and makes the service feel reliable."
  ],
  3: [
    "Read the guest's pace and priorities first. If the diner is rushed, offer one concise, relevant recommendation only when there is a natural opening, then return focus to fast, accurate service instead of forcing a sales pitch.",
    "Accepting a no respectfully shows that the recommendation was meant to help, not pressure. It protects trust, keeps the interaction pleasant, and leaves the diner more open to future suggestions."
  ],
  4: [
    "Write the order and repeat the key details back, especially modifiers, allergies, quantities, and sides. Confirmation catches misunderstandings before the ticket reaches the kitchen, reducing waste, remakes, delays, and guest frustration.",
    "Clear, timely communication gives the kitchen an accurate ticket and lets the front of house know what was confirmed. When a change or risk is important, communicate it directly as well as documenting it so the whole team can keep service moving."
  ],
  5: [
    "An on-screen payment attempt is not proof that the transaction succeeded. Wait for the authorised SMS or system confirmation, verify the amount and reference, and escalate through the approved process if confirmation does not arrive before releasing the order or closing the bill.",
    "Confirm the payment outcome, thank the guest, explain any next step clearly, and close with a warm farewell. This reassures the guest that the transaction and service request were completed rather than leaving uncertainty at the final interaction."
  ],
  6: [
    "Empathise first, acknowledge the impact, apologise for the experience, and explain the immediate corrective action. A calm response lowers defensiveness and creates space to solve the problem.",
    "Escalate when the guest remains upset after the first recovery attempt, requests a manager, compensation or policy exception, or when the issue involves safety, payment, discrimination, or a delay the server cannot resolve. Keep the supervisor informed with the facts and actions already taken."
  ],
  7: [
    "Listen without interrupting, clarify the request, repeat back the important details, and record them accurately. Confirmation prevents wrong items, missed modifiers, and unnecessary corrections.",
    "Positive phrasing focuses on what can be done and gives the guest a helpful next step. Explain the closest available option and why it meets the need, while staying accurate about limits."
  ],
  8: [
    "Use the guest's pace, questions, facial expression, and uncertainty to judge how much help is needed. Offer two or three clear options with brief descriptions, ask a simple preference question, and give them time without making them feel rushed.",
    "Emotional intelligence helps the server notice anxiety, respond with patience, and adjust tone and information rather than treating every guest the same. The guest feels respected, making it easier to reach a decision and recover if something goes wrong."
  ],
  9: [
    "Ownership builds accountability. The server should acknowledge the error privately, inform the supervisor, correct the guest impact, and learn from the cause instead of blaming the kitchen publicly. This protects teamwork and models integrity.",
    "A thorough handover passes on table status, VIP details, dietary requests, promised timings, outstanding bills, and who owns each follow-up. The incoming colleague records and accepts responsibility, preventing information gaps when shifts change."
  ],
  10: [
    "Clean grooming and an orderly station are visible evidence of care, hygiene, and control. A messy uniform or cluttered work area can make guests question food safety, attention to detail, and whether the rest of the service will be handled professionally.",
    "Self-auditing identifies gaps between the expected standard and what actually happened. Supervisor feedback adds an outside view; accepting it, choosing a corrective habit, and checking progress turns feedback into continuous improvement."
  ]
};

Object.entries(CASE_STUDY_ANSWERS).forEach(([moduleId, answers]) => {
  const questions = window.TRAINING_MODULE_DATA[moduleId]?.caseStudy?.questions || [];
  questions.forEach((question, index) => { question.answer = answers[index]; });
});
