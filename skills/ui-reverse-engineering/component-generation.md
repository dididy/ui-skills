# Component Generation — Step 7

## Input checklist before generating

> **STOP. Do not generate code if ANY of these files are missing. Go back to the extraction step that produces the missing artifact.**

- [ ] `structure.json` — DOM hierarchy (from Step 2)
- [ ] `styles.json` — computed styles per element (from Step 3)
- [ ] Breakpoint styles (mobile / tablet / desktop) (from Step 4)
- [ ] Interaction delta (hover/click states + transition values) (from Step 5)
- [ ] Keyframes or `extracted.json` from transition-reverse-engineering (if any)
- [ ] Reference frames exist in `tmp/ref/<component>/frames/ref/` (from Phase 1)

**If you find yourself writing a value that is not in the extracted data, STOP.** You are guessing. Go back and extract it.

## Generation prompt

Use extracted values directly — no guessing:

```
Generate a React + Tailwind component based on these extracted values:

Structure: [structure.json content]
Styles: [styles.json content]
Responsive: mobile={...} tablet={...} desktop={...}
Interactions: hover delta={...}, transition="..."
Keyframes / animations: [extracted.json or keyframes if any]

Rules:
- Use Tailwind utility classes, not inline styles
- Use CSS variables for design tokens
- Use the EXACT text from the original (copy-paste, do not paraphrase)
- Preserve exact colors, spacing, font sizes from extracted values
- Implement hover states with Tailwind group/peer or CSS variables
- Implement animations with Tailwind animate-* or custom @keyframes:
    - Next.js App Router: add to `src/app/globals.css`
    - Vite/CRA: add to `src/index.css` or `src/App.css`
    - Tailwind v4: use `@keyframes` inside `@theme` block; v3: use `theme.extend.keyframes` in `tailwind.config`
- Make interactions FUNCTIONAL — do not stub click/hover handlers
- For images: use descriptive placeholder if original is inaccessible
- If functionality requires backend data, mock it inline
- Component must be self-contained (no external data dependencies)
```

Save the generated component to your project (e.g., `src/components/<ComponentName>.tsx`). If any extracted value is missing, use a placeholder comment: `{/* TODO: missing — check extraction */}`.

## Iteration (update, not rewrite)

When refining after visual verification, make **targeted edits** — do not regenerate the entire component. Identify the specific mismatched property and fix only that.
