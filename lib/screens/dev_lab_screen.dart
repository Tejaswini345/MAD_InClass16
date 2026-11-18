import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../config.dart';
import '../dev_hooks.dart';
import '../services/attempt_repository.dart';

/// DEVELOPMENT ONLY (needs --dart-define=DEV_TOOLS=true). Everything here is
/// labelled as injected/dev. It never changes the deployed Firestore rules.
class DevLabScreen extends StatefulWidget {
  const DevLabScreen({super.key, required this.repo, required this.uid, required this.roundId});
  final AttemptRepository repo;
  final String uid;
  final String roundId;
  @override
  State<DevLabScreen> createState() => _DevLabScreenState();
}

class _DevLabScreenState extends State<DevLabScreen> {
  late final TextEditingController _target = TextEditingController(text: widget.uid);
  late final TextEditingController _round = TextEditingController(text: widget.roundId);
  int _score = 3;
  bool _sync = false;
  String _out = 'Results appear here and in the event log below.';

  @override
  void dispose() {
    _target.dispose();
    _round.dispose();
    super.dispose();
  }

  void _setOut(String s) {
    DevLog.add(s);
    if (mounted) setState(() => _out = s);
  }

  Future<void> _run(String name, Future<String> Function() body) async {
    try {
      _setOut('$name → ${await body()}');
    } catch (e) {
      final err = CloudError.from(e);
      _setOut('$name → REJECTED/FAILED: ${err.label} (${err.message})');
    }
  }

  String get _t => _target.text.trim();
  String get _r => _round.text.trim();

  Widget _arm(String label, VoidCallback f) => FilledButton.tonal(
      onPressed: () {
        f();
        DevLog.add('Armed: $label');
        setState(() {});
      },
      child: Text(label));

  Widget _section(String title, String help, List<Widget> kids) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            Text(help, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            ...kids,
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    assert(kDevTools);
    return Scaffold(
      appBar: AppBar(title: const Text('DEV lab (not for production)')),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        _section(
          'Fault injection (one-shot)',
          'API faults hit the NEXT question load (use Retry/Play again). Verify faults hit the '
              'FIRST server read after a real commit; the commit itself stays real.',
          [
            Wrap(spacing: 8, runSpacing: 8, children: [
              _arm('T03 bad encoding', () => DevHooks.apiFault = ApiFault.badEncoding),
              _arm('T03 response_code 2', () => DevHooks.apiFault = ApiFault.nonZeroCode),
              _arm('T03 four results', () => DevHooks.apiFault = ApiFault.fourResults),
              _arm('T09 verify: permission-denied',
                  () => DevHooks.verifyFault = VerifyFault.permissionDenied),
              _arm('T12 verify: unavailable',
                  () => DevHooks.verifyFault = VerifyFault.unavailable),
              _arm('T12 verify: resource-exhausted',
                  () => DevHooks.verifyFault = VerifyFault.resourceExhausted),
              _arm('G03 sign out during verify (+8 s delay)', () {
                DevHooks.signOutDuringVerify = true;
                DevHooks.verifyDelayMs = 8000;
              }),
              OutlinedButton(
                  onPressed: () => setState(() {
                        DevHooks.apiFault = ApiFault.none;
                        DevHooks.verifyFault = VerifyFault.none;
                        DevHooks.verifyDelayMs = 0;
                        DevHooks.signOutDuringVerify = false;
                      }),
                  child: const Text('Clear all')),
            ]),
            const SizedBox(height: 8),
            Text('Armed → API: ${DevHooks.apiFault.name} | verify: ${DevHooks.verifyFault.name} | '
                'delay: ${DevHooks.verifyDelayMs} ms | signOutDuringVerify: ${DevHooks.signOutDuringVerify}'),
          ],
        ),
        _section(
          'Rules checks (T10 / T11)',
          'T10: paste USER A\'s UID into Target while signed in as USER B, then Read and Write. '
              'T11: keep your own UID and try score 6, extra field, and update.',
          [
            TextField(
                controller: _target,
                decoration: const InputDecoration(labelText: 'Target UID', border: OutlineInputBorder())),
            const SizedBox(height: 8),
            TextField(
                controller: _round,
                decoration: const InputDecoration(labelText: 'Round ID', border: OutlineInputBorder())),
            const SizedBox(height: 8),
            Text('Signed-in UID: ${FirebaseAuth.instance.currentUser?.uid}',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton(
                  onPressed: () => _run('Read target path (server)', () async {
                        final s = await widget.repo.readServer(_t, _r).timeout(kNetworkTimeout);
                        return 'READ ALLOWED, exists=${s.exists}';
                      }),
                  child: const Text('Read path')),
              FilledButton(
                  onPressed: () => _run('Write valid doc to target path', () async {
                        await widget.repo.rawSet(_t, _r, widget.repo.validData(3)).timeout(kNetworkTimeout);
                        return 'WRITE ACCEPTED';
                      }),
                  child: const Text('Write valid doc')),
              FilledButton(
                  onPressed: () => _run('Write correctCount 6', () async {
                        await widget.repo.rawSet(_t, _r, widget.repo.validData(6)).timeout(kNetworkTimeout);
                        return 'UNEXPECTEDLY ACCEPTED';
                      }),
                  child: const Text('Write score 6')),
              FilledButton(
                  onPressed: () => _run('Write with extra field', () async {
                        await widget.repo
                            .rawSet(_t, _r, {...widget.repo.validData(3), 'extra': 'x'})
                            .timeout(kNetworkTimeout);
                        return 'UNEXPECTEDLY ACCEPTED';
                      }),
                  child: const Text('Write extra field')),
              FilledButton(
                  onPressed: () => _run('Update existing doc', () async {
                        await widget.repo.rawUpdate(_t, _r, {'correctCount': 0}).timeout(kNetworkTimeout);
                        return 'UNEXPECTEDLY ACCEPTED';
                      }),
                  child: const Text('Update existing')),
            ]),
          ],
        ),
        _section(
          'Concurrency (G01 / G02)',
          'G01: two clients, SAME user, SAME round ID, DIFFERENT scores. G02: two clients, '
              'DIFFERENT round IDs. Tick "fire at boundary" on both so they commit together.',
          [
            Row(children: [
              Expanded(
                  child: TextField(
                      controller: _round,
                      decoration: const InputDecoration(labelText: 'Round ID', border: OutlineInputBorder()))),
              IconButton(
                  tooltip: 'New random ID',
                  icon: const Icon(Icons.casino),
                  onPressed: () => setState(() => _round.text = widget.repo.newRoundId(widget.uid))),
            ]),
            Row(children: [
              const Text('Score: '),
              DropdownButton<int>(
                  value: _score,
                  items: [for (var i = 0; i <= 5; i++) DropdownMenuItem(value: i, child: Text('$i'))],
                  onChanged: (v) => setState(() => _score = v ?? 3)),
              const Spacer(),
              const Text('Fire at next :00/:30'),
              Switch(value: _sync, onChanged: (v) => setState(() => _sync = v)),
            ]),
            FilledButton(
              onPressed: () => _run('Commit round ${_r.length > 4 ? "…${_r.substring(_r.length - 4)}" : _r} score $_score', () async {
                if (_sync) {
                  final ms = DateTime.now().millisecondsSinceEpoch;
                  final next = ((ms ~/ 30000) + 1) * 30000;
                  _setOut('Waiting ${((next - ms) / 1000).toStringAsFixed(1)} s for the shared boundary…');
                  await Future<void>.delayed(Duration(milliseconds: next - ms));
                }
                String outcome;
                try {
                  final o = await widget.repo
                      .commit(uid: widget.uid, roundId: _r, correctCount: _score)
                      .timeout(kNetworkTimeout);
                  outcome = o.name;
                } on CloudError catch (e) {
                  if (e.kind != CloudErrorKind.collision) rethrow;
                  outcome = 'COLLISION (not overwritten)';
                }
                final snap = await widget.repo.readServer(widget.uid, _r).timeout(kNetworkTimeout);
                final d = snap.data();
                return 'outcome=$outcome | server doc: correctCount=${d?['correctCount']}, '
                    'submittedAt=${d?['submittedAt']}';
              }),
              child: const Text('Commit + server read'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text('Last result', style: Theme.of(context).textTheme.titleMedium),
        SelectableText(_out),
        const Divider(height: 24),
        Text('Event log', style: Theme.of(context).textTheme.titleMedium),
        ValueListenableBuilder<List<String>>(
          valueListenable: DevLog.lines,
          builder: (context, lines, _) => SelectableText(
              lines.reversed.take(60).join('\n'),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
        ),
      ]),
    );
  }
}
