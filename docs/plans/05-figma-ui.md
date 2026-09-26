---
name: PaperSync Phase 5 - Figma UI
overview: 'Rebuild the app screens from the PaperSync Figma file (node 2003:129) on top of the Phase 1-4 logic: read the design through the Figma REST API with a read-only token, turn it into theme tokens and assets, rebuild shared widgets and each screen, and verify against Figma exports with golden tests.'
todos:
  - id: p5-access
    content: 'Read the file through the Figma REST API with FIGMA_TOKEN (read-only scope); cache raw JSON and renders in a gitignored folder; never log or commit the token'
    status: completed
  - id: p5-inventory
    content: 'Map every Figma frame to an app screen or state, and flag any design that needs logic not covered by Phases 1-4'
    status: completed
  - id: p5-tokens
    content: 'Generate app/lib/theme/tokens.dart (colors light and dark, type scale, spacing, radii, elevation) and rebuild AppColors and AppTheme on it; bundle the design fonts as assets'
    status: completed
  - id: p5-assets
    content: 'Export icons and logos from Figma as SVG or PNG at 1x/2x/3x into app/assets/ and register them in pubspec.yaml'
    status: completed
  - id: p5-widgets-screens
    content: 'Rebuild shared widgets, then each screen and state to match Figma, wired only to the AppController API and the sync and link providers'
    status: completed
  - id: p5-verify
    content: 'Golden tests per screen in light and dark at the Figma frame size, side-by-side check against Figma renders, accessibility checks'
    status: completed
isProject: false
---
# Phase 5: UI from Figma

Goal: the app looks like the Figma design ([PaperSync, node 2003:129](https://www.figma.com/design/9Q4PKHBzk3oVIigtd75nLo/PaperSync?node-id=2003-129)). The logic from Phases 1-4 stays unchanged. Screens talk only to `appControllerProvider`, `syncStatusProvider`, and the auth controller.

This phase depends only on the `AppController` API, so it can start any time after Phase 2 if you want to see the design earlier.

## 1. Access

- Figma's AI tools are blocked by the Starter plan limit, so the design is read through the Figma REST API instead.
- Uses `FIGMA_TOKEN`, a Figma personal access token with the read-only `file_content:read` scope. It has been added in Cursor Dashboard > Cloud Agents > Secrets. It is injected only when an agent session starts, so the session that runs this phase checks it first with `GET /v1/me`.
- Calls:
  - `GET /v1/files/9Q4PKHBzk3oVIigtd75nLo/nodes?ids=2003:129` for the node tree, fills, text styles, auto-layout, and components.
  - `GET /v1/files/:key/styles` for the named color and text styles.
  - `GET /v1/images/:key?ids=...&format=png&scale=2` to render each frame as the visual target.
  - The same endpoint with `format=svg` for icons and logos.
- Security:
  - The token is read only from the environment, sent only in the `X-Figma-Token` header, and never written to files, logs, commits, or the PR.
  - Raw responses are cached in `design/figma-cache/`, which is gitignored. Only derived tokens and assets are committed.

## 2. Inventory

- List every frame under node 2003:129 and map it to an app screen or state:
  - Library, Notebook pages, Live Capture, Page editor, Search, and Device.
  - The Phase 4 sign-in sheet.
  - Empty, loading, error, and "Couldn't back up" states.
  - Light and dark variants.
- The mapping goes in `docs/ui-figma-map.md`, with frame names and node ids.
- A frame that needs logic not covered by Phases 1-4 is flagged for your decision instead of being built silently. Examples are handwriting search results, which need ML Kit, or a new setting.

## 3. Design tokens

- `app/lib/theme/tokens.dart` is generated from the Figma styles and auto-layout values:
  - Colors for light and dark.
  - Type scale: family, size, weight, line height, and letter spacing.
  - Spacing steps, corner radii, and elevation or shadows.
- [app/lib/theme/app_colors.dart](app/lib/theme/app_colors.dart) and [app/lib/theme/app_theme.dart](app/lib/theme/app_theme.dart) are rebuilt on these tokens. Widgets use theme values, not hard-coded colors or sizes.
- The design's fonts are bundled under `app/assets/fonts/` with their licenses, replacing runtime `google_fonts` fetching. The app then works offline and makes no network request just to show text.

## 4. Assets

- Every icon, logo, and illustration in the frames is exported from Figma and used in its exact slot. The two logos from [PR #1](https://github.com/alyastanga/PaperSync/pull/1) are reused only if they match the Figma export exactly.
  - Vectors are SVG (rendered with `flutter_svg`), and bitmaps are PNG at 1x, 2x, and 3x.
  - They live under `app/assets/` and are listed in [app/pubspec.yaml](app/pubspec.yaml).
- No temporary Figma URLs remain in the code.

## 5. Widgets, then screens

- First rebuild the shared pieces to match their Figma components: top bar, status pill, notebook card, page row, editor toolbar, buttons, dialogs, and sheets.
- Then rebuild each screen from its frame. Figma's absolute positions are translated into Flutter layout (`Row`, `Column`, padding, and flex taken from auto-layout), so screens adapt to phone sizes rather than being pinned to pixels.
- Every screen keeps its current wiring to the controller and providers. No screen imports `ble`, `capture`, `storage`, or `sync` directly, and `architecture_test.dart` enforces this for `lib/screens/` and `lib/widgets/`.
- The ink canvas (`ink_page.dart`, `stroke_paint.dart`) keeps its rendering logic. Only the colors and chrome around it follow the design.

## 6. Verification

- Golden tests for each screen and state, in light and dark, at the Figma frame size, with the bundled fonts, run by `flutter test`.
- Each golden is compared side by side with the Figma PNG render, and any in-scope difference is fixed. Differences found in screens outside this phase are noted, not changed.
- Accessibility:
  - Text and icon contrast meets WCAG AA.
  - Tap targets are at least 48 dp.
  - Every control has a semantics label.
  - Layouts hold at 200% text scale.
- A web build walkthrough of every screen, with screenshots attached to the PR.

## Coordination

- This phase replaces the sketch UI. Before Phase 5 starts, the UI agent should stop, or its last changes should be merged into this branch, so the two don't edit the same screens.

## Done when

- Analyze, format, and tests are clean, including goldens.
- Every Figma frame in `docs/ui-figma-map.md` is built or has a decision recorded.
- The screens match the Figma renders in light and dark.
