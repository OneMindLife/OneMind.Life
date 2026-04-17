// Stub for non-web platforms (used by VM-based tests).

bool isPwaInstalled() => false;

bool isMobileDevice() => false;

bool isIos() => false;

Future<bool> triggerPwaInstall() async => false;

bool hasInstallPrompt() => false;

Future<bool> hasInstalledPwa() async => false;
