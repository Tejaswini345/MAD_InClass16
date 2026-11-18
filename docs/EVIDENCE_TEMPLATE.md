# ICA16_B_YourName — Evidence document template
Copy into Word and save as `ICA16_B_YourName.docx`. Replace every <…> with YOUR real run data.

**Name / ID:** Tejaswini Kolliboni / 003037935   **Level:** Graduate
**Device/platform:** <emulator model, Android API>   **Build:** <flutter --version, APK date>
**App commit:** <git rev-parse --short HEAD>   **DEV_TOOLS in APK:** <yes/no>
**AI assistance disclosure:** <tool, date, what you used it for, what you changed/tested yourself>

## Four development checkpoints (screenshot + commit hash each)
1. <Firebase project + sign-in working>
2. <OpenTDB fetch/decoding + validation>
3. <Quiz state machine + review>
4. <Transaction + server read + failure recovery>
Failed-first correction: <what failed first, how you fixed it, commit>

## State diagram
<paste exported docs/STATE_DIAGRAM.md diagram, annotated with your names>

## Test records (one block per test)
Fields: ID · Precondition · Action · Expected · Actual · Pass/Fail · Evidence ref · Timestamp · Commit · Round-ID suffix (last 4 only)

| ID | Precondition | Action | Expected | Actual | P/F | Evidence | Time | Round suffix |
|---|---|---|---|---|---|---|---|---|
| T01 | | | | | | | | |
| T02 | | | | | | | | |
| T03 | | | | | | | | |
| T04 | | | | | | | | |
| T05 | | | | | | | | |
| T06 | | | | | | | | |
| T07 | | | | | | | | |
| T08 | | | | | | | | |
| T09 | | | | | | | | |
| T10 | | | | | | | | |
| T11 | | | | | | | | |
| T12 | | | | | | | | |
| G01 | | | | | | | | |
| G02 | | | | | | | | |
| G03 | | | | | | | | |

Redact: passwords, tokens, full UIDs/round IDs if you prefer (keep suffix). Include console + in-app server-read screenshots.

## Six answers (120–180 words each, with an app-specific reference)
Write these yourself from your own run. Pointers to YOUR project:

1. **Decode the evidence** — Use the "T02 evidence" line from the DEV lab log. Reference `parseTriviaResponse` in `trivia_validator.dart`; the URL uses `encode=url3986`, which is RFC 3986 percent-encoding. Unit test "HTML entities are NOT unescaped" shows the difference.
2. **Separate outcomes** — T09. Reference `commitAcknowledged` and the two code paths in `QuizController._commit` / `_verify`; which evidence permits "Write acknowledged; verification unavailable" vs "Cloud verified" (server-only get + checks in `AttemptRepository.validate`).
3. **Identity and collision** — `AttemptRepository.commit`: same ID + same five fields → `reusedExisting`; same ID + different score → `CloudError.collision`; new round = new `newRoundId`. Cite G01.
4. **Access is not truth** — T10 evidence for B denied; rules `validAttempt()` only checks range, so owner can write any 0–5. Sketch: authenticated backend (Cloud Function) holds the questions/answers, scores, writes with Admin SDK, rules deny client writes.
5. **Critique the AI** — Prompt + tool + date, short excerpt, two claims you TESTED, ≥1 flaw, your revised design. Or critique the instructor candidate: public DB (breaks authorization), new ID + re-save (duplicates), cached success (not server proof), admin key in app (credential leak). Least-privilege revision = retry the SAME-ID server read only (`retryVerification`).
6. **Defend your UX** — Screenshot the orange "Write acknowledged; verification unavailable." banner vs red "Save rejected" banner; cue = icon + color + text; failed-first test you corrected.

## Graduate extensions (150–220 words each)
- **G-1 Competing operations:** diagram two clients A/B, same ID, interleaving; transaction serialises on the document; winner = first committed server write; loser sees `collision`. Cite G01/G02 log lines.
- **G-2 Server-authoritative scoring:** authenticated callable/HTTPS API with ID token verification, server holds answer key, one-time round tokens (replay protection), Admin SDK writes, rules `allow write: if false`. Remaining threats: bot answering, stolen tokens, answer-key leakage via OpenTDB itself, rate abuse.
- **G-3 Transaction vs idempotency endpoint:** compare cost (reads+writes), latency (client↔Firestore vs extra hop), contention (single-doc), correctness (client trust vs server trust).

## Reproduce restart retrieval (instructor)
<Steps: install APK → sign in with the test account supplied privately → history icon → same round suffix → verify icon.> No passwords here.
