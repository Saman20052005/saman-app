# Saman Chat — Design to Flutter Implementation Map

This document maps every approved Saman Chat design state to the current Flutter codebase architecture, establishing concrete component boundaries, state responsibilities, and capability realities before any Flutter code is modified.

---

## 1. Current Source Boundaries

| Component / Concern | Current Responsible File(s) | Current Architectural Role |
|---|---|---|
| **App Shell & Root Navigation** | `frontend/lib/screens/main_screen.dart` | Hosts `IndexedStack` with 5 main tabs; controls bottom navigation index; enforces profile completion guard. |
| **Saman Chat Tab Host** | `frontend/lib/screens/main_screen.dart` (index 2) | Mounts `const ChatScreen()` into the `IndexedStack`. |
| **Chat View Screen** | `frontend/lib/screens/chat_screen.dart` | `ConsumerStatefulWidget` owning `_textController`, `_scrollController`, `_scaffoldKey`, header, empty state, message list, drawer, and input area. |
| **Chat State Management** | `frontend/lib/controllers/chat_controller.dart` | `StateNotifier<ChatState>` with `chatControllerProvider`; manages `ChatMessage` list, `isLoading`, `sendMessage()`, and `clearChat()`. |
| **User Context Construction** | `frontend/lib/controllers/chat_controller.dart` (`_buildUserContext`) | Reads biometric and nutrition data from `SharedPreferences` (height, weight, age, TDEE, calories consumed, remaining) to assemble prompt context. |
| **Backend API Client** | `frontend/lib/services/api_client.dart` & `frontend/lib/config/api_config.dart` | Dio HTTP client sending `POST ${ApiConfig.baseUrl}/api/chat` with `{message, context, history}`. |
| **Markdown Rendering** | `frontend/lib/screens/chat_screen.dart` | Uses `flutter_markdown` (`MarkdownBody`) with `MarkdownStyleSheet`. |
| **Assistant Drawer** | `frontend/lib/screens/chat_screen.dart` (`_buildModernDrawer`) | Standard `Drawer` with app logo, "Cuộc trò chuyện mới", analytics prompt shortcut, menu prompt shortcut, and persona dialog. |
| **Composer / Input Dock** | `frontend/lib/screens/chat_screen.dart` (`_buildInputArea`) | Text input with action chips carousel, attachment button (currently shows SnackBar placeholder), mic button, and green send button. |
| **Quick Suggestions** | `frontend/lib/screens/chat_screen.dart` (`_quickSuggestions`) | Hardcoded list of Vietnamese suggestion strings rendered as horizontal `ActionChip`s. |
| **Conversation Reset** | `frontend/lib/screens/chat_screen.dart` & `chat_controller.dart` | App bar trash action calling `clearChat()`. |
| **Initial Message Ingestion** | `frontend/lib/screens/chat_screen.dart` (`widget.initialMessage`) | Populates `_textController.text` in `initState()` when opened from external deep-links/prompts. |
| **Autoscroll Handling** | `frontend/lib/screens/chat_screen.dart` (`_scrollToBottom`) | Post-frame callback animating `_scrollController` to `maxScrollExtent`. |
| **Shared Bottom Navigation** | `frontend/lib/screens/home/widgets/saman_bottom_navigation_bar.dart` | Centralized bottom nav bar on `MainScreen` with 5 navigation items. |
| **Design System Tokens** | `frontend/lib/screens/home/tokens/saman_home_tokens.dart` | Pitch obsidian canvas (`#0C0D0E`), charcoal surfaces (`#16171B`), graphite borders (`#26282F`), and Saman Green (`#10B981`). |

---

## 2. Approved State to Flutter Component Mapping

### 01 Empty / New Conversation
- **Design Source:** `screens/01-empty-state.png` | `references/01-empty-state/`
- **Current Source:** `frontend/lib/screens/chat_screen.dart` (`_buildEmptyState()`)
- **Likely Implementation Areas:**
  - Replace the current centered generic column with the approved layout:
    - 20x20px charcoal `S` monogram badge
    - Headline: *"Your coach is ready"*
    - Subtitle: *"Ask about training, meals, recovery, or what to do next."*
    - Contextual Today card (*"Legs & Chain · 45 min · RPE 8.5 · 35g protein left"*)
    - 3 structured action rows (*"Review today's workout"*, *"Plan next meal"*, *"Check recovery"*)
    - Rapid-query chips row docked above composer
- **Existing Behavior to Preserve:**
  - Quick prompt tap triggers immediate message submission via `_handleSend()`
  - `widget.initialMessage` handling
  - Full compatibility with `chatControllerProvider`

---

### 02 Active Conversation
- **Design Source:** `screens/02-active-conversation.png` | `references/02-active-conversation/`
- **Current Source:** `frontend/lib/screens/chat_screen.dart` (`_buildMessageBubble()`), `chat_controller.dart`
- **Likely Implementation Areas:**
  - User message: Right-aligned dark charcoal bubble (`#1E2024`, border `#23252A`), off-white text (replaces bright green bubble)
  - Assistant message: Left-aligned direct canvas rendering with `S` monogram + title-case `Saman` header and timestamp
  - Inline context cards: Support rendering compact training and nutrition status cards directly inside or below assistant messages
  - Adaptive quick-reply chips above composer
- **Existing Behavior to Preserve:**
  - Chronological message history
  - `ChatMessage(role: 'user' | 'assistant')` role semantics
  - Autoscroll to latest response
  - Markdown text parsing for body copy

---

### 03 Food Photo Result
- **Design Source:** `screens/03-food-photo-result.png` | `references/03-food-photo-result/`
- **Current Source:** Extended rendering within `chat_screen.dart`; backend connection currently in `ai_analysis_result.dart`
- **Likely Implementation Areas:**
  - Rich assistant message widget rendering:
    - User meal image thumbnail preview
    - Assistant conversational confirmation text
    - Structured "Meal estimate" card: Dish title, estimated calories (`~620 kcal` in Saman Green), macro distribution chips (Protein, Carbs, Fat) with indicator dots
    - Remaining budget progress bar
    - Primary CTA: `Log meal →` (navigates to meal logging flow or logs meal directly via `nutrition_provider.dart`)
- **Existing Behavior to Preserve:**
  - When implemented, must wire into existing `NutritionProvider` / `FoodLogScreen` meal addition logic rather than creating parallel mock state.

---

### 04 Reminder / Proactive Nudge
- **Design Source:** `screens/04-reminder-nudge.png` | `references/04-reminder-nudge/`
- **Current Source:** `frontend/lib/screens/chat_screen.dart`
- **Likely Implementation Areas:**
  - Top-of-thread proactive coaching nudge banner/bubble:
    - Remaining calorie and protein statement
    - Primary CTA: `Plan dinner →`
    - Secondary CTA: `Later`
  - Active notification indicator dot on app bar bell icon
- **Existing Behavior to Preserve:**
  - Tapping `Plan dinner →` sends prompt to `chatController.sendMessage("What should I eat for dinner based on remaining macros?")`

---

### 05 Typing / Generating
- **Design Source:** `screens/05-typing-generating.png` | `references/05-typing-generating/`
- **Current Source:** `frontend/lib/screens/chat_screen.dart` (current `msg.isTyping` indicator), `chat_controller.dart` (`isLoading`)
- **Likely Implementation Areas:**
  - Assistant message: Restrained 3-dot pulsing bubble with contextual status line (*"Reviewing your recent training..."*)
  - Composer dock:
    - Input disabled with placeholder *"Saman is responding..."*
    - Send button transforms into neutral monochrome square stop control
- **Existing Behavior to Preserve:**
  - Controlled cleanly by `chatState.isLoading`

---

### 06 Food Photo Analysis Loading
- **Design Source:** `screens/06-food-photo-analysis.png` | `references/06-food-photo-analysis/`
- **Current Source:** Extension of `chat_screen.dart` input & loading state
- **Likely Implementation Areas:**
  - Displays user message with attached photo preview thumbnail
  - Assistant response in scanning state: *"Looking at your meal..."* + *"Checking the portion and main ingredients..."* + subtle dots
  - Composer shows *"Saman is looking at your meal..."* with stop control
- **Existing Behavior to Preserve:**
  - Must represent a true asynchronous loading state without fabricating mock calorie data prematurely

---

### 07 Recoverable Error
- **Design Source:** `screens/07-recoverable-error.png` | `references/07-recoverable-error/`
- **Current Source:** `chat_controller.dart` catch block (currently appends `"⚠️ Có lỗi xảy ra: $e"`)
- **Likely Implementation Areas:**
  - Replace raw technical exception strings with calm coach recovery UI:
    - Message: *"I couldn't complete that response."*
    - Action button: `Retry →` in Saman Green (re-triggers last query)
    - Action button: `Edit question` in neutral gray (copies prompt back into composer)
  - No red error banners, no raw Dio exception dumps
- **Existing Behavior to Preserve:**
  - Re-tries the last failed query using `sendMessage()`

---

### 08 Food Photo Failure
- **Design Source:** `screens/08-food-photo-failure.png` | `references/08-food-photo-failure/`
- **Current Source:** Extension of error presentation in `chat_screen.dart`
- **Likely Implementation Areas:**
  - Meal photo remains visible in user bubble
  - Assistant explanation: *"I couldn't estimate this meal confidently from the photo."*
  - Bulleted tips: full plate visible, better lighting, top-down angle
  - Dual CTAs: `Retake photo →` (re-opens camera) and `Enter meal manually →` (navigates to manual food log screen)
- **Existing Behavior to Preserve:**
  - `Enter meal manually →` deep-links directly to existing `FoodLogScreen`

---

### 09 Long Response / Markdown / Table
- **Design Source:** `screens/09-long-response-table.png` | `references/09-long-response-table/`
- **Current Source:** `frontend/lib/screens/chat_screen.dart` (`MarkdownBody`)
- **Likely Implementation Areas:**
  - Structured multi-section Markdown layout with headings: **Training**, **Nutrition**, **Tomorrow**
  - Numbered list item cards with rounded badge indicators (1, 2, 3)
  - Compact mobile comparison table with columns: `Metric`, `Today`, `Target`
  - Contextual action buttons: `Adjust tomorrow's workout →` and `Plan breakfast →`
  - Feedback action row: Thumbs up, thumbs down, copy response
- **Existing Behavior to Preserve:**
  - Uses `flutter_markdown` table support, customized via `MarkdownStyleSheet` with dark obsidian table borders and cells

---

### 10 Full-Height Drawer
- **Design Source:** `screens/10-full-height-drawer.png` | `references/10-full-height-drawer/`
- **Current Source:** `frontend/lib/screens/chat_screen.dart` (`_buildModernDrawer()`)
- **Likely Implementation Areas:**
  - Full-height drawer styled to ~80% width with obsidian background (`#111215`, border `#23252A`) and dark scrim
  - Identity header: `Saman · Your personal coach`
  - Primary button: `+ New conversation` (calls `clearChat()`)
  - **Recent** conversation list: 4 items (*"Upper body form check"*, *"Post-workout meal plan"*, etc.) + `View all conversations →`
  - **Coach tools**: Weekly review, Nutrition review, Workout analysis (wired to existing screen/prompt handlers)
  - Reminders row with active count badge
  - Saman preferences entry point
- **Existing Behavior to Preserve:**
  - Drawer open trigger via app bar hamburger icon
  - Navigation handlers for weekly review and nutrition analysis
  - Persona switching dialog integration

---

## 3. Global Structural Elements Mapping

### Global Header
- **Design:** Top bar with `[≡]` menu icon, `[S]` monogram badge (20x20), `Saman Coach` title, `[✎]` new chat icon, `[🔔]` notification bell with optional active dot.
- **Current Implementation:** `chat_screen.dart` `AppBar` shows `Icons.dashboard_customize_outlined`, `AppLogo(24)`, `AI Coach`, and delete trash icon.
- **Refactor Target:** Update title to `Saman Coach`, replace logo with `S` monogram, replace dashboard icon with hamburger `Icons.menu`, add edit and notification icons.

### Global Composer Dock
- **Design:** Docked pill with `[+]` attachment tool, text field *"Ask Saman about training, meals, recovery..."*, `[mic]` voice input, and neutral monochrome send button `[↑]`.
- **Current Implementation:** `chat_screen.dart` `_buildInputArea()` uses separate add icon, text field *"Hỏi AI Coach..."*, and bright green send button.
- **Refactor Target:** Encapsulate into a dedicated `SamanComposer` widget using neutral gray send button, integrated attachment popup, and theme-token background.

### Global Bottom Navigation
- **Design:** Central 5-item navigation: Home, Workout, [S] Saman, Nutrition, Profile.
- **Current Implementation:** Already provided globally by `MainScreen` via `SamanBottomNavigationBar`.
- **Rule:** `ChatScreen` must **never** embed its own bottom navigation bar; it relies entirely on the shell.

---

## 4. Real vs. Future Capability Matrix

| Design Capability | Current Real Support | Current Source Evidence | Implementation Status |
|---|---|---|---|
| **Text Chat (Send/Receive)** | **SUPPORTED** | `chat_controller.dart` `sendMessage()`, `api/chat` endpoint | Functional with live backend |
| **Markdown Rendering** | **SUPPORTED** | `chat_screen.dart` `MarkdownBody` | Functional |
| **Message History (In-memory)** | **SUPPORTED** | `ChatState.messages` in `chat_controller.dart` | In-memory session history |
| **Message History (Persistent)** | **NOT CURRENTLY WIRED** | `chat_controller.dart` does not persist chat to DB/Prefs | Ephemeral session only |
| **Clear Conversation** | **SUPPORTED** | `ChatController.clearChat()` | Functional |
| **Quick Prompt Suggestions** | **SUPPORTED** | `_quickSuggestions` list in `chat_screen.dart` | Functional |
| **Deep-link Initial Message** | **SUPPORTED** | `ChatScreen.initialMessage` parameter | Functional |
| **Coach Persona Configuration** | **PARTIAL** | `_showPersonaDialog()` in `chat_screen.dart` | Sets prompt persona in context |
| **Full-Height Drawer** | **PARTIAL** | `_buildModernDrawer()` in `chat_screen.dart` | Functional logic, legacy styling |
| **Assistant Drawer Tools** | **PARTIAL** | Dispatches hardcoded prompts to chat | Prompt-based integration |
| **Typing / Loading State** | **SUPPORTED** | `ChatState.isLoading` | Functional |
| **Recoverable Error Handling** | **PARTIAL** | Catch block in `chat_controller.dart` | Appends error message, needs clean UI |
| **Markdown Tables** | **SUPPORTED** | `MarkdownStyleSheet` table properties | Supported by `flutter_markdown` |
| **Food Photo Upload via Chat** | **NOT CURRENTLY WIRED** | SnackBar shows *"Tính năng Gửi ảnh/Tool sẽ sớm ra mắt!"* | UI stub only; no chat image endpoint |
| **Food Photo Analysis in Chat** | **PRESENTATION ONLY** | `ai_analysis_result.dart` exists in nutrition, not wired to chat | Model exists, chat pipeline absent |
| **Voice Dictation Input** | **PRESENTATION ONLY** | UI icon only; no speech-to-text package integrated | Presentation only |
| **Proactive Reminder / Nudges** | **PRESENTATION ONLY** | SharedPreferences has nutrition data; no push/trigger system | Presentation only |
| **Rich Structured Message Cards** | **NOT CURRENTLY WIRED** | `ChatMessage` only has `String role`, `String content` | Model extension required |
| **Biometric Context Grounding** | **SUPPORTED** | `_buildUserContext()` in `chat_controller.dart` | Reads TDEE, weight, height, eaten |

---

## 5. Home Design System Reuse Strategy

### Tokens to REUSE Directly from `SamanHomeTokens`
- **Canvas & Surface Colors:**
  - `SamanHomeTokens.canvas` (`#0C0D0E`) — Chat screen background
  - `SamanHomeTokens.cardSurface` (`#16171B`) — Card containers, drawer background
  - `SamanHomeTokens.cardSurfaceElevated` (`#1B1D22`) — User chat bubbles, elevated cards
  - `SamanHomeTokens.border` (`#26282F`) & `borderSubtle` (`#23252A`) — Hairline card borders
  - `SamanHomeTokens.divider` (`#1F2126`) — Drawer and list dividers
- **Typography & Label Colors:**
  - `SamanHomeTokens.textWhite` (`#FFFFFF`), `textPrimary` (`#F3F4F6`), `textSecondary` (`#94979E`), `textMuted` (`#71717A`)
- **Instrumentation Accents:**
  - `SamanHomeTokens.greenAccent` (`#10B981`) — Semantic green for CTAs, positive status, and macro badges
  - `SamanHomeTokens.carbsAmber` (`#F59E0B`) — Carbohydrate telemetry
  - `SamanHomeTokens.fatViolet` (`#A855F7`) — Dietary fat telemetry
  - `SamanHomeTokens.progressTrack` (`#202227`) — Progress bar track fill
- **Spacings & Border Radii:**
  - `SamanHomeTokens.radiusSm` (8), `radiusMd` (12), `radiusLg` (16), `radiusXl` (20), `radiusPill` (9999)
  - `SamanHomeTokens.spacingSm` (8), `spacingMd` (12), `spacingLg` (16), `spacingXl` (20)

### What Remains Chat-Specific
- Speech bubble geometry: Asymmetrical rounded corners (`topLeft: 16`, `topRight: 16`, `bottomLeft: 16`, `bottomRight: 4` for user; reverse for assistant)
- Monogram badge component: 20x20 charcoal rounded square with geometric white `S`
- Multimodal composer pill docking styles
- Markdown typography styling sheet (`MarkdownStyleSheet` tailored for obsidian contrast)
- Three-dot animated pulsing wave indicator
