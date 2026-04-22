// Multi-token IAB detection for paid-social landing pages.
// Copy-paste starting point — adapt token list as platforms update UAs.
//
// Usage:
//   import { detectIAB } from './iab-detection.js';
//   const { isIAB, platform, isHostile } = detectIAB();
//   if (isHostile) applyHostileMitigations();

const DETECTORS = {
  // Hostile tier — custom WKWebView / WebView with JS injection, storage isolation,
  // broken Apple Pay. Build defensively. TikTok-first mitigations cover this tier.
  tiktok:    /\b(musical_ly|trill|BytedanceWebview|TikTokOSBrowser|Bytedance)\b|\bJsSdk\//i,
  facebook:  /\b(FBAN|FBAV|FB_IAB|FB4A)\b/,
  instagram: /\bInstagram\b/,
  messenger: /\b(MessengerForiOS|Orca-Android)\b/,
  snapchat:  /\bSnapchat\b/,
  pinterest: /\[Pinterest\/(iOS|Android)\]/,

  // Mixed tier — hostile on iOS, friendly on Android (Chrome Custom Tabs).
  linkedin:  /\bLinkedInApp\b/,

  // Friendly tier — X/Twitter, Reddit, YouTube delegate to SFSafariViewController
  // or Chrome Custom Tabs on link taps and do not leave a reliable UA marker.
  // If you need to detect them, rely on referrer or campaign parameters instead.
};

const HOSTILE_PLATFORMS = new Set([
  'tiktok', 'facebook', 'instagram', 'messenger', 'snapchat', 'pinterest'
]);

export function detectIAB(ua = navigator.userAgent) {
  for (const [platform, regex] of Object.entries(DETECTORS)) {
    if (regex.test(ua)) {
      const isIOS = /iPhone|iPad|iPod/.test(ua);

      // LinkedIn special case: hostile on iOS, friendly on Android.
      const isHostile = platform === 'linkedin'
        ? isIOS
        : HOSTILE_PLATFORMS.has(platform);

      return { isIAB: true, platform, isIOS, isHostile };
    }
  }
  return { isIAB: false, platform: null, isIOS: /iPhone|iPad|iPod/.test(ua), isHostile: false };
}

// Convenience shortcut for the most common check.
export const isTikTokIAB = (ua = navigator.userAgent) => DETECTORS.tiktok.test(ua);
export const isMetaIAB = (ua = navigator.userAgent) =>
  DETECTORS.facebook.test(ua) || DETECTORS.instagram.test(ua) || DETECTORS.messenger.test(ua);
