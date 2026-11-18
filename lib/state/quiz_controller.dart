import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../config.dart';
import '../dev_hooks.dart';
import '../models/trivia_question.dart';
import '../services/attempt_repository.dart';
import '../services/trivia_service.dart';

/// The state machine. signedOut and authError live in the auth gate / sign-in
/// screen; the controller owns everything from loading onward.
enum QuizPhase {
  signedOut,
  loading,
  playing,
  readyToSubmit,
  submitting,
  verifying,
  cloudVerified,
  authError,
  requestError,
  saveUnknown,
  permissionDenied,
  verificationUnavailable,
  collision,
}

class QuizController extends ChangeNotifier {
  QuizController({required this.uid, required this.repo, required this.trivia});

  final String uid;
  final AttemptRepository repo;
  final TriviaService trivia;

  static const int maxRetries = 5;

  QuizPhase phase = QuizPhase.loading;
  List<TriviaQuestion> questions = const [];
  List<bool?> answers = List<bool?>.filled(kQuestionCount, null);
  int index = 0;
  late String roundId = repo.newRoundId(uid);

  String? requestMessage;
  CloudError? error;
  bool commitAcknowledged = false;
  bool reconciledAbsent = false;
  AttemptRecord? verified;
  int retries = 0;
  int cooldownLeft = 0;

  Timer? _cooldownTimer;
  bool _disposed = false;
  bool _busy = false;
  bool _starting = false;
  int _frozenScore = 0;

  bool get busy => _busy;

  int get score {
    var s = 0;
    for (var i = 0; i < questions.length; i++) {
      if (answers[i] != null && answers[i] == questions[i].correctAnswer) s++;
    }
    return s;
  }

  /// True while a save/verification outcome is unresolved. Replay and sign-out
  /// are disabled in this state.
  bool get unresolved =>
      _busy ||
      switch (phase) {
        QuizPhase.submitting ||
        QuizPhase.verifying ||
        QuizPhase.saveUnknown ||
        QuizPhase.verificationUnavailable =>
          true,
        QuizPhase.permissionDenied => commitAcknowledged,
        _ => false,
      };

  bool get canSignOut => !unresolved;

  // ------------------------------------------------------------ round setup
  Future<void> start() async {
    if (_disposed || _starting || unresolved) return;
    _starting = true;
    _resetRound();
    _setPhase(QuizPhase.loading);
    try {
      final qs = await trivia.fetchRound();
      if (_disposed) return;
      questions = qs;
      DevLog.add('T02 evidence: encoded="${qs.first.rawQuestion}" '
          'decoded="${qs.first.question}"');
      _setPhase(QuizPhase.playing);
    } on RateLimitException catch (e) {
      _requestFailed('Open Trivia DB allows one request per 5 seconds. '
          'Try again in ${e.secondsLeft}s.');
    } on TriviaFormatException catch (e) {
      _requestFailed('The question data was not playable: ${e.message}');
    } on TimeoutException {
      _requestFailed('The question request timed out after 10 seconds.');
    } catch (e) {
      _requestFailed('Could not load questions. Check your connection. ($e)');
    } finally {
      _starting = false;
    }
  }

  void _resetRound() {
    roundId = repo.newRoundId(uid); // local id only, nothing is written
    answers = List<bool?>.filled(kQuestionCount, null);
    questions = const [];
    index = 0;
    error = null;
    requestMessage = null;
    commitAcknowledged = false;
    reconciledAbsent = false;
    verified = null;
    retries = 0;
    _frozenScore = 0;
  }

  void _requestFailed(String message) {
    if (_disposed) return;
    requestMessage = message;
    cooldownLeft = TriviaService.cooldownSeconds;
    _cooldownTimer?.cancel();
    if (cooldownLeft > 0) {
      _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        cooldownLeft = TriviaService.cooldownSeconds;
        if (cooldownLeft <= 0) t.cancel();
        _notify();
      });
    }
    _setPhase(QuizPhase.requestError);
  }

  // ---------------------------------------------------------------- playing
  void answer(bool value) {
    if (phase != QuizPhase.playing || answers[index] != null) return; // one answer only
    answers[index] = value;
    _notify();
  }

  void next() {
    if (phase != QuizPhase.playing || answers[index] == null) return;
    if (index < kQuestionCount - 1) {
      index++;
      _notify();
    } else {
      _setPhase(QuizPhase.readyToSubmit);
    }
  }

  // ------------------------------------------------------------ cloud steps
  Future<void> submit() async {
    if (phase != QuizPhase.readyToSubmit || _busy) return; // double-tap safe
    _frozenScore = score; // freeze: answers are final
    await _commit();
  }

  bool _isCurrent(String rid) =>
      !_disposed &&
      roundId == rid &&
      FirebaseAuth.instance.currentUser?.uid == uid;

  Future<void> _commit() async {
    final rid = roundId;
    _busy = true;
    _setPhase(QuizPhase.submitting);
    try {
      final outcome = await repo
          .commit(uid: uid, roundId: rid, correctCount: _frozenScore)
          .timeout(kNetworkTimeout);
      if (!_isCurrent(rid)) {
        DevLog.add('Stale commit response ignored (user or round changed).');
        return;
      }
      commitAcknowledged = true;
      DevLog.add('Commit acknowledged (${outcome.name}) for round ${_tail(rid)}');
      await _verify();
    } catch (e) {
      if (!_isCurrent(rid)) {
        DevLog.add('Stale commit error ignored (user or round changed).');
        return;
      }
      final err = CloudError.from(e);
      error = err;
      DevLog.add('Commit failed: ${err.label}');
      switch (err.kind) {
        case CloudErrorKind.permissionDenied:
          _setPhase(QuizPhase.permissionDenied); // commitAcknowledged is false
        case CloudErrorKind.collision:
          _setPhase(QuizPhase.collision);
        default:
          // timeout / offline / quota: we cannot know. Reconcile, do not blindly retry.
          _setPhase(QuizPhase.saveUnknown);
      }
    } finally {
      _busy = false;
      _notify();
    }
  }

  /// Never throws; maps every outcome to a phase.
  Future<void> _verify() async {
    final rid = roundId;
    _setPhase(QuizPhase.verifying);
    try {
      final rec = await repo
          .verifyFromServer(uid: uid, roundId: rid, expectedCorrect: _frozenScore)
          .timeout(kNetworkTimeout);
      if (!_isCurrent(rid)) {
        DevLog.add('Stale verification response ignored (user or round changed).');
        return;
      }
      verified = rec;
      error = null;
      retries = 0;
      DevLog.add('Cloud verified round ${_tail(rid)} score ${rec.correctCount}');
      _setPhase(QuizPhase.cloudVerified);
    } catch (e) {
      if (!_isCurrent(rid)) {
        DevLog.add('Stale verification error ignored (user or round changed).');
        return;
      }
      final err = CloudError.from(e);
      error = err;
      DevLog.add('Verification failed after real commit: ${err.label}');
      _setPhase(switch (err.kind) {
        CloudErrorKind.permissionDenied => QuizPhase.permissionDenied,
        CloudErrorKind.collision => QuizPhase.collision,
        _ => QuizPhase.verificationUnavailable,
      });
    }
  }

  /// Re-reads the SAME document from the server. Never writes.
  Future<void> retryVerification() async {
    if (!commitAcknowledged || _busy || retries >= maxRetries) return;
    if (phase != QuizPhase.permissionDenied &&
        phase != QuizPhase.verificationUnavailable) {
      return;
    }
    retries++;
    _busy = true;
    _notify();
    try {
      await _verify();
    } finally {
      _busy = false;
      _notify();
    }
  }

  /// After saveUnknown: ask the server what exists for the ORIGINAL round id.
  Future<void> reconcile() async {
    if (phase != QuizPhase.saveUnknown || _busy || retries >= maxRetries) return;
    retries++;
    final rid = roundId;
    _busy = true;
    _notify();
    try {
      final snap = await repo.readServer(uid, rid).timeout(kNetworkTimeout);
      if (!_isCurrent(rid)) return;
      if (!snap.exists) {
        reconciledAbsent = true;
        error = const CloudError(
            CloudErrorKind.notFound, 'Server has no record for this round ID yet.');
        DevLog.add('Reconcile: no server record for ${_tail(rid)}');
      } else {
        final rec = repo.validate(snap, expectedCorrect: _frozenScore);
        commitAcknowledged = true;
        verified = rec;
        error = null;
        retries = 0;
        DevLog.add('Reconcile: record found and verified for ${_tail(rid)}');
        _setPhase(QuizPhase.cloudVerified);
      }
    } catch (e) {
      if (!_isCurrent(rid)) return;
      final err = CloudError.from(e);
      error = err;
      DevLog.add('Reconcile failed: ${err.label}');
      if (err.kind == CloudErrorKind.collision) _setPhase(QuizPhase.collision);
    } finally {
      _busy = false;
      _notify();
    }
  }

  /// Safe only after reconcile proved nothing exists: same id, same frozen
  /// score, create-once transaction => cannot duplicate.
  Future<void> retrySaveSameId() async {
    if (phase != QuizPhase.saveUnknown ||
        !reconciledAbsent ||
        _busy ||
        retries >= maxRetries) {
      return;
    }
    retries++;
    reconciledAbsent = false;
    await _commit();
  }

  /// Replay: new questions, new id, clean state. Blocked while unresolved.
  Future<void> replay() async {
    if (unresolved) return;
    await start();
  }

  // ---------------------------------------------------------------- helpers
  String _tail(String id) => id.length <= 4 ? id : '…${id.substring(id.length - 4)}';

  void _setPhase(QuizPhase p) {
    phase = p;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _cooldownTimer?.cancel();
    super.dispose();
  }
}
