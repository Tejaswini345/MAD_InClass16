import 'package:flutter/material.dart';

import '../config.dart';
import '../services/attempt_repository.dart';

/// Lists this user's attempts straight from the SERVER (T07: restart, sign in
/// again, retrieve the same ID without replaying).
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, required this.repo, required this.uid});
  final AttemptRepository repo;
  final String uid;
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late Future<List<AttemptRecord>> _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _future = widget.repo.listAttempts(widget.uid).timeout(kNetworkTimeout);
  }

  Future<void> _verifyOne(AttemptRecord r) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final snap = await widget.repo.readServer(widget.uid, r.roundId).timeout(kNetworkTimeout);
      final rec = widget.repo.validate(snap, expectedCorrect: r.correctCount);
      messenger.showSnackBar(SnackBar(
          content: Text('Cloud verified: round ${rec.redactedId}, '
              'score ${rec.correctCount}/5, server time ${rec.submittedAt?.toDate().toLocal()}')));
    } catch (e) {
      final err = CloudError.from(e);
      messenger.showSnackBar(SnackBar(content: Text('${err.label}: ${err.message}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Saved attempts (server)'),
        actions: [
          IconButton(
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh),
              onPressed: () => setState(_load)),
        ],
      ),
      body: FutureBuilder<List<AttemptRecord>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            final err = CloudError.from(snap.error!);
            return Center(
                child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('${err.label}\n${err.message}', textAlign: TextAlign.center)));
          }
          final items = snap.data!;
          if (items.isEmpty) return const Center(child: Text('No saved attempts yet.'));
          return ListView(children: [
            for (final r in items)
              ListTile(
                leading: CircleAvatar(child: Text('${r.correctCount}')),
                title: Text('Score ${r.correctCount} / 5'),
                subtitle: Text('Round ${r.redactedId}  •  ${r.submittedAt?.toDate().toLocal() ?? "timestamp pending"}'),
                trailing: IconButton(
                  tooltip: 'Verify this record from the server',
                  icon: const Icon(Icons.verified_outlined),
                  onPressed: () => _verifyOne(r),
                ),
              ),
          ]);
        },
      ),
    );
  }
}
