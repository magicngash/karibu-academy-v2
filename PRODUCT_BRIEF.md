# Karibu Academy V2 — Product Brief

## Product summary

Karibu Academy is a restaurant staff-training platform designed to turn hospitality knowledge into repeatable service behaviour. Staff complete a structured ten-module learning programme, answer assessment questions, receive server-processed scores and AI-generated written-answer feedback, and progress through the course at their own pace.

The platform is currently configured for a restaurant pilot and supports owner/trainer oversight without exposing assessment answer keys or allowing staff-facing manipulation of results.

## Product goals

Karibu Academy is designed to:

- Give restaurant staff a clear, self-guided training journey.
- Build practical knowledge around guest care, menu knowledge, service delivery, teamwork, communication, and quality standards.
- Assess both knowledge and applied judgement.
- Provide useful, timely feedback after each module.
- Give managers and the owner/trainer visibility into progress and performance.
- Preserve an auditable record of attempts, scores, feedback, and completion.

## Users and roles

### Staff learner

Staff sign in to their restaurant account and complete available modules. They can resume from their last page, submit assessments, review their results, and retake failed modules.

### Restaurant manager

Managers can view staff progress, assessment attempts, written answers, scores, AI feedback, and audit history for their restaurant. The current product intentionally does not provide manual trainer score editing.

### Owner / trainer

The owner role represents the service operator and consulting trainer rather than the restaurant owner. The owner console manages restaurants, staff and managers, monthly reporting, restaurant-level overview analytics, and detailed staff progress.

## Learning programme

The current curriculum contains ten available modules:

1. Warm Welcomes, First Impressions, and Service Presence
2. Menu, Product, and Service Knowledge
3. Strategic Upselling Techniques
4. Precision Order-Taking, Service Delivery, and Coordination
5. Shift Management, Billing, and Guest Flow
6. Conflict Resolution and Service Recovery
7. Communication Skills for Customer Care
8. Emotional Intelligence and Customer Psychology
9. Teamwork, Accountability, and Shift Culture
10. Service Standards, Professionalism, and Quality Control

Each module includes lessons, objectives, practical examples, takeaways, a case study, five multiple-choice questions, and five written-answer questions.

Across the programme there are currently 50 MCQs and 50 written-answer questions, for 100 assessment questions in total.

## Assessment and marking

When a learner finishes a module, the platform:

1. Saves the learner's final answers.
2. Grades MCQs on the server using protected answer keys.
3. Sends written responses through the authenticated marking workflow.
4. Stores AI scores and feedback for each written response.
5. Combines MCQ and written results into a final module percentage.
6. Records the attempt as passed, failed, in progress, or awaiting marking.
7. Unlocks the next module after a pass.

The learner sees the final score and feedback as an assessment result. Provider-specific AI terminology is not part of the learner-facing experience.

The current pass mark is 80 percent. Failed modules can be retaken without a hard maximum. Every attempt receives its own attempt number and remains available for manager and owner review.

## Owner overview dashboard

The owner console includes a restaurant-level overview dashboard with:

- Total staff and staff who have started training.
- Modules completed versus possible module assignments.
- Overall completion rate.
- Total, scored, passed, failed, and awaiting-marking attempts.
- Average overall score.
- Average MCQ score.
- Module-by-module completion and performance.
- Question-level MCQ correctness and most-missed questions.
- Needs-attention items.
- Recent assessment activity.
- All-time, last-30-days, and current-month filters.
- CSV export for spreadsheet analysis.
- Browser print report that can be saved as a PDF.

The overview is read-only and links to detailed staff progress for individual investigation.

## Data protection and security approach

The product is designed around server-authoritative assessment and tenant-scoped access:

- Answer keys, rubrics, model answers, and samples are not included in the learner browser bundle.
- Assessment completion and progression are validated by database functions.
- AI marking requires authenticated, attempt-specific context.
- Owner and manager views are scoped to restaurants they are authorized to access.
- Assessment attempts and review activity are stored for auditability.
- Direct table access to protected assessment data is revoked from normal client roles.
- Owner analytics are exposed through read-only aggregate functions.

## Deployment requirements

The product uses a static frontend with Netlify functions and Supabase database functions.

Required deployment configuration includes:

- Public Supabase URL and publishable/anon key for the frontend.
- Server-side Supabase credentials for protected Netlify functions.
- DeepSeek API credentials for the current written-answer marking workflow.
- All database migrations applied in order, including the security, manager-review, owner-progress, and owner-overview migrations.

After changing Netlify environment variables, the site must be redeployed before the new values are used by deployed functions.

## Current product boundaries

The current version is a focused restaurant training pilot. It does not yet include:

- Manual manager score overrides in the active UI.
- A configurable maximum-retake policy.
- Automated end-to-end browser tests for every learner journey.
- A full question-authoring interface.
- Multi-language course delivery.
- Certificates or downloadable learner transcripts.
- Advanced cohort comparison or cross-restaurant benchmarking.
- Native mobile applications.

## Recommended next product steps

The next improvements should be driven by pilot usage:

1. Confirm the ten-module content and marking quality with real staff submissions.
2. Add browser-level regression tests for sign-in, resume, completion, AI marking, retakes, and next-module unlocking.
3. Add configurable pass marks and optional retake policies per restaurant.
4. Add trainer review tools only if operationally necessary, with a clear audit trail.
5. Improve the MCQ diagnostic view with module and question trend analysis.
6. Add configurable module release controls if the curriculum needs staged rollout.
7. Add certificates or completion summaries after the pilot requirements are stable.

## Product status

Karibu Academy V2 is suitable for a controlled restaurant pilot. The core ten-module learning flow, server-authoritative assessment, AI-assisted written-answer marking, repeat attempts, manager review, owner analytics, CSV export, and print-to-PDF reporting are implemented. Production rollout should include a final Supabase migration check, Netlify environment-variable verification, and a live pilot test using a real staff account.
