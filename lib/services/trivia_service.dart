import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import '../dev_hooks.dart';
import '../models/trivia_question.dart';
import 'trivia_validator.dart';

class RateLimitException implements Exception {
  const RateLimitException(this.secondsLeft);
  final int secondsLeft;
}

class TriviaService {
  static final Uri endpoint = Uri.parse(
      'https://opentdb.com/api.php?amount=5&category=17&difficulty=medium'
      '&type=boolean&encode=url3986');

  static const Duration minGap = Duration(seconds: 5);
  static DateTime? _lastRequest;

  /// Seconds until another OpenTDB request is allowed (0 = allowed now).
  static int get cooldownSeconds {
    final last = _lastRequest;
    if (last == null) return 0;
    final left = minGap - DateTime.now().difference(last);
    return left.inMilliseconds <= 0 ? 0 : (left.inMilliseconds / 1000).ceil();
  }

  /// One user-triggered request. Never retries automatically.
  Future<List<TriviaQuestion>> fetchRound() async {
    final fault = kDevTools ? DevHooks.takeApiFault() : ApiFault.none;
    if (fault != ApiFault.none) {
      DevLog.add('DEV-INJECTED API fault: ${fault.name} (no network call)');
      return parseTriviaResponse(_cannedFault(fault));
    }

    final left = cooldownSeconds;
    if (left > 0) throw RateLimitException(left);
    _lastRequest = DateTime.now();

    final res = await http.get(endpoint).timeout(kNetworkTimeout);
    if (res.statusCode != 200) {
      throw TriviaFormatException('HTTP status ${res.statusCode} (expected 200).');
    }
    final decoded = jsonDecode(res.body);
    if (decoded is! Map<String, dynamic>) {
      throw const TriviaFormatException('Response was not a JSON object.');
    }
    return parseTriviaResponse(decoded);
  }

  Map<String, dynamic> _item(String q, String correct) => {
        'category': 'Science%20%26%20Nature',
        'type': 'boolean',
        'difficulty': 'medium',
        'question': q,
        'correct_answer': correct,
        'incorrect_answers': [correct == 'True' ? 'False' : 'True'],
      };

  Map<String, dynamic> _cannedFault(ApiFault fault) {
    switch (fault) {
      case ApiFault.badEncoding:
        return {
          'response_code': 0,
          'results': [
            _item('%E0%A4%A', 'True'), // truncated percent-escape
            for (var i = 0; i < 4; i++) _item('Water%20is%20wet.', 'True'),
          ],
        };
      case ApiFault.nonZeroCode:
        return {'response_code': 2, 'results': []};
      case ApiFault.fourResults:
        return {
          'response_code': 0,
          'results': [for (var i = 0; i < 4; i++) _item('Water%20is%20wet.', 'True')],
        };
      case ApiFault.none:
        return {};
    }
  }
}
