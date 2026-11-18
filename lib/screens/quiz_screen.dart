import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../config.dart';
import '../services/attempt_repository.dart';
import '../services/trivia_service.dart';
import '../state/quiz_controller.dart';
import 'dev_lab_screen.dart';
import 'history_screen.dart';

class QuizScreen extends StatefulWidget {
  const QuizScreen({super.key, required this.user});
  final User user;
  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  final _repo = AttemptRepository();
  late final QuizController c;

  @override
  void initState() {
    super.initState();
    c = QuizController(uid: widget.user.uid, repo: _repo, trivia: TriviaService());
    c.start();
  }

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  // --------------------------------------------------------------- widgets
  Widget _banner({
    required Color color,
    required IconData icon,
    required String title,
    required String detail,
    bool spinner = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        border: Border.all(color: color, width: 1.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        spinner
            ? const SizedBox(
                width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3))
            : Icon(icon, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 4),
            Text(detail),
          ]),
        ),
      ]),
    );
  }

  Widget _centered(List<Widget> children) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: children),
        ),
      );

  String _label(bool? v) => v == null ? '—' : (v ? 'True' : 'False');

  // ---------------------------------------------------------------- build
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Science Signal'),
            Text(widget.user.email ?? 'signed in',
                style: Theme.of(context).textTheme.bodySmall),
          ]),
          actions: [
            IconButton(
              tooltip: 'Saved attempts (server)',
              icon: const Icon(Icons.history),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => HistoryScreen(repo: _repo, uid: widget.user.uid))),
            ),
            if (kDevTools)
              IconButton(
                tooltip: 'DEV lab',
                icon: const Icon(Icons.bug_report),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => DevLabScreen(
                        repo: _repo, uid: widget.user.uid, roundId: c.roundId))),
              ),
            IconButton(
              tooltip: c.canSignOut ? 'Sign out' : 'Sign-out disabled while a save is unresolved',
              icon: const Icon(Icons.logout),
              onPressed: c.canSignOut ? () => FirebaseAuth.instance.signOut() : null,
            ),
          ],
        ),
        body: _body(context),
      ),
    );
  }

  Widget _body(BuildContext context) {
    switch (c.phase) {
      case QuizPhase.loading:
        return _centered(const [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Loading five science questions…'),
        ]);
      case QuizPhase.requestError:
        return _centered([
          const Icon(Icons.cloud_off, size: 48, color: Colors.red),
          const SizedBox(height: 12),
          Text(c.requestMessage ?? 'Could not load questions.', textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: c.cooldownLeft > 0 ? null : c.start,
            icon: const Icon(Icons.refresh),
            label: Text(c.cooldownLeft > 0 ? 'Retry in ${c.cooldownLeft}s' : 'Retry'),
          ),
        ]);
      case QuizPhase.playing:
        return _playing(context);
      default:
        return _result(context);
    }
  }

  // --------------------------------------------------------------- playing
  Widget _playing(BuildContext context) {
    final q = c.questions[c.index];
    final a = c.answers[c.index];
    final theme = Theme.of(context);
    Widget answerButton(String text, bool value) {
      final selected = a == value;
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: FilledButton.tonal(
            style: selected
                ? FilledButton.styleFrom(
                    side: BorderSide(color: theme.colorScheme.primary, width: 2))
                : null,
            onPressed: a == null ? () => c.answer(value) : null,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              if (selected) const Icon(Icons.radio_button_checked, size: 18),
              if (selected) const SizedBox(width: 6),
              Text(text, style: const TextStyle(fontSize: 18)),
            ]),
          ),
        ),
      );
    }

    return ListView(padding: const EdgeInsets.all(16), children: [
      Text('Question ${c.index + 1} of $kQuestionCount', style: theme.textTheme.titleMedium),
      const SizedBox(height: 8),
      LinearProgressIndicator(value: (c.index + (a != null ? 1 : 0)) / kQuestionCount),
      const SizedBox(height: 16),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(q.question, style: theme.textTheme.titleLarge),
        ),
      ),
      const SizedBox(height: 12),
      Row(children: [answerButton('True', true), answerButton('False', false)]),
      const SizedBox(height: 16),
      if (a != null)
        a == q.correctAnswer
            ? _banner(
                color: Colors.green.shade700,
                icon: Icons.check_circle,
                title: 'Correct! +1 point',
                detail: 'The answer is ${_label(q.correctAnswer)}.')
            : _banner(
                color: Colors.red.shade700,
                icon: Icons.cancel,
                title: 'Not quite. +0 points',
                detail: 'The correct answer is ${_label(q.correctAnswer)}.'),
      const SizedBox(height: 16),
      FilledButton(
        onPressed: a == null ? null : c.next,
        child: Text(c.index == kQuestionCount - 1 ? 'Finish' : 'Continue'),
      ),
      if (a == null)
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text('Choose True or False to continue.', textAlign: TextAlign.center),
        ),
    ]);
  }

  // ---------------------------------------------------------------- result
  Widget _result(BuildContext context) {
    final theme = Theme.of(context);
    final tail = c.roundId.length <= 4 ? c.roundId : '…${c.roundId.substring(c.roundId.length - 4)}';
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text('Your score: ${c.score} / $kQuestionCount', style: theme.textTheme.headlineMedium),
      Text('Round $tail', style: theme.textTheme.bodySmall),
      const SizedBox(height: 12),
      ..._status(context),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: c.unresolved ? null : c.replay,
        icon: const Icon(Icons.replay),
        label: const Text('Play again (new round)'),
      ),
      if (c.unresolved)
        const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Text('Replay and sign-out are disabled until this save is resolved.',
              style: TextStyle(fontSize: 12)),
        ),
      const Divider(height: 32),
      Text('Review', style: theme.textTheme.titleMedium),
      for (var i = 0; i < c.questions.length; i++)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: c.answers[i] == c.questions[i].correctAnswer
              ? Icon(Icons.check_circle, color: Colors.green.shade700)
              : Icon(Icons.cancel, color: Colors.red.shade700),
          title: Text('${i + 1}. ${c.questions[i].question}'),
          subtitle: Text('Your answer: ${_label(c.answers[i])}  •  '
              'Correct: ${_label(c.questions[i].correctAnswer)}  •  '
              '${c.answers[i] == c.questions[i].correctAnswer ? "+1" : "+0"}'),
        ),
    ]);
  }

  List<Widget> _status(BuildContext context) {
    final err = c.error;
    final retryInfo = Text('Retries used: ${c.retries}/${QuizController.maxRetries}',
        style: const TextStyle(fontSize: 12));
    switch (c.phase) {
      case QuizPhase.readyToSubmit:
        return [
          _banner(
              color: Colors.blue.shade700,
              icon: Icons.info,
              title: 'Round complete',
              detail: 'Not saved yet. Submit to write your score to Cloud Firestore.'),
          const SizedBox(height: 12),
          FilledButton.icon(
              onPressed: c.submit,
              icon: const Icon(Icons.cloud_upload),
              label: const Text('Submit score')),
        ];
      case QuizPhase.submitting:
        return [
          _banner(
              color: Colors.blue.shade700,
              icon: Icons.cloud_upload,
              title: 'Saving to Cloud Firestore…',
              detail: 'Submit is disabled until the write resolves.',
              spinner: true),
        ];
      case QuizPhase.verifying:
        return [
          _banner(
              color: Colors.blue.shade700,
              icon: Icons.cloud_sync,
              title: 'Write acknowledged. Verifying…',
              detail: 'Reading the exact document back from the server (not the cache).',
              spinner: true),
        ];
      case QuizPhase.cloudVerified:
        final r = c.verified;
        return [
          _banner(
              color: Colors.green.shade700,
              icon: Icons.verified,
              title: 'Cloud verified',
              detail: 'Server record ${r?.redactedId}: correctCount ${r?.correctCount}, '
                  'schemaVersion 1, variant B, category 17, 5 questions.\n'
                  'Server time: ${r?.submittedAt?.toDate().toLocal()}'),
        ];
      case QuizPhase.permissionDenied:
        if (c.commitAcknowledged) {
          return [
            _banner(
                color: Colors.orange.shade800,
                icon: Icons.cloud_queue,
                title: 'Write acknowledged; verification unavailable.',
                detail: 'Your result was committed and has NOT been deleted or saved a '
                    'second time. The server read failed: ${err?.label}'
                    '${err?.injected == true ? " (DEV-INJECTED)" : ""}. '
                    'Retry the server read for the same round ID.'),
            const SizedBox(height: 8),
            FilledButton.icon(
                onPressed: c.busy || c.retries >= QuizController.maxRetries
                    ? null
                    : c.retryVerification,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry server read (same ID)')),
            retryInfo,
          ];
        }
        return [
          _banner(
              color: Colors.red.shade700,
              icon: Icons.block,
              title: 'Save rejected by security rules',
              detail: 'The server refused the write, so nothing was saved. ${err?.message ?? ""}'),
        ];
      case QuizPhase.verificationUnavailable:
        return [
          _banner(
              color: Colors.orange.shade800,
              icon: Icons.cloud_queue,
              title: 'Write acknowledged; verification unavailable.',
              detail: 'Your result was committed and has NOT been deleted or saved a second '
                  'time. ${err?.label}${err?.injected == true ? " (DEV-INJECTED)" : ""}: '
                  '${err?.message}'),
          const SizedBox(height: 8),
          FilledButton.icon(
              onPressed: c.busy || c.retries >= QuizController.maxRetries
                  ? null
                  : c.retryVerification,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry server read (same ID)')),
          retryInfo,
        ];
      case QuizPhase.saveUnknown:
        return [
          _banner(
              color: Colors.orange.shade800,
              icon: Icons.help_outline,
              title: 'Save status unknown',
              detail: '${err?.label}: ${err?.message}\n'
                  'Do not submit again yet. First check the server for this round ID.'),
          const SizedBox(height: 8),
          if (!c.reconciledAbsent)
            FilledButton.icon(
                onPressed: c.busy || c.retries >= QuizController.maxRetries
                    ? null
                    : c.reconcile,
                icon: const Icon(Icons.search),
                label: const Text('Check server (reconcile)'))
          else ...[
            _banner(
                color: Colors.blue.shade700,
                icon: Icons.info,
                title: 'No server record for this ID',
                detail: 'Retrying with the SAME ID is safe: the create-once transaction '
                    'cannot create a duplicate.'),
            const SizedBox(height: 8),
            FilledButton.icon(
                onPressed: c.busy || c.retries >= QuizController.maxRetries
                    ? null
                    : c.retrySaveSameId,
                icon: const Icon(Icons.cloud_upload),
                label: const Text('Retry save (same ID)')),
          ],
          retryInfo,
        ];
      case QuizPhase.collision:
        return [
          _banner(
              color: Colors.red.shade700,
              icon: Icons.warning,
              title: 'Round ID collision',
              detail: '${err?.message}\nThe original record was not overwritten.'),
        ];
      default:
        return const [];
    }
  }
}
