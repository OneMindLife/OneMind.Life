# OneMind Tutorial Flow: Complete Step-by-Step Trace

This document traces every step of the OneMind tutorial, documenting the exact user experience from first launch through completion and the subsequent home tour.

The tutorial uses **template-based content** -- the user chooses a topic scenario (Personal, Family, Community, Workplace, Government, World) and all propositions, winners, and questions are customized to that template. This document uses the **Community** template as a running example, noting where template-specific content applies.

---

## Overview

The tutorial has two phases:

1. **Chat Tutorial** (TutorialStep enum) -- Teaches how chats work: proposing, rating, results, consensus, sharing
2. **Home Tour** (HomeTourStep enum) -- Teaches the home screen UI after the chat tutorial ends

### TutorialStep Enum Values (in order)
```
intro
chatTourTitle, chatTourMessage, chatTourProposing, chatTourParticipants
round1Proposing, round1Rating, round1Result
round2Prompt, round2Proposing, round2Rating, round2Result
round3CarryForward, round3Proposing, round3Rating, round3Consensus
shareDemo
complete
```

### HomeTourStep Enum Values (in order)
```
welcomeName, searchBar, pendingRequest, yourChats, createFab
exploreButton, languageSelector, howItWorks, legalDocs
complete
```

### Progress Dots
A row of 12 progress dots is shown below the app bar throughout the chat tutorial. Each dot maps to a segment:
- 0: intro
- 1: chatTour (all 4 sub-steps)
- 2: round1Proposing
- 3: round1Rating
- 4: round1Result
- 5: round2Prompt / round2Proposing
- 6: round2Rating
- 7: round2Result
- 8: round3CarryForward / round3Proposing
- 9: round3Rating
- 10: round3Consensus
- 11: shareDemo

---

## Phase 1: Introduction & Template Selection

### Step 1: `intro`

**Screen:** Full-screen intro panel. App bar shows title "OneMind Tutorial" with a close (X) button (tooltip: "Skip Tutorial"). The body contains:
- A large groups icon at the top
- Welcome text
- 6 template cards (Personal, Family, Community, Workplace, Government, World)
- Legal agreement links
- A "Skip tutorial" text button at the bottom

**Text shown:**
- Title: `"Welcome to OneMind!"`
- Description: `"Bring people together to share ideas anonymously, rate independently, and reach results everyone can trust."`
- Subtitle: `"Choose a topic to practice with"`
- Template cards:
  - Personal: `"Personal Decision"` / `"What should I do after graduation?"`
  - Family: `"Family"` / `"Where should we go on vacation?"`
  - Community: `"Community Decision"` / `"What should our neighborhood do together?"`
  - Workplace: `"Workplace Culture"` / `"What should our team focus on?"`
  - Government: `"City Budget"` / `"How should we spend the city budget?"`
  - World: `"Global Issues"` / `"What global issue matters most?"`
- Legal text: `"By continuing, you agree to our"` `"Terms of Service"` `"and"` `"Privacy Policy"` `"."`
- Skip button: `"Skip tutorial"`

**New concepts introduced:**
- OneMind exists and is about group decision-making
- There are different scenarios/contexts where consensus-building applies
- The concept of a "chat" as a discussion container (implied by templates)

**User action:** Tap one of the 6 template cards to select a scenario.

**Assumptions:**
- User understands English (or their selected language)
- User understands the concept of agreeing to terms of service

**Skip dialog (if user taps X or "Skip tutorial"):**
- Title: `"Skip Tutorial?"`
- Message: `"You can always access the tutorial later from the home screen."`
- Buttons: `"Continue Tutorial"` / `"Yes, Skip"`

---

## Phase 2: Chat Tour (Progressive Reveal)

After template selection, the user enters a dedicated tour screen that progressively reveals chat screen elements one at a time. A TourTooltipCard (floating card with title, description, progress dots, Next/Skip buttons) animates between positions. Each element starts invisible (opacity 0.0), becomes fully visible (1.0) when spotlighted, then dims to 0.25 as the tour advances.

The app bar shows the template-specific chat name (e.g., `"Community"`) and a participants icon button + close button.

**Note on bottom area layout:** The tutorial uses a single-column layout (no tabs). When a previous round winner exists, a compact amber-bordered "Previous Winner" card appears inline above the proposing input or rate button.

### Step 2: `chatTourTitle`

**Screen:** The chat name in the app bar is at full opacity. Everything else (message area, proposing input, participants button) is invisible. The tooltip card appears just below the app bar.

**Text shown (TourTooltipCard):**
- Title: `"Chat Name"`
- Description: `"This is the chat name. Each chat has a topic everyone discusses together."`
- Progress: `"Step 1 of 4"` with 4 dots
- Buttons: `"Skip tour"` / `"Next"`

**New concepts introduced:**
- A "chat" has a name
- Each chat has a topic

**User action:** Tap "Next" to continue, or "Skip tour" to jump to Round 1.

**Assumptions:** None significant -- this is purely orienting.

---

### Step 3: `chatTourMessage`

**Screen:** The chat name is now dimmed (0.25). The "Initial Message" card appears at full opacity in the body area, showing the template's discussion question (e.g., `"What should our neighborhood do together?"`). The tooltip card animates below the message card.

**Text shown (TourTooltipCard):**
- Title: `"Discussion Question"`
- Description: `"This is the question being discussed. Everyone submits ideas in response."`
- Progress: `"Step 2 of 4"`
- Buttons: `"Skip tour"` / `"Next"`

**Text shown (message card):**
- Label: `"Initial Message"`
- Content: Template description text (e.g., `"What should our neighborhood do together?"`)

**New concepts introduced:**
- Chats have an "Initial Message" -- a question or prompt
- Participants submit ideas in response to the question

**User action:** Tap "Next".

**Assumptions:** User understands Q&A format.

---

### Step 4: `chatTourProposing`

**Screen:** The message card dims to 0.25. The bottom area (proposing input) appears at full opacity. Shows a label `"Your Proposition"`, a disabled text field with placeholder `"Share your idea..."`, and a disabled `"Submit"` button. The tooltip card animates above the proposing area.

**Text shown (TourTooltipCard):**
- Title: `"Submit Ideas"`
- Description: `"This is where you submit ideas. Each round, everyone proposes and then rates. The highest-rated idea wins the round."`
- Progress: `"Step 3 of 4"`
- Buttons: `"Skip tour"` / `"Next"`

**Text shown (proposing area):**
- Tab: `"Your Proposition"`
- Input placeholder: `"Share your idea..."`
- Button: `"Submit"`

**New concepts introduced:**
- "Propositions" are ideas you submit
- The process repeats as the group narrows down (iterative nature hinted)

**User action:** Tap "Next".

**Assumptions:**
- What happens after proposing is not yet explained

---

### Step 5: `chatTourParticipants`

**Screen:** The proposing area dims to 0.25. The participants icon button in the app bar appears at full opacity. The tooltip card appears at the top of the body (just below app bar).

**Text shown (TourTooltipCard):**
- Title: `"Participants"`
- Description: `"Meet your tutorial participants: Alice, Bob, and Carol. Tap here to see who's in the chat."`
- Progress: `"Step 4 of 4"`
- Buttons: `"Skip tour"` / `"Got it!"`

**New concepts introduced:**
- Chats have multiple participants
- Other people (Alice, Bob, Carol) are participating
- You can view who is in the chat

**User action:** Tap "Got it!" (the last step label). This transitions to Round 1.

**Assumptions:**
- User understands that Alice, Bob, and Carol are simulated participants

---

## Phase 3: Round 1 -- Proposing, Rating, and Results

### Step 6: `round1Proposing`

**Screen:** Full chat screen layout. App bar: "OneMind Tutorial" with participants icon and close button. Body: progress dots (segment 2 active), Initial Message card showing the template question. Bottom area: an active text field with placeholder `"Share your idea..."`, a `"Submit"` button with countdown timer.

An educational hint banner appears above the proposing input:
- Lightbulb icon + hint text + countdown

**Text shown:**
- Hint: `"Submit your idea — it'll compete against everyone else's."` followed by `"You have Xm Xs left."`
- Input placeholder: `"Share your idea..."`
- Button: `"Submit (Xm Xs)"`

**Template propositions already exist (hidden from user, used in rating):**
- Community example: "Block Party", "Community Garden", "Neighborhood Watch"

**New concepts introduced:**
- You submit an idea that competes against others
- There is a time limit (countdown timer)
- The concept of proposing as a phase

**User action:** Type an idea into the text field and tap "Submit".

**Assumptions:**
- User understands that their idea competes with others
- The timer concept is introduced but the consequence of it expiring is explained in the next step

**Duplicate detection:** If the user submits an idea identical to a template proposition:
- Snackbar: `"This idea already exists in this round. Try something different!"`

---

### Step 7: `round1Rating`

**Screen:** After submission, the bottom area shows a `"Start Rating"` button with countdown. A hint banner appears. The rating screen auto-opens.

**Text shown (before rating screen opens):**
- Hint: `"Rate each idea. The highest-rated one wins the round."` followed by `"You have Xm Xs left to rate."`
- Button: `"Start Rating (Xm Xs)"`

**Rating Screen (auto-opens as a pushed route):**
- App bar: `"Rate Ideas"` with close (X) button (tooltip: "Skip Tutorial")
- The user rates propositions from other participants (3 template props; their own is excluded)

**Rating Phase 1: Binary**
- Hint: `"The top idea scores higher. Tap [swap] to put your preferred idea on top, then [check] to confirm."`
  - `[swap]` renders as an inline swap_vert icon button
  - `[check]` renders as an inline check icon button

**Rating Phase 2: Positioning**
- Hint: `"Place each idea on the scale. Use [up] [down] to move, then [check] to confirm."`
  - `[up]`, `[down]`, `[check]` render as inline icon buttons

**New concepts introduced:**
- Rating phase: the highest-rated idea wins the round (connects rating to outcome)
- Binary comparison: top idea scores higher (spatial = scoring connection established)
- Positioning: place ideas on a scale where higher = better
- Zoom and undo controls exist but are discoverable (not mentioned in hints)

**User action:** Complete the binary comparison (swap/confirm), then position all remaining ideas on the grid. The rating widget calls onComplete when done.

**Assumptions:**
- The scale meaning ("higher means better") is now explicitly stated in the positioning hint
- Undo/zoom controls are discoverable by doing, not mentioned in hints
- The grid metaphor for ranking is learned by doing

---

### Step 8: `round1Result`

**Screen:** After rating completes, the results screen auto-opens as a pushed route.

**Results Screen (ReadOnlyResultsScreen):**
- App bar: `"Round 1 Results"` with back arrow and close (X) button
- Hint banner: `"'{winner}' won! Press the back arrow when done viewing the results."`
  - e.g., `"'Community Garden' won! Press the back arrow when done viewing the results."`
- Grid showing all propositions positioned by their final ratings (winner at 100, others descending)

**Auto-advance:** When the user dismisses the results screen (back arrow), the tutorial automatically advances to Round 2 proposing. There is no intermediate result step — the user goes directly from viewing results to proposing their next idea.

**New concepts introduced:**
- Rounds have winners (shown in the results grid)
- The results grid visually shows where each idea ranked

**User action:** View the results grid, tap back arrow → auto-advances to Round 2.

**Assumptions:**
- The "must win again" rule is not stated here — it's introduced via the inline winner card in R2 and confirmed by demonstration in R3

---

## Phase 4: Round 2 -- Building on the Previous Winner

### Step 9: `round2Prompt`

**Screen:** Auto-advanced from Round 1 results. The round is now Round 2 (proposing phase). The bottom area shows:
1. An intro hint announcing the R1 winner (introduces the winner card below)
2. An inline "Previous Winner" card (amber-bordered, trophy icon) displaying the R1 winner
3. The proposing input

**Text shown:**
- Intro hint: Community template: `"'Community Garden' won Round 1!"` / Classic: `"'Success' won Round 1!"`
- Previous Winner card: Shows R1 winner (e.g., "Community Garden")
- Input placeholder: `"Share your idea..."`
- Button: `"Submit (Xm Xs)"`

**Template Round 2 propositions (hidden, used in rating):**
- Community example: "Tool Library", "Mutual Aid Fund", "Community Garden" (carried forward)

**New concepts introduced:**
- R1 result announced (who won)
- The "Previous Winner" card is introduced — shows the winner visually
- The previous winner competes alongside new ideas (implied by its presence)

**User action:** Type a new idea and tap "Submit".

**Assumptions:**
- The intro hint + winner card together communicate that R1 had a winner and it's still in play
- User naturally infers they should try to beat it

---

### Step 10: `round2Rating`

**Screen:** The rating screen auto-opens. Same layout as Round 1 rating but without the binary hint (showHints=false). However, a carry-forward hint appears during the positioning phase.

**Rating Screen:**
- App bar: `"Rate Ideas"` with back arrow and close (X) button
- During positioning phase only, hint: `"This is last round's winner. If it wins again, it's decided!"`

**New concepts introduced:**
- Carry-forward propositions are explicitly identified during rating
- If a carried-forward winner wins again, "it's decided" — stakes are raised

**User action:** Complete binary comparison, then position all ideas. The tutorial is rigged so the user's proposition wins.

**Assumptions:**
- The carry-forward hint only appears during positioning, so the user must reach that phase to see it
- "It's decided" builds on the "must win again" rule from Round 1 — still no jargon

---

### Step 11: `round2Result` (transient)

**This step is auto-advanced.** After R2 rating completes, the tutorial immediately transitions to Round 3 proposing. The user never sees an intermediate result screen for Round 2.

The R2 result information (user's idea won) is communicated in the next step via:
1. The inline "Previous Winner" card showing the user's winning idea
2. An educational hint about convergence

**New concepts introduced:** None at this step — deferred to R3 proposing.

**User action:** None (automatic transition).

---

## Phase 5: Round 3 -- Consensus

### Step 12: `round3Proposing`

**Screen:** Round 3 proposing phase, auto-advanced from R2 result. The bottom area shows:
1. An intro hint announcing the user's R2 win + convergence opportunity
2. An inline "Previous Winner" card showing the user's R2 winning idea
3. The proposing input

**Text shown:**
- Intro hint: `"Your idea won! If it wins again, the group reaches convergence."`
- Previous Winner card: Shows user's R2 winning idea
- Input placeholder: `"Share your idea..."`
- Button: `"Submit (Xm Xs)"`

**Template Round 3 propositions (hidden):**
- Community example: "Free Little Library", "Street Mural", "Skill-Share Night"

**Note:** The user's Round 2 winner is automatically carried forward as one of the propositions. The user can also submit a NEW proposition. Both will appear in rating. (The carried forward one will win regardless -- the tutorial is rigged.)

**New concepts introduced:**
- The user's idea won R2 (communicated here, not in a separate result step)
- "Convergence" term introduced — winning again means the group reaches convergence
- Your winning proposition automatically advances (shown via inline winner card)
- You can submit additional new ideas even when you have a carried-forward proposition

**User action:** Type a new idea and tap "Submit".

**Assumptions:**
- The inline winner card makes it clear the previous winner is already in play
- "Convergence" is introduced naturally as the goal, not as jargon

---

### Step 13: `round3Rating`

**Screen:** The rating screen auto-opens. No special hints (showHints=false, isRound2=false).

**Rating Screen:**
- App bar: `"Rate Ideas"` with back arrow and close (X) button
- Standard binary comparison then positioning

**New concepts introduced:** None new -- this is practice.

**User action:** Complete the rating. The tutorial is rigged so the user's carried-forward proposition (from Round 2) wins again.

**Assumptions:**
- User knows how to rate from previous rounds
- User understands their carried-forward proposition is in the mix

---

### Step 14: `round3Consensus`

**Screen:** After rating completes, the main tutorial screen shows a special state:
- The entire chat UI is dimmed to 0.25 opacity EXCEPT the Initial Message, the consensus card, and the tooltip
- The Initial Message remains fully visible so the user sees the convergence result in context with the original question
- A "Convergence #1" message card appears in the chat body at full opacity, containing the user's winning proposition
- A TourTooltipCard floats below the consensus card

**Text shown:**
- Convergence card label: `"Convergence #1"`
- Convergence card content: The user's winning proposition text

**TourTooltipCard:**
- Title: `"Convergence Reached!"`
- Description: `"\"{userProposition}\" won 2 rounds in a row."`
  - e.g., `"\"Free Wi-Fi\" won 2 rounds in a row."`
- Progress: `"Step 1 of 2"` with 2 dots
- Buttons: `"Skip tour"` / `"Continue"`

**New concepts introduced:**
- "Convergence" is the term for consensus (group agreement)
- The rule is confirmed: winning 2 rounds in a row = convergence
- Convergence items are displayed as special cards in the chat history

**User action:** Tap "Continue".

**Assumptions:**
- "Convergence" has been consistently used throughout, so this confirmation feels natural
- The 2-consecutive-wins rule is now fully demonstrated

---

## Phase 6: Share Demo

### Step 15: `shareDemo`

**Screen:** Still dimmed layout. A share icon button appears in the app bar (in addition to participants and close). A TourTooltipCard floats near the top of the body.

**TourTooltipCard:**
- Title: `"Share Your Chat"`
- Description: `"To invite others to join your chat, tap the share button at the top of your screen."`
- Progress: `"Step 2 of 2"` with 2 dots
- Buttons: `"Skip tour"` / `"Share Your Chat"` (the next button is labeled "Share Your Chat")

**Share button tooltip:** `"Share Chat"`

**New concepts introduced:**
- You can share your chat with others
- There is a share button in the app bar

**User action:** Tap the "Share Your Chat" button on the tooltip card. This opens the QR code share dialog.

**QR Code Share Dialog:**
- Title: `"Share link to join {chatName}"` (e.g., "Share link to join Community")
- Shows the full invite URL
- `"Share"` button (copies link + opens native share sheet)
- `"or scan"` divider
- QR code image
- `"Or enter code manually:"` with the invite code `"ABC123"`
- Tutorial hint: `"Tap the Continue button to continue the tutorial."`
- `"Continue"` button (prominent FilledButton)

**New concepts introduced:**
- Invite links: you share a URL to invite others
- QR codes: people can scan to join
- Invite codes: a 6-character code alternative
- Multiple sharing methods (link, QR, manual code)

**User action:** Tap "Continue" on the share dialog. The dialog closes and the tutorial advances to the complete step.

**Assumptions:**
- User understands QR codes
- User understands that in a real chat, they would share with actual people

---

## Phase 7: Completion Transition

### Step 16: `complete`

**Screen:** The chat screen fades out (600ms animation), then a centered transition message fades in (500ms). Clean screen with transparent app bar (only close button).

**Text shown:**
- Green checkmark icon
- Title: `"Chat tutorial complete!"`
- Description: `"Now let's take a quick look at the home screen, where you'll find all your chats."`
- Button: `"Continue"` (FilledButton with arrow icon)

**New concepts introduced:**
- There is a "home screen" where all chats live
- The tutorial has a second phase (home tour)

**User action:** Tap "Continue". This triggers the onComplete callback, which navigates to the home tour.

**Assumptions:**
- User understands that more orientation is coming
- User expects to see a "home screen" next

---

## Phase 8: Home Tour (Post-Tutorial)

The home tour uses the same TourTooltipCard pattern as the chat tour. A mock home screen is progressively revealed. Each widget starts invisible, becomes bright when spotlighted, then dims.

The app bar shows "OneMind" (dimmed) with app bar action buttons that reveal progressively. A close button (tooltip: "Skip tour") is always visible.

### Step H1: `welcomeName`

**Screen:** The welcome header appears: `"Welcome, Brave Fox"` with a pencil edit icon. The tooltip card appears below the header.

**Text shown:**
- Mock header: `"Welcome, Brave Fox"` (with edit icon)
- TourTooltipCard:
  - Title: `"Your Display Name"`
  - Description: `"This is your display name. Tap the pencil icon to change it anytime!"`
  - Progress: `"Step 1 of 9"` with 9 dots
  - Buttons: `"Skip tour"` / `"Next"`

**New concepts introduced:**
- You have a display name
- Your name is shown on the home screen
- You can change your name

**User action:** Tap "Next".

**Assumptions:** "Brave Fox" is a placeholder name; in reality the user's anonymous name is shown.

---

### Step H2: `searchBar`

**Screen:** The search bar appears at full opacity: `"Search your chats or enter invite code..."`. The tooltip card appears below it.

**Text shown:**
- Search placeholder: `"Search your chats or enter invite code..."`
- TourTooltipCard:
  - Title: `"Search Your Chats"`
  - Description: `"Filter your chats by name, or enter a 6-character invite code to join a private chat."`
  - Progress: `"Step 2 of 9"`
  - Buttons: `"Skip tour"` / `"Next"`

**New concepts introduced:**
- You can search/filter your chats
- You can join a private chat by entering a 6-character invite code in the search bar

**User action:** Tap "Next".

**Assumptions:**
- User understands what "private chat" means
- The search bar's dual purpose (search + join) is a new pattern

---

### Step H3: `pendingRequest`

**Screen:** A "Pending Requests" section appears with a mock pending card: "Book Club" / "What should we read next?" / "Waiting for host approval". The tooltip card appears below.

**Text shown:**
- Section header: `"Pending Requests"`
- Mock card:
  - Name: `"Book Club"`
  - Subtitle: `"What should we read next?"`
  - Status: `"Waiting for host approval"`
- TourTooltipCard:
  - Title: `"Pending Requests"`
  - Description: `"When you request to join a chat, the host reviews your request. You'll see it here with a 'Pending' badge until they approve."`
  - Progress: `"Step 3 of 9"`
  - Buttons: `"Skip tour"` / `"Next"`

**New concepts introduced:**
- Joining a chat may require host approval
- Pending requests are visible on the home screen
- There is a review/approval workflow

**User action:** Tap "Next".

**Assumptions:**
- User understands the concept of "host" (the person who created the chat)
- The approval workflow details are not explained (just that it exists)

---

### Step H4: `yourChats`

**Screen:** A "Your Chats" section appears with two mock chat cards:
1. "OneMind" / "..." / 12 participants / Proposing phase / EN+ES languages
2. "Weekend Plans" / "What should we do this Saturday?" / 4 participants / Rating phase / EN language

**Text shown:**
- Section header: `"Your Chats"`
- TourTooltipCard:
  - Title: `"Your Chats"`
  - Description: `"Your active chats appear here. Each card shows the current phase, participant count, and languages."`
  - Progress: `"Step 4 of 9"`
  - Buttons: `"Skip tour"` / `"Next"`

**New concepts introduced:**
- Active chats are listed on the home screen
- Each chat card shows: current phase, participant count, languages
- Chats can be in different phases (proposing, rating)
- Multi-language support exists

**User action:** Tap "Next".

**Assumptions:**
- User notices the phase indicators and language badges on the cards
- The distinction between proposing/rating phases should be familiar from the chat tutorial

---

### Step H5: `createFab`

**Screen:** A floating action button (+) appears in the bottom-right corner at full opacity. All body cards dim. The tooltip card appears above the FAB.

**Text shown:**
- TourTooltipCard:
  - Title: `"Create a Chat"`
  - Description: `"Tap + to create your own chat. You choose the topic, invite friends, and build consensus together."`
  - Progress: `"Step 5 of 9"`
  - Buttons: `"Skip tour"` / `"Next"`

**New concepts introduced:**
- You can create your own chat
- Chat creation involves choosing a topic and inviting friends
- "Build consensus together" reinforces the app's purpose

**User action:** Tap "Next".

**Assumptions:**
- User understands the FAB (floating action button) pattern from other apps

---

### Step H6: `exploreButton`

**Screen:** All body cards dimmed. The Explore icon (compass) in the app bar appears at full opacity. The tooltip card appears at the top of the body.

**Text shown:**
- Button tooltip: `"Discover Chats"`
- TourTooltipCard:
  - Title: `"Explore Public Chats"`
  - Description: `"Tap here to discover and join public chats created by other users."`
  - Progress: `"Step 6 of 9"`
  - Buttons: `"Skip tour"` / `"Next"`

**New concepts introduced:**
- There are "public chats" anyone can join
- You can discover chats created by other users
- The Explore button is the entry point

**User action:** Tap "Next".

**Assumptions:**
- User understands the difference between public and private chats

---

### Step H7: `languageSelector`

**Screen:** The Language icon (globe) in the app bar appears at full opacity. The tooltip card appears at the top of the body.

**Text shown:**
- Button tooltip: `"Language"`
- TourTooltipCard:
  - Title: `"Change Language"`
  - Description: `"Tap here to switch the app language. OneMind is available in English, Spanish, Portuguese, French, and German."`
  - Progress: `"Step 7 of 9"`
  - Buttons: `"Skip tour"` / `"Next"`

**New concepts introduced:**
- The app supports multiple languages
- You can change the app language from the home screen

**User action:** Tap "Next".

**Assumptions:** None significant.

---

### Step H8: `howItWorks`

**Screen:** The Help icon (question mark) in the app bar appears at full opacity. The tooltip card appears at the top of the body.

**Text shown:**
- Button tooltip: `"How it works"`
- TourTooltipCard:
  - Title: `"How It Works"`
  - Description: `"Need a refresher? Tap here to replay the tutorial anytime."`
  - Progress: `"Step 8 of 9"`
  - Buttons: `"Skip tour"` / `"Next"`

**New concepts introduced:**
- The tutorial can be replayed anytime

**User action:** Tap "Next".

**Assumptions:** None.

---

### Step H9: `legalDocs`

**Screen:** The Legal icon (document) in the app bar appears at full opacity. The tooltip card appears at the top of the body.

**Text shown:**
- Button tooltip: `"Legal"`
- TourTooltipCard:
  - Title: `"Legal Documents"`
  - Description: `"View the Privacy Policy and Terms of Service here."`
  - Progress: `"Step 9 of 9"`
  - Buttons: `"Skip tour"` / `"Got it!"`

**New concepts introduced:**
- Legal documents are accessible from the home screen

**User action:** Tap "Got it!" (last step). This marks the home tour as complete.

**Assumptions:** None.

---

### Step H10: `complete`

**Screen:** The tour ends. The onComplete callback fires, navigating the user to the real home screen.

**Text shown:** None (immediate transition).

**User action:** None (automatic).

---

## Summary: Knowledge Progression

| Phase | Key Concepts Introduced |
|-------|------------------------|
| Intro | OneMind is for group decisions; pick a topic |
| Chat Tour | Chat name, discussion question, proposing input (rounds + rating explained), participants |
| Round 1 Proposing | Submit idea to compete against others, time limits |
| Round 1 Rating | Highest-rated wins; Binary: top scores higher; Positioning: higher = better |
| Round 1 Result | Results grid shows ranked ideas (auto-advances to R2 after viewing) |
| Round 2 Proposing | Inline winner card shows R1 winner; improve on it |
| Round 2 Rating | Carry-forward propositions identified, "it's decided" raises stakes |
| Round 2 Result | (Transient — auto-advances to R3) |
| Round 3 Proposing | "Your idea won! If it wins again, convergence." — convergence term introduced |
| Round 3 Rating | Practice (no new hints) |
| Round 3 Consensus | Convergence = 2 consecutive wins confirmed by demonstration |
| Share Demo | Invite links, QR codes, invite codes |
| Completion | Home screen exists, transition to home tour |
| Home Tour | Display name, search/join, pending requests, active chats, create, explore, language, tutorial replay, legal docs |

## Summary: Assumptions and Knowledge Gaps

1. **Grid rating mechanics** -- The binary hint establishes "top idea scores higher" and the positioning hint states "higher means better", giving users the key conceptual anchor from both phases. Undo/zoom controls are discoverable by doing rather than explained in text.

2. **Round timing** -- The rating phase explanation now states the consequence: "If you don't submit in time, the round continues without your idea."

3. **Carry-forward mechanics** -- Explained across multiple steps (R1 result, R2 rating, R2 result) using consistent "convergence" terminology. Users piece it together incrementally.

4. **Convergence confirmation rounds** -- The tutorial uses 2 confirmation rounds (the default). Users who encounter chats with different settings won't have been prepared for that.

5. **Propositions per user** -- The tutorial uses 1 proposition per user per round. Multi-proposition mode is not demonstrated.

6. **Host controls** -- The tutorial user is marked as host but never exercises host powers (starting phases, advancing, pausing). The concept of host vs. participant roles is not taught.

7. **Credits/billing** -- Not mentioned in the tutorial at all. Users discover this when creating real chats.

8. **Cycles** -- The term "cycle" (a sequence of rounds working toward convergence) is never used in the tutorial. Users only see "rounds" and "convergence".

9. **Anonymous proposing** -- The tutorial doesn't explicitly state that propositions are anonymous during rating. Users discover this naturally as they rate ideas without seeing who submitted them.

10. **Real-time collaboration** -- The tutorial simulates everything locally. Users may not realize that in real chats, other participants are submitting and rating simultaneously in real-time.

## Template-Specific Content Reference

### Propositions by Template

| Template | R1 Props | R1 Winner | R2 Props | R3 Props |
|----------|----------|-----------|----------|----------|
| Personal | Travel Abroad, Start a Business, Graduate School | Graduate School | Get a Job First, Take a Gap Year, Graduate School | Freelance, Move to a New City, Volunteer Program |
| Family | Beach Resort, Mountain Cabin, City Trip | Beach Resort | Road Trip, Camping Adventure, Beach Resort | Cruise, Theme Park, Cultural Exchange |
| Community | Block Party, Community Garden, Neighborhood Watch | Community Garden | Tool Library, Mutual Aid Fund, Community Garden | Free Little Library, Street Mural, Skill-Share Night |
| Workplace | Flexible Hours, Mental Health Support, Team Building | Mental Health Support | Skills Training, Open Communication, Mental Health Support | Fair Compensation, Work-Life Balance, Innovation Time |
| Government | Public Transportation, School Funding, Emergency Services | Emergency Services | Road Repairs, Public Health, Emergency Services | Affordable Housing, Small Business Grants, Parks & Recreation |
| World | Climate Change, Global Poverty, AI Governance | Climate Change | Pandemic Preparedness, Nuclear Disarmament, Climate Change | Ocean Conservation, Digital Rights, Space Cooperation |

### Questions by Template

| Template | Question (shown as Initial Message) |
|----------|-------------------------------------|
| Personal | What should I do after graduation? |
| Family | Where should we go on vacation? |
| Community | What should our neighborhood do together? |
| Workplace | What should our team focus on? |
| Government | How should we spend the city budget? |
| World | What global issue matters most? |

### Chat Names by Template

| Template | Chat Name |
|----------|-----------|
| Personal | Personal Decision |
| Family | Family |
| Community | Community |
| Workplace | Workplace |
| Government | City Budget |
| World | Global Issues |

### Rigged Outcomes

- **Round 1:** Template's designated winner always wins (user's proposition gets score 0, winner gets 100)
- **Round 2:** User's proposition always wins (score 100), carried-forward R1 winner gets 67
- **Round 3:** User's carried-forward R2 proposition wins again (score 100) = **CONVERGENCE**

### Tutorial Participants

| Name | Role | ID |
|------|------|----|
| You | Host | -1 |
| Alice | Participant | -2 |
| Bob | Participant | -3 |
| Carol | Participant | -4 |
