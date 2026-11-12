# Karibu Academy V2 — Testing Notes

This is the updated restaurant staff-training app. The main changes and features to know before testing are below.

## What to test

### 1. Staff learner portal

- Staff can sign in and resume from their last page instead of restarting the introduction.
- There are 10 training modules covering guest service, menu knowledge, upselling, service delivery, billing, complaints, communication, emotional intelligence, teamwork, and service standards.
- Each module contains lessons, examples, a case study, five multiple-choice questions, and five written-answer questions.
- Staff can complete modules in sequence. Passing a module unlocks the next one.
- The **Finish module** button saves the answers and shows visible progress while the result is being processed.
- The final result combines server-graded MCQs with AI-assessed written answers.
- The learner sees the final percentage, pass/fail result, and written-answer feedback.
- Failed modules can be retaken. There is currently no hard retake limit.

### 2. Manager view

Managers can view:

- Staff completion progress across all 10 modules.
- Module scores and overall results.
- Multiple attempts, including retakes.
- Written answers and AI-generated feedback.
- Assessment history and audit events.

The current version is read-only for scores. Managers do not manually change marks.

### 3. Owner console

The owner console is for the software owner/trainer and includes:

- Restaurant and staff management.
- Manager access management.
- Monthly reporting.
- **Overview** dashboard with total staff, completion rate, attempts, passes, failures, average scores, and pending marking.
- Module-by-module performance and MCQ question analysis.
- Needs-attention items and recent activity.
- **Staff progress** drill-down for individual staff, modules, attempts, written answers, and feedback.

The overview supports **All time**, **Last 30 days**, and **This month** filters.

### 4. Reports and exports

From the owner Overview page:

- **Download CSV** exports summary metrics, module performance, and MCQ question results.
- **Print / save PDF** opens a formatted report in the browser print dialog. Choose **Save as PDF**.

## Suggested test journey

1. Create or use a staff account such as Alana.
2. Sign in and confirm the learner resumes correctly after signing out and back in.
3. Complete one module, including all MCQs and written answers.
4. Click **Finish module** and confirm that saving/marking progress is visible.
5. Confirm that the final score and AI written-answer feedback appear.
6. Try a failed module again using **Retake exam**.
7. Confirm the next module unlocks after passing.
8. Sign in to the manager view and confirm the attempt, score, answers, and feedback are visible.
9. Open the owner console, select **Overview**, and test the filters and exports.
10. Open **Staff progress** and confirm the same attempts and results can be investigated in detail.

## Important testing notes

- AI marking requires the deployed DeepSeek API key and server credentials to be configured in Netlify.
- Database migrations must be applied, including the latest owner overview migration.
- A completed score may take a short time while written answers are being assessed.
- If a result does not appear, check the visible completion message and the browser console/network response.
