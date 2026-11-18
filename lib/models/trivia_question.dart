class TriviaQuestion {
  const TriviaQuestion({
    required this.question,
    required this.rawQuestion,
    required this.correctAnswer,
  });

  /// Decoded with Uri.decodeComponent (what the player sees).
  final String question;

  /// Original percent-encoded text from the API (kept for T02 evidence).
  final String rawQuestion;

  /// true  => the correct answer is "True"
  final bool correctAnswer;
}

class TriviaFormatException implements Exception {
  const TriviaFormatException(this.message);
  final String message;
  @override
  String toString() => message;
}
