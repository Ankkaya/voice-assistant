# Child Voice Call Pencil Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create `designs/child-voice-call.pen` as the complete, editable Pencil design source for the approved child-facing AI character call experience and parent voice settings.

**Architecture:** Rebuild the approved design natively in one Pencil document in five dependency-ordered layers: document structure, variables and foundations, reusable components, product screens, and responsive/accessibility evidence. Every mutation is performed through Pencil MCP, recorded in a separate run ledger, then validated with the Pencil node tree, layout diagnostics, and rendered screenshots before dependent work begins.

**Tech Stack:** Pencil MCP (`get_editor_state`, `open_document`, `set_variables`, `get_variables`, `batch_design`, `snapshot_layout`, `get_screenshot`), Pencil `.pen` document, local PNG character assets, Flutter/Dart production references, Noto Sans SC typography.

## Global Constraints

- Target artifact is `designs/child-voice-call.pen`; do not overwrite the archived Figma file or Figma execution ledger.
- Target platform is Flutter Android; the reference viewport is 390 × 844 and QA viewports are 360 × 640 and 412 × 915.
- Child flow contains character selection, character-initiated incoming call, half-duplex voice states, hangup, and return to character selection.
- Parent settings opens directly without PIN, system identity verification, or arithmetic challenge.
- Preset voice, voice design, and voice clone exist only in parent settings and are saved per character on the device.
- Use the production display name `拉布拉多队长`; do not use the old plan typo `拉布拉多警长`.
- Current character images are internal prototype assets and both Cover and States & Specs must say `当前角色素材仅限内部原型，不可公开分发`.
- No account, login, history, bottom navigation, chat transcript, iOS-specific screen, interruption, or full-duplex behavior.
- All visible UI remains as native editable Pencil nodes; never use a full-screen raster image as a completed screen.
- Use 52 logical tokens: 17 primitives, 16 semantic colors with Child Light and Call Dark values, 8 spacing values, 5 radius values, and 6 sizing values.
- Use Pencil reusable components for all repeated controls and screen structures. If Pencil lacks Figma-style variants, use named sibling components with a shared base component.
- Normal touch targets are at least 48 × 48; accept, decline, and hangup controls are 76 × 76.
- Character names occupy one line; main call status occupies at most two lines; layouts must survive 130% text scaling.
- Use Noto Sans SC when available. Map ExtraBold to Black. If unavailable, use the first complete Chinese sans-serif reported by Pencil and record the substitution in Getting Started and the audit.
- Import `mobile/assets/characters/labrador_captain.png` and `mobile/assets/characters/ryder.png` locally; do not upload either asset to a public temporary URL.
- Every `batch_design` call is limited to one coherent component family, one documentation section, or at most three closely related screens.
- After a failed Pencil mutation, inspect the returned error and current node tree before applying a corrected operation; never replay the same batch blindly.
- Preserve the unrelated untracked `.superpowers/` directory.

## File and State Structure

**Create:**

- `designs/child-voice-call.pen` — versioned Pencil design source.
- `/tmp/dsb-state-ds-build-20260802-child-voice-call-pencil.json` — transient run ID, phase, document path, node IDs, validation results, and completed operations.
- `docs/design/child-voice-call-pencil-audit.md` — final coverage, typography substitution, layout checks, and screenshot index.

**Modify during execution:**

- `docs/superpowers/plans/2026-08-02-child-voice-call-pencil.md` — check completed boxes after each accepted task.

**Read-only references:**

- `docs/superpowers/specs/2026-08-02-child-voice-call-pencil-migration-design.md`
- `docs/superpowers/specs/2026-08-01-child-voice-call-figma-design.md`
- `mobile/assets/characters.json`
- `mobile/assets/character_options.json`
- `mobile/assets/characters/labrador_captain.png`
- `mobile/assets/characters/ryder.png`
- `mobile/lib/pages/character_page.dart`
- `mobile/lib/pages/call_page.dart`
- `mobile/lib/pages/character_editor_page.dart`
- `mobile/lib/widgets/character_card.dart`
- `mobile/lib/widgets/call_avatar.dart`
- `mobile/lib/widgets/incoming_call_actions.dart`
- `mobile/lib/widgets/hangup_button.dart`
- `mobile/lib/controllers/call_state.dart`

---

### Task 1: Pencil Connectivity, Document, and Run Ledger

**Files:**
- Create: `designs/child-voice-call.pen`
- Create: `/tmp/dsb-state-ds-build-20260802-child-voice-call-pencil.json`
- Read: `/data/home/.codex/config.toml`

**Interfaces:**
- Consumes: active Pencil MCP registration named `io.github.pencilink/pencil` and the approved specifications.
- Produces: an open, writable Pencil document at the exact target path and a ledger with `documentPath`, `phase`, `sections`, `components`, `screens`, and `validations` maps.

- [ ] **Step 1: Verify the Pencil server is present in the active tool registry**

Confirm the active session exposes all seven required operations: `get_editor_state`, `open_document`, `set_variables`, `get_variables`, `batch_design`, `snapshot_layout`, and `get_screenshot`. If any operation is absent, stop before creating or editing the target document and restart the session after enabling the configured `io.github.pencilink/pencil` server.

- [ ] **Step 2: Inspect the current Pencil editor without mutation**

Call `get_editor_state`. Record the active document path, current selection, supported font information, and whether the editor can create a repository-local document.

- [ ] **Step 3: Create or open the target document**

Call `open_document` for `/projects/voice-assistant/designs/child-voice-call.pen`. If the file does not exist, use the operation's create-new-document behavior. Confirm the returned document path exactly matches the target and that the initial canvas is writable.

- [ ] **Step 4: Initialize the run ledger**

Create `/tmp/dsb-state-ds-build-20260802-child-voice-call-pencil.json` with run ID `ds-build-20260802-child-voice-call-pencil`, phase `document`, the absolute document path, empty maps for `sections`, `variables`, `components`, and `screens`, plus empty `validations` and `completedOperations` arrays.

- [ ] **Step 5: Validate the blank document**

Call `snapshot_layout` at the document root with enough depth to show all top-level nodes. Expected: a valid document with no unexpected imported screens or components. Record the result in the ledger.

- [ ] **Step 6: Commit the initialized artifact**

```bash
git add designs/child-voice-call.pen docs/superpowers/plans/2026-08-02-child-voice-call-pencil.md
git commit -m "design: initialize Pencil voice call document"
```

---

### Task 2: Variables and Foundation Specimens

**Files:**
- Modify: `designs/child-voice-call.pen`
- Modify: `/tmp/dsb-state-ds-build-20260802-child-voice-call-pencil.json`

**Interfaces:**
- Consumes: writable Pencil document from Task 1.
- Produces: 52 named variables plus the `02 Foundations` section ID used by every later component and screen.

- [ ] **Step 1: Create all primitive color variables**

Use `set_variables` to create exactly 17 primitives: white `#FFFFFF`, black `#000000`, neutral 50 `#F6F7FB`, neutral 100 `#FFFFFF`, neutral 200 `#D8DAE2`, neutral 500 `#777C8D`, neutral 700 `#252A3A`, neutral 900 `#111522`, brand blue `#4E72E6`, call blue 700 `#243B73`, call blue 950 `#0D1633`, amber 500 `#F5B83C`, role amber `#E7A93B`, role red `#E64B4B`, destructive red `#E84545`, success green `#31B768`, and thinking purple `#9B7FE8`.

- [ ] **Step 2: Create semantic color variables**

Use `set_variables` to create 16 semantic keys for `canvas`, `surface`, `surface-elevated`, `text-primary`, `text-secondary`, `text-inverse`, `border-default`, `border-subtle`, `action-primary`, `action-warm`, `action-success`, `action-destructive`, `state-listening`, `state-speaking`, `state-thinking`, and `state-error`. Store both Child Light and Call Dark values using Pencil theme modes when supported; otherwise create `/child` and `/call` values under each semantic key.

- [ ] **Step 3: Create numeric variables**

Use `set_variables` for spacing 4/8/12/16/20/24/32/40, radius 8/12/16/24/full, and sizing touch-min 48, call-action 76, call-avatar 176, call-avatar-small 148, screen-width 390, screen-height 844.

- [ ] **Step 4: Read variables back and verify exact coverage**

Call `get_variables`. Expected: 17 primitives, 16 semantic keys, 8 spacing keys, 5 radius keys, and 6 sizing keys; no missing theme value, duplicate key, or malformed color.

- [ ] **Step 5: Create the Foundations section and specimens**

Use one `batch_design` call to create top-level frame `02 Foundations` and bound specimen groups for both color contexts, all nine text styles, spacing bars, radius shapes, sizing targets, and four shadow examples. Use the exact typography and shadow values from the migration specification.

- [ ] **Step 6: Validate Foundations structurally and visually**

Call `snapshot_layout` on `02 Foundations` with `problemsOnly` enabled, then call `get_screenshot` on the section. Expected: no clipping/overlap and all labels readable. Fix any issue before recording the section ID and validation in the ledger.

- [ ] **Step 7: Commit Foundations**

```bash
git add designs/child-voice-call.pen docs/superpowers/plans/2026-08-02-child-voice-call-pencil.md
git commit -m "design: add Pencil foundations"
```

---

### Task 3: File Structure and Documentation Sections

**Files:**
- Modify: `designs/child-voice-call.pen`
- Modify: `/tmp/dsb-state-ds-build-20260802-child-voice-call-pencil.json`

**Interfaces:**
- Consumes: Foundation variables and the `02 Foundations` node.
- Produces: all seven top-level section IDs in final reading order.

- [ ] **Step 1: Create the remaining top-level sections**

Use `batch_design` to create `00 Cover`, `01 Getting Started`, `03 Components`, `04 Child Flow`, `05 Parent Settings`, and `06 States & Specs`. Position all seven sections in a single left-to-right row with 240px between sections and place `02 Foundations` in its correct third position.

- [ ] **Step 2: Build Cover content**

Create the title `儿童 AI 角色电话`, subtitle `Design System & Mobile Flows`, Android badge, migration date, product summary, and a high-visibility warning containing the exact internal-only asset statement.

- [ ] **Step 3: Build Getting Started content**

Document child/parent information boundaries, 390 × 844 base size, 360 × 640 and 412 × 915 QA sizes, 130% text scaling, one-line character names, two-line call status, 48px general targets, 76px call actions, typography substitution, and component reuse rules.

- [ ] **Step 4: Add section navigation and labels**

Add consistent section headers and a compact seven-item contents strip to Cover. Use section numbers and exact names; do not simulate clickable navigation if Pencil does not support prototype links.

- [ ] **Step 5: Validate document organization**

Call `snapshot_layout` at the root. Expected: exactly seven named top-level sections in the specified order, no section overlap, and no unnamed root-level node. Capture Cover, Getting Started, and full-canvas screenshots.

- [ ] **Step 6: Commit documentation structure**

```bash
git add designs/child-voice-call.pen docs/superpowers/plans/2026-08-02-child-voice-call-pencil.md
git commit -m "design: structure Pencil design documentation"
```

---

### Task 4: Core Controls and Navigation Components

**Files:**
- Modify: `designs/child-voice-call.pen`
- Modify: `/tmp/dsb-state-ds-build-20260802-child-voice-call-pencil.json`

**Interfaces:**
- Consumes: all Foundation variables and `03 Components` section ID.
- Produces: reusable `TopBar`, `Button`, and `CallAction` component IDs.

- [ ] **Step 1: Create Button components**

Use `batch_design` to create shared-base Button components for Primary, Secondary, and Destructive styles; Medium and Large sizes; Default, Pressed, and Disabled states. Every variant exposes an editable label, uses variable-bound padding/radius/colors, and preserves a 48px minimum height.

- [ ] **Step 2: Validate Button variants**

Render the complete Button matrix in `03 Components`, run `snapshot_layout` on the matrix, and capture a screenshot. Expected: identical label baselines and no state-dependent size changes.

- [ ] **Step 3: Create CallAction components**

Create Accept, Decline, and Hangup at exactly 76 × 76 with Default, Pressed, and Disabled states. Use editable vector phone glyphs, success/destructive semantic colors, accessible text labels beneath specimen instances, and consistent shadow bounds.

- [ ] **Step 4: Validate CallAction components**

Run layout diagnostics and capture the CallAction matrix. Expected: circular bounds remain 76 × 76 across states and glyphs stay optically centered.

- [ ] **Step 5: Create TopBar components**

Create Child, Parent, and Call contexts with Back True/False and Action None/Parent Settings/Timer siblings. Expose title/action text, preserve 48 × 48 action targets, and bind child/call context colors appropriately.

- [ ] **Step 6: Validate and record core component IDs**

Run `snapshot_layout` on the TopBar specimens and capture the complete core-controls area. Add all reusable component IDs and accepted screenshots to the ledger.

- [ ] **Step 7: Commit core components**

```bash
git add designs/child-voice-call.pen docs/superpowers/plans/2026-08-02-child-voice-call-pencil.md
git commit -m "design: add Pencil core controls"
```

---

### Task 5: Character and Call-State Components

**Files:**
- Modify: `designs/child-voice-call.pen`
- Modify: `/tmp/dsb-state-ds-build-20260802-child-voice-call-pencil.json`
- Read: `mobile/assets/characters/labrador_captain.png`
- Read: `mobile/assets/characters/ryder.png`

**Interfaces:**
- Consumes: Foundation variables, core controls, and two local raster assets.
- Produces: reusable Avatar, CharacterCard, MicrophoneStatus, and CallStatusBlock component IDs plus two internal image references.

- [ ] **Step 1: Import and verify both local character assets**

Insert each PNG from its repository path into a temporary 256 × 256 verification frame without a public URL. Capture both frames, verify the images are not swapped or stretched, record their Pencil image references, then delete only the temporary verification frames.

- [ ] **Step 2: Create Avatar components**

Create Card, Call, and Call Small sizes and Default, Listening, Speaking, Thinking, and Error states. Keep the outer bounds fixed per size; express state with ring color, icon, and opacity rather than changing layout dimensions.

- [ ] **Step 3: Create and configure CharacterCard**

Create a reusable card with image, one-line name, two-line subtitle, role theme accent, and CTA `邀请来电`. Render configured specimens for `拉布拉多队长` / `勇敢又可靠的探险伙伴` / 白桦 and `莱德` / `乐于助人的救援队长` / 苏打.

- [ ] **Step 4: Create MicrophoneStatus**

Create Active and Paused states with distinct glyph, label, opacity, and color. Use labels `麦克风正在聆听` and `麦克风已暂停`; neither state may rely on color alone.

- [ ] **Step 5: Create CallStatusBlock**

Create Connecting, Speaking, Listening, User Speaking, Processing, Recoverable Error, and Ended siblings. Include editable role name, main status, timer, and nested microphone status; role name is one line and main status is at most two lines.

- [ ] **Step 6: Stress-test call components**

Render the longest approved error `我刚刚没有听清，可以再说一次吗？` and a deliberately long test role name `勇敢的拉布拉多探险队长`. Run layout diagnostics and capture Avatar, CharacterCard, and status matrices. Expected: no bound changes, clipping, or overlap.

- [ ] **Step 7: Commit character and call components**

```bash
git add designs/child-voice-call.pen docs/superpowers/plans/2026-08-02-child-voice-call-pencil.md
git commit -m "design: add Pencil character call components"
```

---

### Task 6: Parent-Settings and Feedback Components

**Files:**
- Modify: `designs/child-voice-call.pen`
- Modify: `/tmp/dsb-state-ds-build-20260802-child-voice-call-pencil.json`

**Interfaces:**
- Consumes: Foundations, Button, and TopBar components.
- Produces: reusable voice-mode, input, upload, feedback, dialog, and snackbar component IDs.

- [ ] **Step 1: Create SegmentedControl / VoiceMode**

Create Preset, Voice Design, and Voice Clone selected states with labels `预置音色`, `音色设计`, and `音色克隆`. Each segment is at least 48px tall and remains the same width in every state.

- [ ] **Step 2: Create VoiceOptionRow**

Create Selected True/False and Playing True/False siblings. Expose voice name, description, and audition label, with distinct controls for selection and audition.

- [ ] **Step 3: Create VoiceDescriptionField**

Create Default, Focused, Error, and Disabled states with editable label, content, hint, helper/error, and count. Include specimens for the 8-character validation failure and `500/500` maximum count.

- [ ] **Step 4: Create AuthorizedAudioUpload**

Create Empty, Selected, Uploading, Error, and Expired states. Every state displays WAV／MP3, 10 MB, and `仅使用本人或已明确授权的声音`; Selected uses middle truncation for `一段非常非常长的已授权儿童角色参考声音文件名称.mp3`.

- [ ] **Step 5: Create feedback components**

Create Banner Info/Warning/Error, EmptyState Loading/Failure/No Content, ConfirmationDialog, and Snackbar Success/Error. Use real Chinese copy and reuse the Button component for actions.

- [ ] **Step 6: Validate all settings components**

Run `snapshot_layout` on each component matrix with layout problems enabled and capture screenshots. Expected: no cropped helper text, no long-filename overflow, and stable action placement.

- [ ] **Step 7: Commit settings components**

```bash
git add designs/child-voice-call.pen docs/superpowers/plans/2026-08-02-child-voice-call-pencil.md
git commit -m "design: add Pencil parent settings components"
```

---

### Task 7: Child Flow Screens

**Files:**
- Modify: `designs/child-voice-call.pen`
- Modify: `/tmp/dsb-state-ds-build-20260802-child-voice-call-pencil.json`

**Interfaces:**
- Consumes: all accepted components and `04 Child Flow` section ID.
- Produces: 12 complete 390 × 844 child-flow screen IDs.

- [ ] **Step 1: Create all child-flow screen wrappers**

Create 390 × 844 frames named Character Selection, Character Loading, Character Failure, Incoming Call, Connecting, Character Speaking, Listening, User Speaking, Processing, Recoverable Error, Call Ended, and Microphone Denied. Arrange them in a four-column grid with 96px gaps.

- [ ] **Step 2: Build character selection states**

Build Character Selection with `今天想邀请谁给你打电话？`, helper `选一位伙伴，稍后他会打给你`, direct `家长设置`, and both configured CharacterCard instances. Build Loading from EmptyState Loading and Failure with child-safe copy plus `重新加载`.

- [ ] **Step 3: Build Incoming Call**

Use Call Dark colors, a large image-backed avatar, `AI 角色来电`, `正在呼叫你…`, and 76 × 76 Accept/Decline components separated by at least 48px. Keep content inside Android top/bottom safe areas.

- [ ] **Step 4: Build Connecting, Speaking, and Listening**

Use the shared four-zone active-call shell: 32px top information zone, flexible avatar zone, fixed 126px identity/status zone, and fixed 78px bottom action zone. Populate exact status/microphone combinations from the approved matrix and include Hangup in every live state.

- [ ] **Step 5: Build User Speaking, Processing, and Recoverable Error**

Reuse the same shell and component IDs. Use the stronger blue speaking ring for User Speaking, purple pulse for Processing, and red semantic error ring with `我刚刚没有听清，可以再说一次吗？` for Recoverable Error.

- [ ] **Step 6: Build Call Ended and Microphone Denied**

Call Ended displays `通话已结束` with stopped visual motion and return-home action. Microphone Denied displays `请找大人帮忙打开麦克风` and one return-home action without Android settings jargon.

- [ ] **Step 7: Validate every child screen**

Run `snapshot_layout` on each screen with `problemsOnly` enabled and capture one screenshot per screen plus a section overview. Expected: zero clipping, overlap, off-canvas content, incorrect component state, and bottom safe-area conflict.

- [ ] **Step 8: Commit child flow**

```bash
git add designs/child-voice-call.pen docs/superpowers/plans/2026-08-02-child-voice-call-pencil.md
git commit -m "design: build Pencil child call flow"
```

---

### Task 8: Parent Settings Screens

**Files:**
- Modify: `designs/child-voice-call.pen`
- Modify: `/tmp/dsb-state-ds-build-20260802-child-voice-call-pencil.json`

**Interfaces:**
- Consumes: all accepted parent components and `05 Parent Settings` section ID.
- Produces: seven complete 390 × 844 parent-settings screen IDs.

- [ ] **Step 1: Create all parent screen wrappers**

Create 390 × 844 frames named Preset Voice, Voice Design, Voice Clone Empty, Voice Clone Selected, Voice Clone Uploading, Voice Clone Error, and Voice Clone Expired. Arrange them in a four-column grid with 96px gaps.

- [ ] **Step 2: Build Preset Voice**

Use Parent TopBar, character switcher/summary, segmented control, VoiceOptionRow instances, and `保存音色设置`. Show 白桦 for 拉布拉多队长 and 苏打 for 莱德.

- [ ] **Step 3: Build Voice Design**

Use the selected character's real default voice description from `mobile/assets/characters.json`, the 8～500 count rule, helper/error area, and save action. Include a compact annotation that identifies default, validation, saving, success, and failure states without duplicating full screens.

- [ ] **Step 4: Build Voice Clone Empty, Selected, and Uploading**

Use AuthorizedAudioUpload instances and keep the authorization statement visible above the fold in every state. Selected uses the approved long filename stress string; Uploading keeps navigation visible but disables the save action.

- [ ] **Step 5: Build Voice Clone Error and Expired**

Error offers a retry/select-again action. Expired states that the next call will use the character's default preset voice and asks the parent to select the authorized file again.

- [ ] **Step 6: Validate every parent screen**

Run layout diagnostics and capture each screen plus a section overview. Expected: no long-filename overflow, clipped field helper, obscured authorization statement, or off-screen primary action.

- [ ] **Step 7: Commit parent settings**

```bash
git add designs/child-voice-call.pen docs/superpowers/plans/2026-08-02-child-voice-call-pencil.md
git commit -m "design: build Pencil parent settings flow"
```

---

### Task 9: Responsive, Accessibility, and State Specifications

**Files:**
- Modify: `designs/child-voice-call.pen`
- Modify: `/tmp/dsb-state-ds-build-20260802-child-voice-call-pencil.json`

**Interfaces:**
- Consumes: all approved base screens, components, and `06 States & Specs` section ID.
- Produces: 12 responsive derivatives, six 130% text stress frames, and final state/accessibility documentation.

- [ ] **Step 1: Create 360 × 640 responsive frames**

Create derived layouts for Character Selection, Incoming Call, Listening, Recoverable Error, Voice Design, and Voice Clone Selected. Preserve 48px/76px targets; shrink call avatar toward 148px before reducing vertical spacing.

- [ ] **Step 2: Create 412 × 915 responsive frames**

Create the same six derived layouts. Keep the base typography and touch sizes; use additional vertical space in the flexible avatar/content region rather than scaling controls beyond specification.

- [ ] **Step 3: Create 130% text stress frames**

Duplicate the six 390 × 844 representative screens into a clearly labeled stress-test row and increase all text sizes and line heights by exactly 30%. Keep role names one line with truncation and call status at most two lines.

- [ ] **Step 4: Build the state matrix**

Document Connecting, Assistant Speaking, Listening, User Speaking, Processing, Error, and Ended with exact main copy, microphone copy, ring color, and motion/reduced-motion behavior.

- [ ] **Step 5: Build accessibility and content constraints**

Document WCAG AA contrast intent, multi-channel state expression, reduced motion, Chinese semantic labels, minimum targets, line limits, long filename behavior, safe areas, and internal-only asset warning.

- [ ] **Step 6: Build the interaction and failure-flow map**

Document invitation → incoming call → accept/decline, first microphone permission, connect → speak/listen/process loop, hangup from every live state, recoverable error → listening, unrecoverable error → cleanup/ended, and ended → character selection. Add parent flows for per-character save, upload retry, expired reference, and default-preset fallback.

- [ ] **Step 7: Validate responsive and stress frames**

Run `snapshot_layout` with `problemsOnly` on all 18 validation frames. Capture section overview plus one screenshot for each size/text category. Fix every clipping, overlap, or off-canvas report before recording validation success.

- [ ] **Step 8: Commit responsive specifications**

```bash
git add designs/child-voice-call.pen docs/superpowers/plans/2026-08-02-child-voice-call-pencil.md
git commit -m "design: validate Pencil responsive layouts"
```

---

### Task 10: Final Audit, Evidence, and Delivery

**Files:**
- Modify: `designs/child-voice-call.pen`
- Create: `docs/design/child-voice-call-pencil-audit.md`
- Modify: `docs/superpowers/plans/2026-08-02-child-voice-call-pencil.md`
- Modify: `/tmp/dsb-state-ds-build-20260802-child-voice-call-pencil.json`

**Interfaces:**
- Consumes: completed Pencil document, ledger, rendered screenshots, and migration specification.
- Produces: final validated `.pen` file, written audit, completed plan checklist, and clean scoped commit.

- [ ] **Step 1: Audit the root node tree**

Call `snapshot_layout` at root depth sufficient to list all sections, components, and screens. Verify seven top-level sections, all named component families, 12 child screens, seven parent screens, 12 responsive frames, and six 130% text frames.

- [ ] **Step 2: Audit variables and reuse**

Call `get_variables` and inspect representative screen node trees. Verify all 52 logical tokens exist and repeated UI uses reusable component references rather than detached copies wherever Pencil supports references.

- [ ] **Step 3: Run full layout diagnostics**

Call `snapshot_layout` with layout problems enabled for each top-level section. Expected: zero clipping, overlap, off-canvas, and invalid-size errors. Record each section's result and node ID in the ledger.

- [ ] **Step 4: Capture final visual evidence**

Capture screenshots for the full canvas, Foundations, Components, Child Flow, Parent Settings, States & Specs, Character Selection, Incoming Call, Listening, Recoverable Error, Voice Design, and Voice Clone Selected.

- [ ] **Step 5: Write the audit document**

Create `docs/design/child-voice-call-pencil-audit.md` with document path, commit, exact coverage counts, font used, 52-token counts, component family checklist, screen checklist, responsive/text validation results, internal-asset warning confirmation, and the node IDs corresponding to all final screenshots.

- [ ] **Step 6: Verify the Pencil file is versioned and non-empty**

Run:

```bash
test -s designs/child-voice-call.pen
git status --short
git diff --check
```

Expected: the `.pen` file exists and is non-empty; only the Pencil document, audit, and plan checklist are scoped for the final commit. The unrelated `.superpowers/` directory remains untouched.

- [ ] **Step 7: Mark the implementation plan complete**

Check every completed step in this file, then reread the migration specification and audit document. Expected: every acceptance criterion in specification section 12 maps to explicit audit evidence.

- [ ] **Step 8: Commit final delivery**

```bash
git add designs/child-voice-call.pen docs/design/child-voice-call-pencil-audit.md docs/superpowers/plans/2026-08-02-child-voice-call-pencil.md
git commit -m "design: complete Pencil voice call migration"
```

- [ ] **Step 9: Report the final handoff**

Provide clickable paths to the `.pen` document and audit, the final commit hash, the font actually used, coverage counts, validation result, and the key rendered screenshots. Do not claim completion if any required node, screen, or validation remains missing.
