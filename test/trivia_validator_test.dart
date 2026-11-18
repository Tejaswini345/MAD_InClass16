import 'package:flutter_test/flutter_test.dart';
import 'package:science_signal/models/trivia_question.dart';
import 'package:science_signal/services/trivia_validator.dart';

Map<String, dynamic> item(String q, String correct, {String difficulty = 'medium'}) => {
      'category': 'Science%20%26%20Nature',
      'type': 'boolean',
      'difficulty': difficulty,
      'question': q,
      'correct_answer': correct,
      'incorrect_answers': [correct == 'True' ? 'False' : 'True'],
    };

Map<String, dynamic> valid() => {
      'response_code': 0,
      'results': [
        item('The%20Earth%20orbits%20the%20Sun.', 'True'),
        item('Water%20boils%20at%2050%C2%B0C.', 'False'),
        item('Sound%20travels%20faster%20than%20light.', 'False'),
        item('Humans%20have%2023%20chromosome%20pairs.', 'True'),
        item('Gold%27s%20symbol%20is%20Au.', 'True'),
      ],
    };

void main() {
  test('valid payload is decoded with Uri.decodeComponent', () {
    final qs = parseTriviaResponse(valid());
    expect(qs.length, 5);
    expect(qs.first.question, 'The Earth orbits the Sun.');
    expect(qs.first.rawQuestion, 'The%20Earth%20orbits%20the%20Sun.');
    expect(qs[1].question, 'Water boils at 50°C.');
    expect(qs[1].correctAnswer, false);
    expect(qs[4].question, "Gold's symbol is Au.");
  });

  test('non-zero response_code is rejected', () {
    final j = valid()..['response_code'] = 5;
    expect(() => parseTriviaResponse(j), throwsA(isA<TriviaFormatException>()));
  });

  test('four results are rejected', () {
    final j = valid();
    (j['results'] as List).removeLast();
    expect(() => parseTriviaResponse(j), throwsA(isA<TriviaFormatException>()));
  });

  test('malformed percent-encoding is rejected', () {
    final j = valid();
    (j['results'] as List)[0] = item('%E0%A4%A', 'True');
    expect(() => parseTriviaResponse(j), throwsA(isA<TriviaFormatException>()));
  });

  test('wrong difficulty is rejected', () {
    final j = valid();
    (j['results'] as List)[2] = item('Hard%20one.', 'True', difficulty: 'hard');
    expect(() => parseTriviaResponse(j), throwsA(isA<TriviaFormatException>()));
  });

  test('invalid answer values are rejected', () {
    final j = valid();
    (j['results'] as List)[3] = {
      ...item('Odd%20one.', 'True'),
      'correct_answer': 'Maybe',
    };
    expect(() => parseTriviaResponse(j), throwsA(isA<TriviaFormatException>()));
  });

  test('HTML entities are NOT unescaped (percent-encoding is a different scheme)', () {
    final j = valid();
    (j['results'] as List)[0] = item('A%20%26quot%3B%20B', 'True');
    expect(parseTriviaResponse(j).first.question, 'A &quot; B');
  });
}
