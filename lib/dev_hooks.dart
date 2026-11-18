import 'package:flutter/foundation.dart';

import 'config.dart';

/// Faults injected into the question request (no network is used for these).
enum ApiFault { none, badEncoding, nonZeroCode, fourResults }

/// Faults injected into the FIRST server verification read after a real commit.
enum VerifyFault { none, permissionDenied, unavailable, resourceExhausted }

/// One-shot, development-only switches. Everything here is inert unless the
/// app was started with --dart-define=DEV_TOOLS=true. Deployed rules are never
/// touched; the real commit and the final server read are always real.
class DevHooks {
  static ApiFault apiFault = ApiFault.none;
  static VerifyFault verifyFault = VerifyFault.none;
  static int verifyDelayMs = 0;
  static bool signOutDuringVerify = false;

  static ApiFault takeApiFault() {
    if (!kDevTools) return ApiFault.none;
    final f = apiFault;
    apiFault = ApiFault.none;
    return f;
  }

  static VerifyFault takeVerifyFault() {
    if (!kDevTools) return VerifyFault.none;
    final f = verifyFault;
    verifyFault = VerifyFault.none;
    return f;
  }

  static int takeVerifyDelay() {
    if (!kDevTools) return 0;
    final d = verifyDelayMs;
    verifyDelayMs = 0;
    return d;
  }

  static bool takeSignOutDuringVerify() {
    if (!kDevTools) return false;
    final s = signOutDuringVerify;
    signOutDuringVerify = false;
    return s;
  }
}

/// Small in-app event log (no credentials, no tokens). Useful as test evidence.
class DevLog {
  static final ValueNotifier<List<String>> lines =
      ValueNotifier<List<String>>(<String>[]);

  static void add(String message) {
    final t = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final stamp = '${two(t.hour)}:${two(t.minute)}:${two(t.second)}.'
        '${t.millisecond.toString().padLeft(3, '0')}';
    final next = <String>[...lines.value, '$stamp  $message'];
    if (next.length > 200) next.removeAt(0);
    lines.value = next;
  }
}
