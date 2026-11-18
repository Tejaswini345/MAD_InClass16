import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../config.dart';
import '../dev_hooks.dart';

enum CloudErrorKind {
  permissionDenied,
  unavailable,
  resourceExhausted,
  unauthenticated,
  timeout,
  collision,
  notFound,
  mismatch,
  other,
}

/// One error type for the whole UI so each failure is shown distinctly.
class CloudError implements Exception {
  const CloudError(this.kind, this.message, {this.injected = false});
  final CloudErrorKind kind;
  final String message;
  final bool injected;

  String get label => switch (kind) {
        CloudErrorKind.permissionDenied => 'Permission denied',
        CloudErrorKind.unavailable => 'Service unavailable / offline',
        CloudErrorKind.resourceExhausted => 'Quota exhausted (resource-exhausted)',
        CloudErrorKind.unauthenticated => 'Signed out (unauthenticated)',
        CloudErrorKind.timeout => 'Timed out',
        CloudErrorKind.collision => 'Round ID collision',
        CloudErrorKind.notFound => 'Not found on server',
        CloudErrorKind.mismatch => 'Server record does not match',
        CloudErrorKind.other => 'Unexpected error',
      };

  static CloudError from(Object e) {
    if (e is CloudError) return e;
    if (e is TimeoutException) {
      return const CloudError(CloudErrorKind.timeout,
          'No answer within 10 s. The underlying operation may still finish.');
    }
    if (e is FirebaseException) {
      final msg = '${e.code}: ${e.message ?? ''}'.trim();
      switch (e.code) {
        case 'permission-denied':
          return CloudError(CloudErrorKind.permissionDenied, msg);
        case 'unavailable':
          return CloudError(CloudErrorKind.unavailable, msg);
        case 'resource-exhausted':
          return CloudError(CloudErrorKind.resourceExhausted, msg);
        case 'unauthenticated':
          return CloudError(CloudErrorKind.unauthenticated, msg);
        case 'deadline-exceeded':
          return CloudError(CloudErrorKind.timeout, msg);
        default:
          return CloudError(CloudErrorKind.other, msg);
      }
    }
    return CloudError(CloudErrorKind.other, e.toString());
  }
}

enum CommitOutcome { created, reusedExisting }

class AttemptRecord {
  const AttemptRecord({
    required this.roundId,
    required this.correctCount,
    required this.submittedAt,
  });
  final String roundId;
  final int correctCount;
  final Timestamp? submittedAt;

  String get redactedId =>
      roundId.length <= 4 ? roundId : '…${roundId.substring(roundId.length - 4)}';
}

class AttemptRepository {
  AttemptRepository({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;
  final FirebaseFirestore _db;

  static const _keys = {
    'schemaVersion', 'variant', 'categoryId',
    'questionCount', 'correctCount', 'submittedAt',
  };

  CollectionReference<Map<String, dynamic>> _attempts(String uid) =>
      _db.collection('users').doc(uid).collection('attempts');

  /// users/{uid}/attempts/{roundId}
  DocumentReference<Map<String, dynamic>> refFor(String uid, String roundId) =>
      _attempts(uid).doc(roundId);

  /// Generates an id locally. This does NOT create a server record.
  String newRoundId(String uid) => _attempts(uid).doc().id;

  /// The exact six-field Class B document.
  Map<String, dynamic> validData(int correctCount) => {
        'schemaVersion': 1,
        'variant': 'B',
        'categoryId': 17,
        'questionCount': 5,
        'correctCount': correctCount,
        'submittedAt': FieldValue.serverTimestamp(),
      };

  bool _sameFixedFields(Map<String, dynamic> d, int correct) =>
      d['schemaVersion'] == 1 &&
      d['variant'] == 'B' &&
      d['categoryId'] == 17 &&
      d['questionCount'] == 5 &&
      d['correctCount'] == correct;

  /// Create-once transaction: read first; absent -> set; present & same five
  /// fields -> reuse; present & different -> collision (never overwrite).
  /// NOTE: no ID generation, UI changes or other side effects in the callback,
  /// because Firestore may run it more than once.
  Future<CommitOutcome> commit({
    required String uid,
    required String roundId,
    required int correctCount,
  }) {
    final ref = refFor(uid, roundId);
    final payload = validData(correctCount); // frozen before the transaction
    return _db.runTransaction<CommitOutcome>((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) {
        tx.set(ref, payload);
        return CommitOutcome.created;
      }
      final data = snap.data()!;
      if (_sameFixedFields(data, correctCount)) return CommitOutcome.reusedExisting;
      throw const CloudError(CloudErrorKind.collision,
          'This round ID already holds a different payload. Not overwritten.');
    });
  }

  /// Server-only read (never cache).
  Future<DocumentSnapshot<Map<String, dynamic>>> readServer(String uid, String roundId) =>
      refFor(uid, roundId).get(const GetOptions(source: Source.server));

  /// Checks that a server snapshot is the expected committed record.
  AttemptRecord validate(DocumentSnapshot<Map<String, dynamic>> snap,
      {required int expectedCorrect}) {
    if (!snap.exists) {
      throw const CloudError(CloudErrorKind.notFound, 'No document on the server.');
    }
    if (snap.metadata.isFromCache) {
      throw const CloudError(CloudErrorKind.mismatch, 'Snapshot came from cache.');
    }
    if (snap.metadata.hasPendingWrites) {
      throw const CloudError(CloudErrorKind.mismatch, 'Snapshot has pending writes.');
    }
    final d = snap.data()!;
    final keys = d.keys.toSet();
    if (keys.length != _keys.length || !keys.containsAll(_keys)) {
      throw const CloudError(CloudErrorKind.mismatch, 'Unexpected field set.');
    }
    final ts = d['submittedAt'];
    if (ts is! Timestamp) {
      throw const CloudError(CloudErrorKind.mismatch, 'Server timestamp not resolved.');
    }
    final fixedOk = d['schemaVersion'] == 1 &&
        d['variant'] == 'B' &&
        d['categoryId'] == 17 &&
        d['questionCount'] == 5 &&
        d['correctCount'] is int;
    if (!fixedOk) {
      throw const CloudError(CloudErrorKind.mismatch, 'Fixed fields are wrong.');
    }
    if (d['correctCount'] != expectedCorrect) {
      throw CloudError(CloudErrorKind.collision,
          'Server holds correctCount=${d['correctCount']}, expected $expectedCorrect.');
    }
    return AttemptRecord(
        roundId: snap.id, correctCount: d['correctCount'] as int, submittedAt: ts);
  }

  /// Verification read used after a commit. Dev-only fault hooks live HERE
  /// (the repository), never in the rules.
  Future<AttemptRecord> verifyFromServer({
    required String uid,
    required String roundId,
    required int expectedCorrect,
  }) async {
    if (kDevTools) {
      if (DevHooks.takeSignOutDuringVerify()) {
        DevLog.add('DEV-INJECTED external sign-out during verification');
        Future<void>.delayed(
            const Duration(milliseconds: 800), () => FirebaseAuth.instance.signOut());
      }
      final delay = DevHooks.takeVerifyDelay();
      if (delay > 0) {
        DevLog.add('DEV-INJECTED verification delay ${delay}ms');
        await Future<void>.delayed(Duration(milliseconds: delay));
      }
      final fault = DevHooks.takeVerifyFault();
      if (fault != VerifyFault.none) {
        DevLog.add('DEV-INJECTED ${fault.name} on first verification read');
        throw switch (fault) {
          VerifyFault.permissionDenied => const CloudError(
              CloudErrorKind.permissionDenied,
              'DEV-INJECTED permission-denied (rules are unchanged).',
              injected: true),
          VerifyFault.unavailable => const CloudError(CloudErrorKind.unavailable,
              'DEV-INJECTED unavailable.', injected: true),
          _ => const CloudError(CloudErrorKind.resourceExhausted,
              'DEV-INJECTED resource-exhausted (quota simulated).', injected: true),
        };
      }
    }
    final snap = await readServer(uid, roundId);
    return validate(snap, expectedCorrect: expectedCorrect);
  }

  /// Newest attempts of this user, read from the server.
  Future<List<AttemptRecord>> listAttempts(String uid) async {
    final q = await _attempts(uid)
        .orderBy('submittedAt', descending: true)
        .limit(20)
        .get(const GetOptions(source: Source.server));
    return q.docs.map((d) {
      final data = d.data();
      final ts = data['submittedAt'];
      return AttemptRecord(
        roundId: d.id,
        correctCount: (data['correctCount'] as num?)?.toInt() ?? -1,
        submittedAt: ts is Timestamp ? ts : null,
      );
    }).toList();
  }

  // ---- Dev-lab raw operations (used only to PROVE the rules reject things) ----
  Future<void> rawSet(String uid, String roundId, Map<String, dynamic> data) =>
      refFor(uid, roundId).set(data);

  Future<void> rawUpdate(String uid, String roundId, Map<String, dynamic> data) =>
      refFor(uid, roundId).update(data);
}
