/// Development-only tools (fault injection, rules lab, concurrency lab).
/// OFF by default. Turn on with:  flutter run --dart-define=DEV_TOOLS=true
const bool kDevTools = bool.fromEnvironment('DEV_TOOLS', defaultValue: false);

const int kQuestionCount = 5;
const Duration kNetworkTimeout = Duration(seconds: 10);
