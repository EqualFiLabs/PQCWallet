# UI Audit – EqualFi PQC Wallet (Flutter)

## Context

- Target platforms: iOS and Android mobile; tablet layouts are out of scope and the app should enforce portrait orientation (not implemented yet).
- Two major code areas: shared shell in `lib/main.dart`, feature screens under `lib/ui/`, theming in `lib/theme/theme.dart`.
- Current goal: capture definitive UI state so designers/agents can iterate on new visual language, finalize placeholders, and align error handling.

## Brand & Theme

- **Palette**: dark background `#0B0E14`, surface `#11151F`, neon teal primary `#00E5FF`, magenta secondary `#FF3D81`; errors rely on `Colors.redAccent`. `onPrimary` is black, `onSecondary` white (`lib/theme/theme.dart`).
- **Typography**: defaults to Material text styles; body text uses `Colors.white70`, titles `Colors.white` with medium weight. No custom fonts defined yet.
- **Buttons & Inputs**: Elevated buttons = neon background, black label, 12 px radius, zero elevation; `FilledButton` defaults remain. Inputs use translucent cyan fill (`0x151BE0FF`), no borders, rounded 12 px corners.
- **Reusable Glow**: `NeonCard` and placeholder screens blend primary/secondary gradients with semi-transparent borders for information panels (`lib/ui/components/neon_card.dart`, `lib/ui/navigation_placeholder_screen.dart`).

## Layout & Navigation

- **App Shell**: `MaterialApp` hosts a shared drawer + `TopBar` + bottom navigation scaffold (`lib/main.dart`).
- **Bottom Navigation**: `IndexedStack` preserves tab state. Tabs (left→right): Overview (placeholder), Wallet (main functionality), Placeholder 3, Security, Placeholder 4 (`lib/main.dart:1174-1217`).
- **Drawer**: Switch between PQC smart account and classic EOA, includes decorative network picker card, quick-access icon tiles, and gradient “EQ” logo footer (`lib/main.dart:1321-1705`). Network dropdown is visual-only today.
- **Top Bar**: Wallet icon + truncated address title, copy button, WalletConnect QR trigger, settings, and status chip + optional banner (`lib/ui/components/top_bar.dart`).

## Screen Inventory

- **Wallet Tab (`OverviewScreen`)**: Balance header, streamed activity feed, account card, ETH send form, token sheet entry, pending actions. Shows instructions when PQC address is missing (`lib/main.dart:1860-2325`).
- **Settings**: Biometrics toggles, PIN management, WalletConnect access, custom RPC override with validation and helper text (`lib/ui/settings_screen.dart`).
- **Wallet Setup View**: Centered card for creating or importing wallets, handles busy/error states inline (`lib/ui/wallet_setup.dart`).
- **Send Token Sheet**: Bottom sheet with token dropdown (from `assets/tokens.base.json`), mode toggle (EOA vs 4337), permit switches, transfers + approvals (`lib/ui/send_token_sheet.dart`).
- **Fee Sheet**: Modal bottom sheet for editing max/priority gas fees with computed summaries (`lib/ui/send_sheet.dart`).
- **WalletConnect Flows**:
  - Pairing dialog (scan/paste URI) under TopBar QR icon (`lib/main.dart:2248-2319`).
  - Sessions list with dApp cards, account chips, disconnect actions (`lib/walletconnect/ui/wc_sessions_screen.dart`).
  - Request modal summarizing transaction/message payloads, warnings for risky methods (`lib/walletconnect/ui/wc_request_modal.dart`).
- **Placeholders**: Overview tab + Placeholder 3 + Placeholder 4 show instructional gradient cards (`lib/ui/overview_tab_placeholder.dart`, `lib/main.dart:1182`). These slots are earmarked for future feature designs.

## Components & Patterns

- **NeonCard**: Gradient container with 16 px radius, 1.5 px border, used for security info cards and placeholder messaging (`lib/ui/components/neon_card.dart`).
- **BottomNavScaffold**: Column layout with expanded `IndexedStack` + SafeArea-wrapped `BottomNavigationBar` (`lib/ui/components/bottom_nav_scaffold.dart`).
- **Dialogs**: PIN setup/entry, private key import, WalletConnect request/pairing all use `AlertDialog`/`Dialog` with inline validation and action buttons (`lib/ui/dialogs/*.dart`, `lib/main.dart:2248`).
- **Activity Feed**: `ListView.separated` with status-colored avatars and trailing chips (uses default Material colors) (`lib/ui/activity_feed.dart`).

## Interaction & Feedback

- **Status Copy**: `_status` string drives TopBar chip + optional banner. Messages mix system updates (“Ready”, “Sent…”) and validation errors.
- **SnackBars**: Primary error/success surface currently uses transient `SnackBar`s triggered across PIN flows, WalletConnect, settings, clipboard, etc. (`rg "SnackBar" lib`). Requirement: replace with toasts fixed directly under TopBar that persist until next action.
- **Authentication**: PIN + optional biometrics gating for sensitive flows; dialogs show inline red errors on failure (`lib/ui/dialogs/pin_dialog.dart`).
- **Pending Feedback**: Activity entries persist via `SharedPreferences`, updated through `ActivityStore` streams so UI reflects transaction states (`lib/services/activity_store.dart`).

## Configuration & Data Sources

- **Runtime Config**: `assets/config.json` (example in `assets/config.example.json`) defines chain ID, RPC, bundler, EntryPoint, wallet address, WalletConnect project.
- **Tokens Registry**: `assets/tokens.base.json` lists Base/Mainnet + Base Sepolia tokens, decimals, addresses, permit capabilities. Loaded by `ChainTokens.load()` for Send Token UI.
- **Settings Store**: `AppSettings` persisted in secure storage controls biometrics, testnet requirements, custom RPC overrides (`lib/state/settings.dart`).

## Platform Considerations

- Flutter project targets mobile; no explicit orientation enforcement yet. Need to lock portrait in `main.dart` (e.g., `SystemChrome.setPreferredOrientations`) and update platform manifests.
- Shared code assumes phone-sized layout; no responsive breakpoints or tablet variants observed.

## Opportunities & Next Steps

1. **Persistent Toast/Banner System**: Design + implement sticky error/success banners anchored under TopBar to replace all `SnackBar` usages (ensure consistent copy/tone).
2. **Finalize Visual Identity**: Decide on brand colors/accents once logo direction is set; update `cyberpunkTheme` and gradient utilities accordingly, including activity status colors and chips.
3. **Typography & Iconography**: Introduce brand fonts, weight hierarchy, and icon set aligned with logo; document usage tokens to replace Material defaults.
4. **Placeholder Tab Designs**: Define IA and interaction model for the three placeholder tabs (Overview, Placeholder 3, Placeholder 4) now that slots exist.
5. **Orientation Lock**: Enforce portrait mode and verify layout resilience on iPhone SE / Pixel 5 / large phone breakpoints.
6. **Drawer Network Switch**: Determine desired behavior (read-only indicator vs actual network toggle) and design states for active/inactive networks.
7. **Theme Consistency**: Extend neon palette to chips, list dividers, and status badges; audit default Material colors for alignment with brand.

## Outstanding Decisions / Inputs Needed

- Final color palette + gradients once logo is locked.
- Brand typography and any supporting illustration/icon assets.
- Tone & copy guidelines for persistent banners (errors, warnings, confirmations).
- Feature requirements for placeholder tabs to inform layout IA.

_Last updated: YYYY-MM-DD (replace with current date when revising)._
