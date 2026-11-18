# State machine (names match `QuizPhase` in `lib/state/quiz_controller.dart`)

```mermaid
stateDiagram-v2
    [*] --> signedOut
    signedOut --> authError: sign-in fails (FirebaseAuthException shown)
    authError --> signedOut: user edits form
    signedOut --> loading: sign-in OK (new controller keyed by uid)
    loading --> playing: HTTP 200 + response_code 0 + 5 valid decoded results
    loading --> requestError: timeout / bad encoding / code != 0 / 4 results / rate limit
    requestError --> loading: user taps Retry (>= 5 s since last request)
    playing --> playing: answer (once) / Continue (needs selection)
    playing --> readyToSubmit: Continue on question 5 (score frozen)
    readyToSubmit --> submitting: Submit (single-flight guard)
    submitting --> verifying: transaction committed (commitAcknowledged = true)
    submitting --> permissionDenied: rules reject write (commitAcknowledged = false)
    submitting --> collision: same ID, different payload
    submitting --> saveUnknown: 10 s timeout / offline / unavailable / quota
    saveUnknown --> cloudVerified: reconcile finds matching server record
    saveUnknown --> submitting: reconcile finds NOTHING, retry SAME id
    saveUnknown --> collision: reconcile finds different payload
    verifying --> cloudVerified: server-only get: exists, 5 fixed fields, timestamp, no pending writes
    verifying --> permissionDenied: read denied (commit stays acknowledged)
    verifying --> verificationUnavailable: unavailable / resource-exhausted / unauthenticated / timeout
    permissionDenied --> verifying: Retry server read, SAME id (bounded)
    verificationUnavailable --> verifying: Retry server read, SAME id (bounded)
    cloudVerified --> loading: Play again (new round id)
    permissionDenied --> loading: Play again (only if write was rejected)
    collision --> loading: Play again
```

Guards: replay + sign-out are disabled while `unresolved`
(`submitting`, `verifying`, `saveUnknown`, `verificationUnavailable`, and `permissionDenied` after a real commit).
Every async callback checks `_isCurrent(roundId)` (same UID + same round, controller not disposed) before touching state.

Render in VS Code with the "Markdown Preview Mermaid Support" extension, or paste into https://mermaid.live
and export PNG for your evidence document. (Add your own variable names if you rename anything.)
