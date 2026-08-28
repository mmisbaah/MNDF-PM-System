# Accessibility and device acceptance

## Required automated gate

Run `npm run accessibility:gate` for every release. The gate checks document language, keyboard navigation support, zoom availability, minimum touch targets, focus visibility, reduced-motion behavior, high-contrast focus, navigation landmarks, and accessible icon controls.

## Supported pilot clients

- Current and previous major versions of Microsoft Edge and Google Chrome on desktop.
- Current Android Chrome on organization-approved phones and tablets.
- Current iOS/iPadOS Safari, including the installed PWA.
- Desktop widths from 1024px upward and mobile widths from 320px upward.

## Attended acceptance before onboarding

Complete and record the following on representative organization devices:

1. Navigate login, MFA, every workspace tab, forms, dialogs, and sign-out using only a keyboard.
2. Confirm the skip link appears on focus and moves focus to the application content.
3. Test browser zoom at 200% without loss of content or horizontal page overflow. A deliberately scrollable tab bar is acceptable.
4. Test with Windows Narrator plus Edge and with either VoiceOver plus Safari or TalkBack plus Chrome. Verify names, roles, states, errors, deadlines, scores, and progress indicators are announced.
5. Verify all interactive targets are at least 48 by 48 CSS pixels on mobile.
6. Enable reduced motion and forced/high-contrast colors and confirm focus remains visible.
7. Rotate a phone or tablet, install the PWA, relaunch it, and confirm the offline shell loads without exposing protected cached data.

Record device, operating-system version, browser version, tester, date, result, defects, and retest evidence. Any failure in authentication, appraisal submission, grievance deadlines, restricted information, or sign-out blocks pilot release.
