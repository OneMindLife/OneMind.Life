/// Non-web fallback for PWA detection — always false on mobile/desktop
/// because the concept of "installed PWA in standalone display-mode"
/// only exists in browsers.
bool isStandalonePwa() => false;
