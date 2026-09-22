# Saman Chat — Implementation Risks & Mitigation Strategies

This document catalogs observed technical, architectural, and visual risks identified during the design-to-code mapping of the Saman Chat redesign.

---

## Risk 1: Current Chat UI is Visually Legacy/Theme-Dependent vs. Approved Obsidian Foundation
- **Risk:** `ChatScreen` currently relies on legacy `AppThemeExtension` (`context.bgColor`, `colors.primary` user bubbles, `Icons.smart_toy_outlined` robot icon, `AI Coach` title), creating an inconsistent aesthetic contrast with the approved dark obsidian design system.
- **Evidence / Source:** `frontend/lib/screens/chat_screen.dart` (lines 54, 64, 176, 187).
- **Safe Implementation Strategy:** Adopt `SamanHomeTokens` directly for background (`canvas`), surfaces (`cardSurface`), and borders (`borderSubtle`), updating user bubbles to dark charcoal (`#1E2024`) and replacing the robot icon with the approved `S` monogram badge without altering Riverpod state logic.

---

## Risk 2: Rich State Presentations Exceed Current `ChatMessage` Data Model
- **Design Requirement:** States 03 (Food Photo Result), 04 (Reminder Nudge), and 09 (Long Response with action CTAs) require rendering structured metadata (macro chips, caloric progress bars, actionable buttons).
- **Evidence / Source:** `frontend/lib/controllers/chat_controller.dart` defines `ChatMessage` as:
  ```dart
  class ChatMessage {
    final String role;
    final String content;
    final bool isTyping;
  }
  ```
  It has no fields for structured payload, image URLs, or action buttons.
- **Safe Implementation Strategy:** During Phase 1 of UI implementation, parse structured patterns from the Markdown content or introduce an optional, backward-compatible `Map<String, dynamic>? metadata` field on `ChatMessage` without breaking existing string-based messages.

---

## Risk 3: Food Photo Analysis Pipeline Does Not Currently Exist in Chat Endpoint
- **Design Requirement:** States 03, 06, and 08 assume uploading a meal photo into the chat thread and receiving an AI nutritional analysis.
- **Evidence / Source:** In `frontend/lib/screens/chat_screen.dart` (line 304), tapping the attachment icon displays:
  ```dart
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text("Tính năng Gửi ảnh/Tool sẽ sớm ra mắt!"))
  );
  ```
  The chat endpoint `/api/chat` only accepts `{message, context, history}` without multipart image support.
- **Safe Implementation Strategy:** Treat multimodal photo interactions as visual preview states or hook the camera trigger directly to the existing `NutritionScreen` / `FoodLogScreen` camera service. Do not invent an unverified chat image upload API.

---

## Risk 4: Proactive Reminder / Nudge State (State 04) Lacks Automated Trigger Pipeline
- **Design Requirement:** State 04 displays a proactive assistant check-in (*"You still have 620 kcal and 35g protein left today..."*) before the user sends a message.
- **Evidence / Source:** `ChatController` only appends assistant messages in direct response to user `sendMessage()` HTTP responses. There is no background push event or client trigger injecting proactive cards into `ChatState.messages`.
- **Safe Implementation Strategy:** Check remaining nutrition values in `SharedPreferences` upon entering `ChatScreen` and render a top-docked suggestion card when calories remain, or simulate it gracefully as a contextual suggestion chip above the composer.

---

## Risk 5: Leaking Technical Dio/Server Exceptions into Chat UI
- **Risk:** Network timeouts, server 500 errors, or formatting failures currently display raw technical Dart/Dio exception strings directly inside an assistant message.
- **Evidence / Source:** `frontend/lib/controllers/chat_controller.dart` (lines 80–84):
  ```dart
  } catch (e) {
    state = state.copyWith(messages: [
      ...state.messages,
      ChatMessage(role: 'assistant', content: "⚠️ Có lỗi xảy ra: $e")
    ], isLoading: false);
  }
  ```
- **Safe Implementation Strategy:** Update the error handler to flag `isError: true` or present the calm approved State 07 layout (*"I couldn't complete that response."* with `Retry →` and `Edit question`), logging `$e` to debug console without leaking raw stack traces to the user.

---

## Risk 6: Duplicate Bottom Navigation Bar
- **Risk:** Chat screen designs show a bottom navigation bar, which could lead to adding a nested `BottomNavigationBar` inside `ChatScreen`.
- **Evidence / Source:** `frontend/lib/screens/main_screen.dart` already centrally hosts `SamanBottomNavigationBar` for all 5 tabs in an `IndexedStack`.
- **Safe Implementation Strategy:** `ChatScreen` must never render its own bottom navigation bar; the global shell handles all bottom navigation.

---

## Risk 7: State 02 and State 09 Visual Snapshot Micro-Styling Mismatches
- **Risk:** Developers relying solely on `screen.png` for State 02 and 09 could implement uppercase `SAMAN`, `Saman COACH` badge, or `TELEMETRY SYNCED`.
- **Evidence / Source:** Documented in `design/saman-chat/SCREEN-STATUS.md`.
- **Safe Implementation Strategy:** Enforce the documented exception rule: for State 02 and State 09, `SCREEN-STATUS.md` and `code.html` supersede the outdated screenshot text artifacts.
