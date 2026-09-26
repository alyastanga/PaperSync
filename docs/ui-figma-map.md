# PaperSync Figma map

Source: [PaperSync, node 2003:129](https://www.figma.com/design/9Q4PKHBzk3oVIigtd75nLo/PaperSync?node-id=2003-129).

Read with the `Figma_token` environment variable (`file_content:read`) in the `X-Figma-Token` header. `GET /v1/me`, `GET /v1/files/:key/styles`, and `GET /v1/files/:key/variables/local` return 403 for this scope. `GET /v1/files/9Q4PKHBzk3oVIigtd75nLo/nodes?ids=2003:129` and `GET /v1/images/:key` succeeded. Raw JSON and PNG renders stay in gitignored `design/figma-cache/`.

The file has two canvases:

- `PaperSync Screens` (`2003:129`), one light frame `PaperSync Mobile` (`2003:171`) with 13 screens at 390×844.
- `Page 1` (`0:1`), one illustration frame `Comic Strip` (`5:360`) at 1036×1198. The images API returned no URL for that node.

There is no dark-mode frame, and no separate Search, loading, empty, or error frame. Dark colors are the inverse palette in `app/lib/theme/tokens.dart`. Welcome (`2003:172`) resolves variable `2003:151` to black; every other screen resolves that variable to `#F4F1EC`. The welcome render is black, so the screen is black. Title text in the file is `#1C1917` on that black (about 1.1:1). The app uses paper white for the title and `#A39E94` for the subtitle so the screen meets WCAG AA.

`#8A847C` meta text is about 3.3:1 on the canvas. Screens use `#726D66`, the same hue at 4.5:1. The original value is `PaperTokens.lightFigmaMeta`.

| Frame | Node | App surface | Status |
| --- | --- | --- | --- |
| Welcome | `2003:172` | `WelcomeScreen`, first screen | Built. Continue without account opens the library. |
| Sign in | `2003:174` | `SignInScreen` | Built. UI-only for the password. Phase 4 sign-in is an email code; the password is not sent. |
| Create account | `2003:176` | `CreateAccountScreen` | Built. UI-only for the password. The name and email stay on this phone. A cloud account is not created unless backup is configured, and then the email-code sheet runs. |
| Reset password | `2003:178` | `ResetPasswordScreen` | Built. UI-only. The artboard's "Check your inbox" note is shown. The button does not send a link. |
| Library | `2003:180` | `LibraryScreen` | Built. A Settings control was added so that frame is reachable. The file's row only has New notebook. |
| Notebook | `2003:182` | `NotebookPagesScreen` | Built |
| Live capture | `2003:184` | `LiveCaptureScreen` | Built. Ink keeps the 170×107 mm canvas. |
| Page editor | `2003:186` | `PageEditorScreen` | Built |
| Pen | `2003:188` | `DeviceScreen` when a pen is bonded | Built |
| Settings | `2003:190` | `SettingsScreen` | Built. Handwriting recognition, export default, and the comic-strip row are UI-only. Appearance changes the theme. |
| Account and sync | `2003:192` | `AccountSyncScreen` | Built. UI-only for storage size ("On this phone", not "18 MB"), last-sync time ("not recorded", not "just now"), and the mobile-data switch. The name is whatever was typed on Create account. |
| Pen setup | `2003:194` | `DeviceScreen` while pairing | Built. Bluetooth permission stays in front of Connect. |
| Sync recovery | `2003:196` | `SyncIssueScreen` | Built. The card lists real local pages. It does not invent "Pages 4, 5, and 6". |
| Comic Strip | `5:360` | `ComicStripScreen` | Built. UI-only. The images API returned no render, so the screen shows the frame's text. Opened from Settings. |
| Phase 4 sign-in sheet | none | `showSignInSheet` on the pen screen | Built. Email code, not a Figma frame. |
| Search | none | `SearchScreen` | Built from tokens. Results match saved `recognizedText`. ML Kit handwriting search is not added. |
| Empty library | none | `LibraryScreen` empty state | Built |
| Storage error | none | quarantine banner on `LibraryScreen` | Built |
| Couldn't back up | none | backup banner on `LibraryScreen`, opens `SyncIssueScreen` | Built |
| Loading | none | none | Not a frame. Storage opens before the first screen. |
| Dark mode | none | `AppTheme.dark` | Tokens only. No dark frames in the file. |

## What the screens do not pretend

- Password sign-in, account creation, and reset links are not a backend. Copy on those screens says so when you submit.
- Handwriting recognition does not start ML Kit. Search keeps using text already stored on a page.
- Sync over mobile data does not change `SyncService`.
- Storage used is not a byte count. Nothing in Phases 1–4 records one.
- Last sync is not "just now". No sync clock is stored.
- The sync-issue page list is the notebooks on this phone, not a server list of failed pages.

## What was built

Shared chrome follows the auto-layout: 60 dp library bars, 56 dp form bars, text actions (Search, Back, Close, More), status pill, notebook cards, page rows, editor clusters, primary and secondary buttons, fields, settings rows, dialogs, and the sign-in sheet. Hit targets are at least 48 dp, so some controls are taller than the 46 dp Figma buttons. Widgets take spacing and type from `PaperTokens` / `PaperType` and color from `AppColors`.

Illustrations exported as SVG and registered in `app/pubspec.yaml`:

- `assets/images/ink-preview.svg` (`2003:199`) on Welcome and the empty library.
- `assets/images/pen-glyph.svg` (`2007:71`) on pen setup.
- `assets/images/sync-warn.svg` (`2007:88`) on the sync issue screen.

There were no bitmap icons, so there are no 1x/2x/3x PNGs. The comic strip did not render. Inter (OFL, `app/assets/fonts/OFL.txt`) replaces `google_fonts`. No Figma URL is left in the app code.

The live sheet in the file is 342×420. Capture still uses the tablet aspect (`pageAspect`) so a page stays the shape the pen writes. Chrome around it (radius 12, hairline, no shadow) follows the file. The file has no effects.
