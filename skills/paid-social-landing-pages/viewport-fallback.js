// Viewport fallback JS — companion to templates/viewport-fallback.css
//
// Sets the --vh CSS custom property based on window.innerHeight, which is
// the only reliable viewport measurement inside TikTok's WKWebView.
// Updates on resize and orientation change (keyboard open/close triggers resize).
//
// Load early in <head>, ideally inline to avoid FOUC on layout shift.

(function () {
  function setVh() {
    var vh = window.innerHeight * 0.01;
    document.documentElement.style.setProperty('--vh', vh + 'px');
  }

  // Initial set — must run before first paint.
  setVh();

  // Debounce resize to avoid thrashing during keyboard animation.
  var resizeTimer;
  function debouncedSetVh() {
    clearTimeout(resizeTimer);
    resizeTimer = setTimeout(setVh, 50);
  }

  window.addEventListener('resize', debouncedSetVh);
  window.addEventListener('orientationchange', debouncedSetVh);

  // Manual scroll restoration — TikTok re-enters pages in fresh WebView instances,
  // and browser-native scroll restoration is unreliable inside IABs.
  if ('scrollRestoration' in history) {
    history.scrollRestoration = 'manual';
  }

  // Optional: persist and restore scroll position per pathname.
  var storageKey = 'scroll:' + location.pathname;
  var saved = sessionStorage.getItem(storageKey);
  if (saved) {
    // Wait for layout to settle before restoring.
    window.addEventListener('load', function () {
      window.scrollTo(0, parseInt(saved, 10) || 0);
    });
  }
  window.addEventListener('beforeunload', function () {
    sessionStorage.setItem(storageKey, String(window.scrollY));
  });
})();
