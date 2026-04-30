/// No-op stubs used by the Dart VM test runner.

bool wasHtmlPlayTapped() => false;

void registerHtmlPlayCallback(void Function() onPlay) {}

void unregisterHtmlPlayCallback() {}

bool wasHtmlSkipTapped() => false;

void registerHtmlSkipCallback(void Function() onSkip) {}

void unregisterHtmlSkipCallback() {}

void registerHtmlLegalCallback(void Function(String page) onLegal) {}

void unregisterHtmlLegalCallback() {}
