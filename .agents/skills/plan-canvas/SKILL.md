---
name: plan-canvas
description: Present a plan for a visual/UX feature as an annotatable HTML artifact rendered in the project's own design tokens, instead of a markdown wall of text. MUST USE when the user says "use plan canvas" or "plan canvas". Also use when planning a UI feature, redesign, layout change, or component where competing options are easier to judge by seeing them than by reading them. Skip for pure backend/logic/data plans, which stay as a text checklist.
---

# Plan Canvas

Created by Kenneth Villar ([BrewedOps](https://brewedops.com)).

Adapted from Kun Chen's "lavish" workflow: for anything visual, a wall of markdown is the wrong medium. The user cannot easily tell what each option will actually look like, or point at the specific part they dislike. Render the plan as an **HTML artifact in the project's real design system** so options are seen, not imagined, and feedback is precise.

Front-loads the requirements-clarification the global constitution already asks for ("the plan is the cheapest place to be wrong"), but in a medium that fits UI work.

## When to use vs skip

- **Use** for: a new UI feature, a redesign, a layout/nav change, a component with 2+ viable directions, anything where "which of these looks right?" is the real question.
- **Skip** (stay text/PLAN.md) for: backend logic, data pipelines, API wiring, refactors, bug fixes - nothing visual to compare.

## Step 1 - Read the project's tokens first (do not invent a look)

Before rendering anything, ground the mock in the actual project so it looks like the app, not a generic template:
1. Read the project's stylesheet / token source - `index.css`, `tailwind` theme, or the CSS-vars block (`--bg`, `--accent`, font stack). Global default if none: `#0B0B1A`/`#07071A` bg, white text, `#FF5722` accent, one accent only.
2. Note the icon set in use (Phosphor for BrewedOps, Lucide elsewhere - never mix), the font (Geist/Satoshi/Cabinet Grotesk on premium surfaces, never Inter/Roboto on a hero), and spacing/radius conventions.
3. If the feature touches an existing screen, read that component so the mock matches its real structure.

Never hardcode hex the project doesn't use. Pull its variables. If a color is missing, create a token, don't guess a raw value.

## Step 2 - Build the canvas as a self-contained HTML artifact

Write one HTML file to the scratchpad, then publish it with the `Artifact` tool. Requirements:

- **Inline everything** (CSS + JS + data-URI assets). Strict CSP blocks external hosts - no CDNs, no remote fonts, no fetch. Load the `artifact-design` skill first to calibrate design investment.
- **Show the options side by side**, each as a realistic mock using the project's tokens - not a description of the option, the option. 2-4 directions is the sweet spot.
- **Make it annotatable.** Give each option and each major region a clickable state that reveals a comment field (store notes in memory; no backend). The user should be able to point at "this header" and say why it is wrong without leaving the page.
- **Put the decisions at the bottom** as explicit choices (radio/toggle rows): which direction, plus any per-option forks (density, motif, nav pattern). The user clicks to decide.
- **Theme-aware + responsive** per the Artifact rules (light/dark, no horizontal body scroll, wide content scrolls in its own container).

Favicon: a stable emoji for the artifact (e.g. a drafting/compass mark). Keep it constant across redeploys of the same plan.

## Step 3 - Iterate on the canvas, then build

- The user annotates and picks. Read their selections/notes back and **redeploy to the same file path** (same Artifact URL) with the refinements - do not mint a new artifact per revision.
- When they approve a direction, restate it in one tight line (chosen option + resolved forks) and only then start implementing. The canvas was the spec; the build follows it.
- Do not review-by-wall-of-text afterward. Verify the built UI against the approved canvas (screenshot / served harness), per the deploy-verification rule.

## Anti-slop guardrails (inherit /taste)

The mock is still shipped design - it must not itself be slop. No colored left-border accent cards, no purple-to-blue gradients, no neon glows, no centered pill+headline+subtext+CTA hero, no uniform card grids, no circular spinners. If the plan is for a premium surface, invoke `/taste` or `/soft` for the brief before rendering options.
