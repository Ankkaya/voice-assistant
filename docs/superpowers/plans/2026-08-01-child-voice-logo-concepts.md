# Child Voice Logo Concepts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Generate six professional, independently reviewable Logo concepts for the child voice-call app and package them with reproducible prompts and small-size comparison sheets.

**Architecture:** Use the bundled imagegen CLI directly with `gpt-image-2` and one fully authored JSONL job per concept. Persist the prompt set and generated PNGs under a project-local output directory, then use Pillow only as a local post-processing dependency to assemble comparison sheets without changing the generated candidates.

**Tech Stack:** OpenAI Image API, bundled `image_gen.py` CLI, `gpt-image-2`, JSONL, PNG, Python 3, Pillow.

## Global Constraints

- Produce a pure graphic mark with no brand name, letters, numbers, or slogan.
- The core concept is an original, rounded, friendly “voice buddy” with a small amount of sound-wave rhythm integrated into its structure.
- The tone is warm and playful without appearing infantile.
- Use brand blue `#4E72E6` and warm yellow `#F5B83C`; use warm white only as a neutral background or minimal supporting color.
- Use a flat, geometric, modern, vector-friendly visual language with a clear outer silhouette.
- Request a centered `1024x1024` square canvas with generous, consistent safety padding; accept a larger square response from the configured endpoint when both edges are at least `1024px`.
- Do not include telephones, receivers, microphones, headphones, call buttons, robots, mechanical parts, circuit textures, generic chatbot symbols, complex gradients, realistic 3D, glass, metal, heavy shadows, watermarks, or imitations of existing brands and characters.
- Use `gpt-image-2` with `quality=high`; do not set `input_fidelity` or request transparent output.
- Treat generated PNGs as concept candidates, not final release-ready vector artwork.

---

### Task 1: Generate Six Independent Logo Candidates

**Files:**
- Create: `output/imagegen/child-voice-logo-concepts/prompts.jsonl`
- Create: `output/imagegen/child-voice-logo-concepts/01-wave-silhouette.png`
- Create: `output/imagegen/child-voice-logo-concepts/02-wave-ears.png`
- Create: `output/imagegen/child-voice-logo-concepts/03-negative-space-wave.png`
- Create: `output/imagegen/child-voice-logo-concepts/04-gentle-pulse.png`
- Create: `output/imagegen/child-voice-logo-concepts/05-dual-sound-buddy.png`
- Create: `output/imagegen/child-voice-logo-concepts/06-contained-app-icon.png`

**Interfaces:**
- Consumes: `OPENAI_API_KEY`, `OPENAI_BASE_URL` when configured, `.python-deps/openai`, and `/data/home/.codex/skills/.system/imagegen/scripts/image_gen.py`.
- Produces: six square PNG files with stable numeric names and the exact JSONL prompt set used to generate them.

- [ ] **Step 1: Verify the CLI runtime and credential without printing secret values**

Run:

```bash
test -n "${OPENAI_API_KEY:-}" && \
PYTHONPATH=.python-deps python3 -c 'import openai; print(openai.__version__)' && \
python3 /data/home/.codex/skills/.system/imagegen/scripts/image_gen.py generate-batch --help >/dev/null
```

Expected: exit code `0`; the command prints the installed OpenAI Python package version and does not print the API key.

- [ ] **Step 2: Create the reproducible six-job prompt set**

Create `output/imagegen/child-voice-logo-concepts/prompts.jsonl` with exactly these six JSON objects, one per line:

```jsonl
{"out":"01-wave-silhouette.png","model":"gpt-image-2","size":"1024x1024","quality":"high","output_format":"png","use_case":"logo-brand","prompt":"Create an original pure graphic logo mark for a voice-companion app for children ages 6 to 9. The mark is one friendly rounded abstract voice buddy whose outer silhouette is formed by three broad, soft sound-wave lobes. Give it a tiny calm smile and two minimal dot eyes, with mature restraint rather than babyish cuteness.","style":"professional vector logo mark, flat geometric shapes, minimal, modern, warm and playful, vector-friendly","composition":"one centered standalone mark, strong recognizable silhouette, balanced negative space, generous consistent padding, plain warm-white background","palette":"brand blue #4E72E6 and warm yellow #F5B83C only, with warm white as neutral background","constraints":"pure graphic icon; no text, letters, numbers, slogan, watermark; no phone, receiver, microphone, headphones, call button, robot, mechanical parts, circuit pattern, generic chatbot bubble; no gradients, mockup, 3D, glass, metal, heavy shadow; no imitation of existing brands or characters"}
{"out":"02-wave-ears.png","model":"gpt-image-2","size":"1024x1024","quality":"high","output_format":"png","use_case":"logo-brand","prompt":"Create an original pure graphic logo mark for a voice-companion app for children ages 6 to 9. Design one simple rounded abstract buddy with two symmetrical ear-like forms that subtly echo sound-wave arcs without resembling headphones. Use an economical face with two dot eyes and a gentle confident expression.","style":"professional vector logo mark, flat geometric shapes, minimal, modern, warm and playful, vector-friendly","composition":"one centered standalone mark, clear compact silhouette, balanced symmetry with one memorable asymmetrical detail, generous consistent padding, plain warm-white background","palette":"brand blue #4E72E6 and warm yellow #F5B83C only, with warm white as neutral background","constraints":"pure graphic icon; no text, letters, numbers, slogan, watermark; no animal species, phone, receiver, microphone, headphones, call button, robot, antenna, mechanical parts, circuit pattern, generic chatbot bubble; no gradients, mockup, 3D, glass, metal, heavy shadow; no imitation of existing brands or characters"}
{"out":"03-negative-space-wave.png","model":"gpt-image-2","size":"1024x1024","quality":"high","output_format":"png","use_case":"logo-brand","prompt":"Create an original pure graphic logo mark for a voice-companion app for children ages 6 to 9. Use one bold rounded buddy silhouette, with a single smooth sound wave revealed through internal negative space. The negative-space wave should also suggest a subtle friendly smile without becoming a speech bubble.","style":"professional vector logo mark, clever negative space, flat geometric shapes, minimal, modern, warm and playful, vector-friendly","composition":"one centered standalone mark, extremely clear outer silhouette, one elegant internal cutout, generous consistent padding, plain warm-white background","palette":"brand blue #4E72E6 and warm yellow #F5B83C only, with warm white as neutral background","constraints":"pure graphic icon; no text, letters, numbers, slogan, watermark; no phone, receiver, microphone, headphones, call button, robot, mechanical parts, circuit pattern, generic chatbot bubble; no gradients, mockup, 3D, glass, metal, heavy shadow; no imitation of existing brands or characters"}
{"out":"04-gentle-pulse.png","model":"gpt-image-2","size":"1024x1024","quality":"high","output_format":"png","use_case":"logo-brand","prompt":"Create an original pure graphic logo mark for a voice-companion app for children ages 6 to 9. Design one soft pebble-shaped buddy with a small yellow heart-like voice pulse integrated into its center as an abstract rhythm, not a literal heart. Keep the outer character calm, friendly, and self-assured with minimal facial detail.","style":"professional vector logo mark, flat geometric shapes, minimal, modern, warm and playful, vector-friendly","composition":"one centered standalone mark, stable rounded silhouette, small integrated pulse detail, generous consistent padding, plain warm-white background","palette":"brand blue #4E72E6 and warm yellow #F5B83C only, with warm white as neutral background","constraints":"pure graphic icon; no text, letters, numbers, slogan, watermark; no literal heart icon, phone, receiver, microphone, headphones, call button, robot, mechanical parts, circuit pattern, generic chatbot bubble; no gradients, mockup, 3D, glass, metal, heavy shadow; no imitation of existing brands or characters"}
{"out":"05-dual-sound-buddy.png","model":"gpt-image-2","size":"1024x1024","quality":"high","output_format":"png","use_case":"logo-brand","prompt":"Create an original pure graphic logo mark for a voice-companion app for children ages 6 to 9. Combine two simple rounded sound units into one cohesive friendly buddy. Their facing edges should create a rhythmic central negative space that suggests listening and responding, while the total silhouette reads as one character rather than two people.","style":"professional vector logo mark, flat geometric shapes, minimal, modern, warm and playful, vector-friendly","composition":"one centered unified mark, strong compact silhouette, balanced two-part construction, generous consistent padding, plain warm-white background","palette":"brand blue #4E72E6 and warm yellow #F5B83C only, with warm white as neutral background","constraints":"pure graphic icon; no text, letters, numbers, slogan, watermark; no phone, receiver, microphone, headphones, call button, robot, mechanical parts, circuit pattern, generic chatbot bubble; no gradients, mockup, 3D, glass, metal, heavy shadow; no imitation of existing brands or characters"}
{"out":"06-contained-app-icon.png","model":"gpt-image-2","size":"1024x1024","quality":"high","output_format":"png","use_case":"logo-brand","prompt":"Create an original pure graphic logo mark for a voice-companion app for children ages 6 to 9. Place one minimal rounded yellow voice buddy inside a simple brand-blue circular container. Integrate two small sound-wave notches into the buddy silhouette so the character feels alive and vocal without using a literal audio device.","style":"professional vector logo mark, flat geometric shapes, minimal, modern, warm and playful, vector-friendly","composition":"one centered emblem, simple circle container, clear buddy silhouette, excellent app-icon readability, generous consistent padding, plain warm-white background","palette":"brand blue #4E72E6 and warm yellow #F5B83C only, with warm white as neutral background","constraints":"pure graphic icon; no rounded-square app mockup, no text, letters, numbers, slogan, watermark; no phone, receiver, microphone, headphones, call button, robot, mechanical parts, circuit pattern, generic chatbot bubble; no gradients, 3D, glass, metal, heavy shadow; no imitation of existing brands or characters"}
```

- [ ] **Step 3: Dry-run the complete batch**

Run:

```bash
PYTHONPATH=.python-deps python3 /data/home/.codex/skills/.system/imagegen/scripts/image_gen.py generate-batch \
  --input output/imagegen/child-voice-logo-concepts/prompts.jsonl \
  --out-dir output/imagegen/child-voice-logo-concepts \
  --concurrency 3 \
  --augment \
  --dry-run
```

Expected: six jobs resolve to `gpt-image-2`, `1024x1024`, `quality=high`, and the six requested output filenames; no network call is made.

- [ ] **Step 4: Generate all six concepts through the bundled CLI**

Run the same command without `--dry-run`:

```bash
PYTHONPATH=.python-deps python3 /data/home/.codex/skills/.system/imagegen/scripts/image_gen.py generate-batch \
  --input output/imagegen/child-voice-logo-concepts/prompts.jsonl \
  --out-dir output/imagegen/child-voice-logo-concepts \
  --concurrency 3 \
  --max-attempts 3 \
  --augment
```

Expected: exit code `0`; the output directory contains six non-empty PNG candidate files with the exact stable names listed above.

- [ ] **Step 5: Verify the generated file set and PNG dimensions**

Run:

```bash
PYTHONPATH=.python-deps python3 -c 'from pathlib import Path; import struct; root=Path("output/imagegen/child-voice-logo-concepts"); files=sorted(root.glob("[0-9][0-9]-*.png")); assert len(files)==6, files; dims=[]; [(lambda data,p: dims.append((p.name, *struct.unpack(">II", data[16:24]))))(p.read_bytes()[:24],p) for p in files]; assert all(w==h and w>=1024 for _,w,h in dims), dims; print(dims)'
```

Expected: six square entries with both edges at least `1024px`; the current configured endpoint reports `1254, 1254` for each generated candidate.

- [ ] **Step 6: Commit the reproducible prompt set and raw candidates**

```bash
git add output/imagegen/child-voice-logo-concepts/prompts.jsonl \
  output/imagegen/child-voice-logo-concepts/0*.png
git commit -m "design: generate child voice logo concepts"
```

Expected: one commit containing only the prompt provenance and six raw candidates.

### Task 2: Build Review Sheets and Perform Visual QA

**Files:**
- Create: `output/imagegen/child-voice-logo-concepts/contact-sheet.png`
- Create: `output/imagegen/child-voice-logo-concepts/small-size-check.png`

**Interfaces:**
- Consumes: the six `1024x1024` PNG files from Task 1.
- Produces: a numbered 3-by-2 review sheet and a 24/48-pixel readability sheet; does not alter raw candidates.

- [ ] **Step 1: Install the local-only contact-sheet dependency**

Run:

```bash
python3 -m pip install --target tmp/imagegen/python-deps Pillow
```

Expected: `PYTHONPATH=tmp/imagegen/python-deps python3 -c 'from PIL import Image'` exits with code `0`. The dependency directory is temporary and is not committed.

- [ ] **Step 2: Assemble a numbered contact sheet without modifying candidates**

Run:

```bash
PYTHONPATH=tmp/imagegen/python-deps python3 -c 'from pathlib import Path; from PIL import Image,ImageDraw; root=Path("output/imagegen/child-voice-logo-concepts"); files=sorted(root.glob("[0-9][0-9]-*.png")); sheet=Image.new("RGB",(960,680),(246,247,251)); draw=ImageDraw.Draw(sheet); [(lambda im,i,p: (sheet.paste(im.resize((280,280),Image.Resampling.LANCZOS),(20+(i%3)*320,40+(i//3)*320)),draw.text((20+(i%3)*320,18+(i//3)*320),p.stem,fill=(37,42,58))))(Image.open(p).convert("RGB"),i,p) for i,p in enumerate(files)]; sheet.save(root/"contact-sheet.png")'
```

Expected: `contact-sheet.png` is `960x680` and shows all six concepts in filename order without cropping.

- [ ] **Step 3: Assemble the 48-pixel and 24-pixel readability sheet**

Run:

```bash
PYTHONPATH=tmp/imagegen/python-deps python3 -c 'from pathlib import Path; from PIL import Image,ImageDraw; root=Path("output/imagegen/child-voice-logo-concepts"); files=sorted(root.glob("[0-9][0-9]-*.png")); sheet=Image.new("RGB",(720,220),(246,247,251)); draw=ImageDraw.Draw(sheet); draw.text((20,18),"48 px",fill=(37,42,58)); draw.text((20,120),"24 px",fill=(37,42,58)); [(lambda im,i: (sheet.paste(im.resize((48,48),Image.Resampling.LANCZOS),(120+i*96,12)),sheet.paste(im.resize((24,24),Image.Resampling.LANCZOS),(132+i*96,116)),draw.text((137+i*96,68),str(i+1),fill=(37,42,58)),draw.text((137+i*96,150),str(i+1),fill=(37,42,58))))(Image.open(p).convert("RGB"),i) for i,p in enumerate(files)]; sheet.save(root/"small-size-check.png")'
```

Expected: `small-size-check.png` shows all six candidates at both target sizes with numeric labels.

- [ ] **Step 4: Inspect the contact sheet and every candidate against the approved rubric**

Open `contact-sheet.png`, `small-size-check.png`, and any ambiguous raw candidate with the local image viewer. Reject a candidate from recommendation if any of the following is true:

- it contains text, a forbidden device or robot symbol, a watermark, a mockup, 3D treatment, or brand imitation;
- its silhouette is not recognizable at 48 pixels;
- its key character cue disappears or becomes visual noise at 24 pixels;
- it reads primarily as a phone utility, generic chatbot, animal mascot, or infant product rather than a warm voice companion;
- it uses more than the approved blue, yellow, and warm-white palette in a way that prevents simple vector reconstruction.

Expected: record a concise recommendation of the strongest one to three candidates, with observed strengths and any violation; do not silently regenerate or overwrite candidates.

- [ ] **Step 5: Commit the two review sheets**

```bash
git add output/imagegen/child-voice-logo-concepts/contact-sheet.png \
  output/imagegen/child-voice-logo-concepts/small-size-check.png
git commit -m "design: add logo concept review sheets"
```

Expected: one commit containing only the two derived review images.

- [ ] **Step 6: Hand off the candidates for user selection**

Report the exact output directory, model (`gpt-image-2`), quality (`high`), the final prompt-set path, and clickable links to the contact sheet and each recommended candidate. Ask the user to choose one candidate before any refinement or SVG vectorization work begins.
