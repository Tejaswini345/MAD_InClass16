import '../models/trivia_question.dart';

/// Validates and decodes an Open Trivia DB response (encode=url3986).
/// Pure Dart so it can be unit-tested without a network.
///
/// Rules: response_code == 0, exactly five results, each with a nonempty
/// question, a correct answer and exactly one incorrect answer. category,
/// question and answers are decoded with Uri.decodeComponent (NOT an HTML
/// unescaper). Decoded category must be "Science & Nature", difficulty
/// "medium", type "boolean" and the answer set exactly {True, False}.
List<TriviaQuestion> parseTriviaResponse(Map<String, dynamic> json) {
  final code = json['response_code'];
  if (code != 0) {
    throw TriviaFormatException('API response_code was $code (expected 0).');
  }
  final results = json['results'];
  if (results is! List || results.length != 5) {
    final n = results is List ? results.length : 'missing';
    throw TriviaFormatException('Expected exactly 5 results but got $n.');
  }

  final out = <TriviaQuestion>[];
  for (var i = 0; i < results.length; i++) {
    final item = results[i];
    if (item is! Map) {
      throw TriviaFormatException('Result ${i + 1} is not an object.');
    }

    String decode(Object? value, String field) {
      if (value is! String) {
        throw TriviaFormatException('Result ${i + 1}: "$field" is missing.');
      }
      try {
        return Uri.decodeComponent(value);
      } catch (_) {
        throw TriviaFormatException(
            'Result ${i + 1}: "$field" has malformed percent-encoding.');
      }
    }

    final category = decode(item['category'], 'category');
    final difficulty = decode(item['difficulty'], 'difficulty');
    final type = decode(item['type'], 'type');
    final rawQuestion = item['question'];
    final question = decode(rawQuestion, 'question');
    final correct = decode(item['correct_answer'], 'correct_answer');

    final incorrectList = item['incorrect_answers'];
    if (incorrectList is! List || incorrectList.length != 1) {
      throw TriviaFormatException(
          'Result ${i + 1}: expected exactly one incorrect answer.');
    }
    final incorrect = decode(incorrectList.first, 'incorrect_answers');

    if (category != 'Science & Nature') {
      throw TriviaFormatException(
          'Result ${i + 1}: category "$category" is not Science & Nature.');
    }
    if (difficulty != 'medium') {
      throw TriviaFormatException(
          'Result ${i + 1}: difficulty "$difficulty" is not medium.');
    }
    if (type != 'boolean') {
      throw TriviaFormatException('Result ${i + 1}: type "$type" is not boolean.');
    }
    if (question.trim().isEmpty) {
      throw TriviaFormatException('Result ${i + 1}: empty question.');
    }
    final answers = <String>{correct, incorrect};
    if (answers.length != 2 ||
        !answers.contains('True') ||
        !answers.contains('False')) {
      throw TriviaFormatException(
          'Result ${i + 1}: answers must be exactly True and False.');
    }

    out.add(TriviaQuestion(
      question: question,
      rawQuestion: rawQuestion as String,
      correctAnswer: correct == 'True',
    ));
  }
  return out;
}
