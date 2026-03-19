# Component Generation — Step 7

## Input checklist before generating

- [ ] `structure.json` — DOM hierarchy
- [ ] `styles.json` — computed styles per element
- [ ] Breakpoint styles (mobile / tablet / desktop)
- [ ] Interaction delta (hover/click states + transition values)
- [ ] Keyframes or `extracted.json` from transition-reverse-engineering (if any)

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
