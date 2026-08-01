# Child Voice Call Figma Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create a new Figma design file containing a reusable design system and a complete Android mobile design for the approved child-facing AI character call experience and adult voice settings.

**Architecture:** Build one Figma file in strict phases: discovery, variable and style foundations, documentation structure, reusable components, child flow, parent settings, and final accessibility/overflow QA. All Figma mutations are sequential and recorded in `/tmp/dsb-state-ds-build-20260801-child-voice-call.json`; every milestone is validated with metadata plus screenshots before the next phase starts.

**Tech Stack:** Figma MCP (`whoami`, `create_new_file`, `use_figma`, `search_design_system`, `get_metadata`, `get_screenshot`), Figma Plugin API, local Flutter/Dart source as the production reference, Noto Sans SC typography.

## Global Constraints

- Target platform is Flutter Android; the reference viewport is 390 × 844 and QA viewports are 360 × 640 and 412 × 915.
- The child flow contains character selection, character-initiated incoming call, half-duplex voice states, hangup, and return to character selection.
- Parent settings opens directly without PIN, system authentication, or arithmetic challenge.
- Preset voice, voice design, and voice clone remain available only in parent settings and are saved per character on the device.
- Current character images are internal prototype assets and must be labeled “仅限内部原型，不可公开分发”.
- No account, login, history, bottom navigation, chat transcript, iOS-specific screens, interruption, or full-duplex behavior.
- All `use_figma` calls are sequential; each call returns every created or mutated node ID.
- Every `use_figma` call loads `figma-use`; Foundations/components also pass `figma-generate-library`, while flow screens also pass `figma-generate-design` in `skillNames`.
- Use the helper scripts shipped with the installed Figma skills for collections, components, documentation, validation, and state rehydration instead of writing monolithic inline scripts.
- Every variable has explicit scopes and Android code syntax; semantic values alias primitives rather than duplicating raw values.
- Every screen is built from local variables, text/effect styles, and component instances wherever a matching design-system asset exists.
- Normal touch targets are at least 48 × 48; accept, decline, and hangup controls are 72–76px.
- Character names occupy one line; call status occupies at most two lines; content must not overflow at 130% text scaling.
- A failed `use_figma` call is inspected before correction; it is never blindly retried.

## File and State Structure

**Created external artifact:**

- Figma file: `儿童 AI 角色电话 · Design System & Mobile Flows`

**Created local state:**

- `/tmp/dsb-state-ds-build-20260801-child-voice-call.json` — run ID, Figma file key/URL, phase, returned node/variable/style IDs, validations, and completed steps.

**Read-only production references:**

- `docs/superpowers/specs/2026-08-01-child-voice-call-figma-design.md`
- `mobile/lib/app.dart`
- `mobile/lib/pages/character_page.dart`
- `mobile/lib/pages/call_page.dart`
- `mobile/lib/widgets/character_card.dart`
- `mobile/lib/widgets/call_avatar.dart`
- `mobile/lib/widgets/incoming_call_actions.dart`
- `mobile/lib/widgets/hangup_button.dart`
- `mobile/lib/controllers/call_state.dart`
- `mobile/assets/characters.json`
- `mobile/assets/characters/labrador_captain.png`
- `mobile/assets/characters/ryder.png`

**Figma pages:**

- `00 Cover` — title, product summary, internal-asset warning.
- `01 Getting Started` — usage, responsive rules, content constraints.
- `02 Foundations` — colors, type, spacing, radius, sizing, effects.
- `03 Components` — component families and variants.
- `04 Child Flow` — character selection, incoming call, active-call states.
- `05 Parent Settings` — three voice modes and upload states.
- `06 States & Specs` — state matrix, error copy, accessibility and overflow QA.

---

### Task 1: Figma Connectivity, New File, and Discovery

**Files:**
- Create: `/tmp/dsb-state-ds-build-20260801-child-voice-call.json`
- Read: approved specification and production references listed above

**Interfaces:**
- Consumes: approved product/design specification and connected Figma MCP server.
- Produces: one blank Figma design file, its `file_key`/URL, library search results, and a locked Phase 1 scope.

- [ ] **Step 1: Verify the required Figma MCP tools are exposed in the active session**

Required tools: `whoami`, `create_new_file`, `use_figma`, `search_design_system`, `get_metadata`, and `get_screenshot`. If any are absent, stop before external writes and reconnect/restart the Figma MCP session.

- [ ] **Step 2: Resolve the destination Figma plan**

Call `whoami`. If exactly one plan is returned, use its `key`. If more than one plan is returned, ask the user to select the destination team before creating a file.

- [ ] **Step 3: Create the blank design file**

Call `create_new_file` with editor type `design` and file name `儿童 AI 角色电话 · Design System & Mobile Flows`. Record the returned `file_key` and `file_url` immediately.

- [ ] **Step 4: Initialize the state ledger**

Create JSON with run ID `ds-build-20260801-child-voice-call`, phase `phase0`, step `inspect-file`, the returned Figma identity, empty entity maps for collections/variables/styles/pages/components/screens, and empty validation/completion arrays.

- [ ] **Step 5: Inspect the new file without mutating it**

Call `use_figma` with `skillNames: "figma-use,figma-generate-library"`. Return all pages, top-level nodes, local variable collections, local text/effect/paint styles, component sets, and available fonts matching `Noto Sans SC`.

- [ ] **Step 6: Search subscribed libraries before building**

Call `search_design_system` separately for `button`, `card`, `avatar`, `input`, `segmented`, `color`, `spacing`, `heading`, and `shadow`, requesting components, variables, and styles. Record results and decide local reuse → subscribed library → create new in that order.

- [ ] **Step 7: Present the final Phase 0 inventory and scope checkpoint**

Report discovered libraries, exact proposed variable collections, styles, components, and any conflict with the approved spec. Await explicit approval to begin Foundations.

---

### Task 2: Foundations — Variables and Styles

**Files:**
- Modify: `/tmp/dsb-state-ds-build-20260801-child-voice-call.json`
- Read: `figma-generate-library/references/token-creation.md`
- Read: `figma-use/references/variable-patterns.md`
- Read: `figma-use/references/text-style-patterns.md`
- Read: `figma-use/references/effect-style-patterns.md`

**Interfaces:**
- Consumes: Phase 0 file key, approved inventory, and verified font availability.
- Produces: primitive/semantic variables, text styles, effect styles, and their exact IDs.

- [ ] **Step 1: Create the `Primitives` collection with one `Value` mode**

Create color variables for white, black, neutral 50/100/200/500/700/900, brand blue 500, call blue 700/950, amber 500, role amber 600, role red 500, destructive red 600, success green 500, and thinking purple 400. Primitive scopes are `[]`; Android syntax uses stable identifiers such as `VoiceTokens.neutral50` and `VoiceTokens.brandBlue`.

- [ ] **Step 2: Validate primitive colors**

Read the collection and return variable names, scopes, Android syntax, and resolved RGBA values. Confirm the count matches the approved token map before continuing.

- [ ] **Step 3: Create the `Color` collection with `Child Light` and `Call Dark` modes**

Create alias-based semantic variables for canvas, surface, elevated surface, text primary/secondary/inverse, border default/subtle, action primary/warm/success/destructive, and state listening/speaking/thinking/error. Use explicit fill, text, or stroke scopes as appropriate.

- [ ] **Step 4: Create `Spacing`, `Radius`, and `Sizing` collections**

Create spacing 4/8/12/16/20/24/32/40 with `GAP` scope; radius 8/12/16/24/full with `CORNER_RADIUS` scope; sizing touch-min 48, call-action 76, call-avatar 176, call-avatar-small 148, screen-width 390, and screen-height 844 with width/height scopes.

- [ ] **Step 5: Validate all numeric collections**

Return collection names, modes, variables, values, scopes, and code syntax. Confirm no variable uses `ALL_SCOPES`.

- [ ] **Step 6: Create text styles sequentially**

Create Noto Sans SC styles: Display 32/40 ExtraBold, Page Title 28/36 ExtraBold, Section Title 22/30 Bold, Component Title 18/26 Bold, Body 16/24 Regular, Body Strong 16/24 Bold, Caption 13/18 Regular, Call Status 20/28 Bold, and Timer 16/24 Regular with tabular figures where supported. Load each font before writing style properties.

- [ ] **Step 7: Create effect styles sequentially**

Create `Elevation/Card`, `Elevation/Floating`, `Elevation/Call Action`, and `Elevation/Call Avatar` using restrained drop shadows that match the approved visual direction.

- [ ] **Step 8: Validate Foundations and request approval**

Return a summary of collection/style counts and render a compact token/type/effect specimen for screenshot review. Await explicit approval before creating page structure.

---

### Task 3: File Structure and Foundation Documentation

**Files:**
- Modify: `/tmp/dsb-state-ds-build-20260801-child-voice-call.json`
- Read: `figma-generate-library/references/documentation-creation.md`

**Interfaces:**
- Consumes: all Foundation IDs from Task 2.
- Produces: seven named pages and navigable documentation frames.

- [ ] **Step 1: Rename the initial page and create the page skeleton**

Create the seven exact pages listed in “Figma pages,” tagging every page with run ID, phase, and logical key via shared plugin data. Return every page ID.

- [ ] **Step 2: Build the Cover page**

Create the product title, one-paragraph summary, Android target badge, and a prominent warning: `当前角色素材仅限内部原型，不可公开分发`.

- [ ] **Step 3: Build Getting Started documentation**

Document child vs parent boundaries, 390 × 844 base frame, 360 × 640 and 412 × 915 QA frames, 130% text scaling, one-line character names, two-line call status, 48px minimum touch target, and 76px call controls.

- [ ] **Step 4: Build Foundation specimens**

Create bound color swatches for both semantic modes, type specimens for all text styles, spacing bars, radius samples, sizing samples, and effect examples.

- [ ] **Step 5: Validate page structure and request approval**

Use metadata to verify names/order and screenshots to verify Cover, Getting Started, and Foundations. Await approval before components.

---

### Task 4: Core Controls and Navigation Components

**Files:**
- Modify: `/tmp/dsb-state-ds-build-20260801-child-voice-call.json`
- Read: `figma-generate-library/references/component-creation.md`
- Read: `figma-use/references/component-patterns.md`

**Interfaces:**
- Consumes: Foundation variable/style IDs and the `03 Components` page ID.
- Produces: local component sets for buttons, call actions, and top bars.

- [ ] **Step 1: Search for reusable controls immediately before creation**

Search `button`, `call action`, and `top bar`. Reuse only assets with compatible properties and token bindings; otherwise create local sets.

- [ ] **Step 2: Create and validate `Button`**

Variants: Style = Primary/Secondary/Destructive; Size = Medium/Large; State = Default/Pressed/Disabled. Add a text `Label` property and optional Boolean leading icon property. Bind fills, text, padding, gaps, height, and radius to variables. Render the variant grid, inspect metadata, screenshot, and obtain approval.

- [ ] **Step 3: Create and validate `CallAction`**

Variants: Type = Accept/Decline/Hangup; State = Default/Pressed/Disabled. Keep every circular touch target 76 × 76, expose a text `Label`, and use success/destructive semantic colors. Validate metadata/screenshot and obtain approval.

- [ ] **Step 4: Create and validate `TopBar`**

Variants: Context = Child/Parent/Call; Back = True/False; Action = None/Parent Settings/Timer. Expose title/action text and keep touch targets at least 48 × 48. Validate metadata/screenshot and obtain approval.

---

### Task 5: Character and Call-State Components

**Files:**
- Modify: `/tmp/dsb-state-ds-build-20260801-child-voice-call.json`

**Interfaces:**
- Consumes: Foundations and core controls.
- Produces: reusable character cards, avatar states, call status, and microphone status.

- [ ] **Step 1: Search for reusable avatar/card/status assets**

Search `character card`, `avatar`, `status`, and `microphone` before local creation.

- [ ] **Step 2: Import the two approved internal raster assets**

Read each PNG as base64 outside Figma, pass one image per sequential `use_figma` call, decode with `figma.base64Decode`, create the image with `figma.createImage`, and record its image hash in the state ledger. Do not expose the images through a public temporary URL. Confirm both hashes resolve in temporary 256 × 256 image-fill frames, then remove only those temporary frames after validation.

- [ ] **Step 3: Create and validate `Avatar / Character`**

Variants: Size = Card/Call/Call Small and State = Default/Listening/Speaking/Thinking/Error. Use an instance-swap image/character property where supported and state-colored rings that do not change component bounds. Validate every state visually and obtain approval.

- [ ] **Step 4: Create and validate `CharacterCard`**

Expose character image, name, subtitle, CTA label, and role theme color. The entire card is interactive; the CTA defaults to `邀请来电`. Use a single-line title and two-line subtitle constraint. Validate both configured characters and obtain approval.

- [ ] **Step 5: Create and validate `MicrophoneStatus`**

Variants: Active/Paused; expose label text. Combine icon, text, opacity, and semantic colors so state is not color-only.

- [ ] **Step 6: Create and validate `CallStatusBlock`**

Variants: Connecting/Speaking/Listening/User Speaking/Processing/Recoverable Error/Ended. Expose role name, status, timer, and microphone status; constrain role name to one line and main status to two lines. Validate the longest approved error copy and obtain approval.

---

### Task 6: Parent-Settings and Feedback Components

**Files:**
- Modify: `/tmp/dsb-state-ds-build-20260801-child-voice-call.json`

**Interfaces:**
- Consumes: Foundations and Button/TopBar sets.
- Produces: settings input, selector, upload, feedback, loading, and dialog components.

- [ ] **Step 1: Create and validate `SegmentedControl / VoiceMode`**

Variants: Selected = Preset/Voice Design/Voice Clone. Labels are `预置音色`, `音色设计`, and `音色克隆`; each segment has at least 48px height.

- [ ] **Step 2: Create and validate `VoiceOptionRow`**

Variants: Selected True/False and Playing True/False. Expose voice name, description, and audition label. Keep selection and audition controls separately identifiable.

- [ ] **Step 3: Create and validate `VoiceDescriptionField`**

Variants: Default/Focused/Error/Disabled. Expose label, hint, content, helper/error, and count text; document the 8–500 Chinese-character constraint.

- [ ] **Step 4: Create and validate `AuthorizedAudioUpload`**

Variants: Empty/Selected/Uploading/Error/Expired. Expose filename and error text. Always display WAV/MP3, 10 MB, and authorized-voice requirements; clamp long filenames with middle truncation.

- [ ] **Step 5: Create and validate feedback families**

Create Banner variants Info/Warning/Error, EmptyState variants Loading Failure NoContent, ConfirmationDialog, and Snackbar variants Success/Error. Validate longest Chinese copy and obtain approval for each family.

---

### Task 7: Child Flow Screens

**Files:**
- Modify: `/tmp/dsb-state-ds-build-20260801-child-voice-call.json`

**Interfaces:**
- Consumes: all approved local component sets, variable IDs, and style IDs.
- Produces: complete child-flow screens on `04 Child Flow`.

- [ ] **Step 1: Create all 390 × 844 wrapper frames first**

Create wrappers for Character Selection, Character Loading, Character Failure, Incoming Call, Connecting, Character Speaking, Listening, User Speaking, Processing, Recoverable Error, Call Ended, and Microphone Denied. Position them in a readable left-to-right flow and return every wrapper ID.

- [ ] **Step 2: Build Character Selection inside its wrapper**

Use the warm storybook surface, `TopBar / Child` with direct `家长设置`, title `今天想邀请谁给你打电话？`, helper text, and the two real internal character images in CharacterCard instances. Validate screenshot and obtain approval.

- [ ] **Step 3: Build Character Loading and Failure states**

Use skeleton/LoadingState for loading and an illustration-style Failure state with `重新加载`. Validate both screens.

- [ ] **Step 4: Build Incoming Call**

Use the dark blurred character-image surface, large call avatar, `AI 角色来电`, `正在呼叫你…`, and CallAction accept/decline instances. Validate minimum 48px spacing between actions and screenshot.

- [ ] **Step 5: Build the active-call state screens one at a time**

Each state uses the approved four-zone grid: 32px top information, flexible avatar region, fixed 126px information region, and fixed 78px bottom control region. Build Connecting, Character Speaking, Listening, User Speaking, Processing, Recoverable Error, and Ended sequentially, validating a screenshot after every screen.

- [ ] **Step 6: Build Microphone Denied**

Use child-safe copy `请找大人帮忙打开麦克风` and a single return-home action; do not expose Android settings jargon or technical errors.

- [ ] **Step 7: Validate the full child flow**

Capture each section/screen individually plus the full flow overview. Audit placeholder text, wrong variants, clipping, overlap, and bottom safe-area violations. Obtain flow approval.

---

### Task 8: Parent Settings Screens

**Files:**
- Modify: `/tmp/dsb-state-ds-build-20260801-child-voice-call.json`

**Interfaces:**
- Consumes: approved parent-settings component families.
- Produces: complete settings screens on `05 Parent Settings`.

- [ ] **Step 1: Create wrapper frames first**

Create 390 × 844 wrappers for Preset Voice, Voice Design, Voice Clone Empty, Voice Clone Selected, Voice Clone Uploading, Voice Clone Error, and Voice Clone Expired.

- [ ] **Step 2: Build Preset Voice**

Use `TopBar / Parent`, character switcher/summary, segmented control, selectable VoiceOptionRow instances, and `保存音色设置`. Show the current values 白桦 for 拉布拉多警长 and 苏打 for 莱德.

- [ ] **Step 3: Build Voice Design**

Use the approved field, role’s existing default voice description, character counter, validation helper, and save states. Validate 8-character error and 500-character maximum behavior visually.

- [ ] **Step 4: Build Voice Clone states sequentially**

Use AuthorizedAudioUpload for Empty, Selected, Uploading, Error, and Expired. Keep the authorization statement visible in every state; use default-preset fallback copy on Expired.

- [ ] **Step 5: Validate the full parent flow**

Screenshot every screen individually and the page overview. Audit long filename truncation, keyboard-safe content region, button visibility, and feedback clarity. Obtain approval.

---

### Task 9: Responsive, Accessibility, and State Specifications

**Files:**
- Modify: `/tmp/dsb-state-ds-build-20260801-child-voice-call.json`

**Interfaces:**
- Consumes: approved child/parent screens and components.
- Produces: small/large viewport evidence and the `06 States & Specs` documentation.

- [ ] **Step 1: Create responsive QA frames**

Create 360 × 640 and 412 × 915 instances/derived layouts for Character Selection, Incoming Call, Listening, Recoverable Error, Voice Design, and Voice Clone Selected.

- [ ] **Step 2: Create 130% text-scale stress frames**

Apply 130% equivalent text sizes to Listening, Recoverable Error with `我刚刚没有听清，可以再说一次吗？`, Voice Design helper text, and a long clone filename. Confirm avatar shrinks before controls and bottom actions remain visible.

- [ ] **Step 3: Document the call state matrix**

Create a table covering Connecting, Speaking, Listening, User Speaking, Processing, Error, and Ended with primary copy, microphone behavior, icon, state-ring color, and reduced-motion fallback.

- [ ] **Step 4: Document accessibility and asset restrictions**

Document contrast, 48/76px targets, non-color status cues, reduced motion, one/two-line limits, Android sizes, and the internal-only asset warning.

- [ ] **Step 5: Validate specs and stress frames**

Capture screenshots at native resolution. Reject any clipped text, overlap, unsafe contrast, or off-screen control and apply targeted fixes before approval.

---

### Task 10: Final Design-System Audit and Handoff

**Files:**
- Finalize: `/tmp/dsb-state-ds-build-20260801-child-voice-call.json`

**Interfaces:**
- Consumes: all Figma entities and validation evidence.
- Produces: approved Figma URL, inventory, audit report, and completed state ledger.

- [ ] **Step 1: Run structural audit**

Enumerate all pages, components, component sets, local variables, styles, screen wrappers, instance/main-component relationships, duplicate names, unnamed nodes, and missing shared run metadata.

- [ ] **Step 2: Run token-binding audit**

Scan design-system components and flow frames for fills, strokes, gaps, padding, and radii lacking variable bindings. Fixed icon geometry and intentionally static dividers are the only allowed exceptions.

- [ ] **Step 3: Run visual audit**

Capture Cover, Foundations, Components, Child Flow, Parent Settings, and States & Specs page overviews, then capture every final mobile screen individually. Check clipping, overlap, placeholder copy, wrong character/voice values, wrong component variants, and safe-area violations.

- [ ] **Step 4: Apply targeted corrections**

Modify only identified nodes; return all mutated IDs; re-run the exact failing metadata/screenshot check after each fix.

- [ ] **Step 5: Complete the state ledger and request sign-off**

Set phase to `complete`, record all entity IDs and passed validations, and provide the Figma URL plus counts of collections, variables, styles, component sets, screens, responsive frames, and unresolved exceptions. Await final user sign-off.
