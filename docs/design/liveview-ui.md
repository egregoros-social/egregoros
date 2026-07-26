# LiveView Frontend Plan (World‑Class UI)

This is a **Phoenix LiveView + Tailwind v4** UI plan for Egregoros. It focuses on: (1) making the app feel premium, (2) closing feature gaps (e.g. attachments), and (3) setting up a maintainable component architecture so future features don’t degrade UX.

## Current pain points (observed)
- **Missing core features:** no attachment posting, limited compose options, incomplete parity with implemented backend capabilities.
- **Information architecture feels “prototype‑y”:** unclear separation between navigation / compose / timeline / relationships.
- **Weak interaction affordances:** some controls don’t look/feel clickable (hover, focus, disabled, loading states).
- **Inconsistent patterns:** repeated Tailwind class blobs, no shared component system, hard to maintain.
- **Feedback gaps:** actions need consistent success/error feedback (flash/toasts, inline validation, etc.).
- **Mobile and accessibility undefined:** keyboard navigation, focus handling, screen reader semantics, responsive layout.

## Target UX (definition of “world‑class”)
**A world‑class Egregoros UI should:**
- Feel fast (streaming updates, optimistic UI where safe, no jank).
- Be coherent (clear navigation, predictable layout, consistent interactions).
- Be accessible (keyboard‑first, focus visible, semantic markup, good contrast).
- Be safe (sanitized HTML, safe external links, cautious remote media handling).
- Be maintainable (design system + reusable components + stable selectors for tests).

**Measurable acceptance criteria (for review):**
- Primary flows: **register/login**, **compose**, **upload attachments**, **follow/unfollow**, **like/repost/react**, **view notifications**, **edit profile**, **logout**.
- Responsive: phone → tablet → desktop works without layout regressions.
- Accessibility baseline: keyboard navigation works for all primary flows; focus states are visible; icon buttons have labels.

## UI Architecture Plan

### 1) App shell / layout
Create a stable “app shell” that maps to how social clients work:
- **Desktop (3 columns):**
  - Left: navigation + account switch + quick links.
  - Center: timeline and detail views.
  - Right: compose (if logged in), notifications preview, follow suggestions (later).
- **Mobile:**
  - Single column views with a **bottom navigation bar**.
  - Compose becomes a modal/sheet.

Implementation guidance:
- Keep the layout in `Layouts.app` as the outer wrapper, but use a dedicated LiveView for the shell when needed (or a shared component) to avoid “everything in TimelineLive”.
- Use consistent spacing scale and `max-w-*` constraints for readability.

### 2) Component system (design system)
Introduce a small, opinionated component layer so every view stops hand‑rolling classes:
- `Button` / `IconButton` (primary/secondary/ghost/destructive, loading, disabled).
- `Input` wrappers for consistent label/help/error, using existing `<.input>` when possible.
- `Card`, `Panel`, `Badge`, `Avatar`, `Menu` (dropdown), `Tabs`.
- `Toast` / flash presentation that reads from `@flash` (and LiveView `put_flash`).
- `EmptyState`, `Skeleton` loading placeholders.

**Key UX details to standardize:**
- `cursor-pointer` on non‑disabled clickable elements.
- `hover:*` + `active:*` states, and `focus-visible:ring-*`.
- `aria-*` labels for icon-only actions, `type="button"` where appropriate.

**Testing approach (TDD):**
- Component tests assert semantics and stable `data-role` hooks (avoid brittle “exact class string” tests).
- Small smoke tests ensure each component has correct attributes and renders in light/dark mode.

### 3) View models (avoid duplicated decoration logic)
Right now, TimelineLive builds “decorated” post maps inline. Plan:
- Create `EgregorosWeb.ViewModels.Status` (or similar) that:
  - Takes an `Object` + current user, returns the renderable shape.
  - Centralizes counts, “liked?”, “reposted?”, reaction aggregates.
  - Mirrors Mastodon JSON projection where possible (reduces drift).
- LiveViews use view models instead of recomputing in each view.

This makes UI changes safer and reduces logic in templates.

### 4) Media & attachments (LiveView uploads)
Add a first‑class attachment composer experience:
- Use `allow_upload/3` for images/videos with:
  - size limits
  - accepted types
  - max number of files
- Composer UI:
  - Drag‑and‑drop area, file picker button.
  - Previews (image/video icon), remove, reorder (later).
  - Per‑attachment alt text/description.
  - Progress indicator + error display.
- On submit:
  - `consume_uploaded_entries/3` -> pass `%Plug.Upload{}` to `MediaStorage.store_media/2`.
  - Create attachment objects (same shape used by Mastodon API) and pass them as `attachments:` to `Publish.post_note/3`.

**TDD coverage:**
- LiveView test: upload + submit creates a post with attachment rendered in timeline.
- LiveView test: invalid type/oversize shows validation error and doesn’t post.
- Test with `MediaStorage.Mock` so uploads don’t hit disk in CI.

### 5) Timeline & post card UX
Refactor timeline into smaller parts:
- `TimelineHeader` (home/public toggle, filters later).
- `StatusCard` dispatcher with specialized card components:
  - `NoteCard` for standard posts
  - `PollCard` for Question/poll objects
  - `AnnounceCard` for boosts/reposts
  - Shared subcomponents: `ActorHeader`, `ContentBody`, `AttachmentGrid`, `InteractionBar`, `StatusMenu`

Improve timeline behavior:
- Infinite scroll (or “Load more”) with proper loading states.
- Streaming insert animations (subtle, not distracting).
- Provide “new posts” marker when user is scrolled away from top.

**TDD coverage:**
- TimelineLive tests cover: initial render, switching timeline, receiving streamed post, like/repost/react toggles, pagination.

### 6) Notifications UI
Add a notifications panel/view:
- Render follow/like/repost/reaction notifications with clear visuals.
- Unread indicator and “mark as read” (later).
- Desktop: preview in right column; mobile: dedicated screen.

### 7) Profiles and settings polish
Finish “real app” expectations:
- Profile view page (avatar, header, bio, stats, follow button).
- Profile editing:
  - avatar upload (replace URL field)
  - header image upload (optional)
  - bio with safe formatting rules
- Settings pages: consistent forms, real feedback (success/error), and “danger zone” patterns.

## Execution milestones (TDD‑first)

### UI‑0 — Baseline polish + component foundation (fast win)
- Inventory current UI, remove obvious layout oddities.
- Introduce base components (Button, Card, Avatar, Toast).
- Replace ad‑hoc buttons/links with components for consistent hover/focus/disabled states.

**Deliverables**
- Buttons/links universally look clickable and have consistent hover/focus.
- Flash/toast feedback consistent across actions.

### UI‑1 — App shell restructure
- Implement responsive shell (desktop 3‑col, mobile 1‑col + bottom nav).
- Move relationship lists and “secondary” widgets out of the compose area into proper panels.

**Deliverables**
- Timeline is the primary center content; side panels feel intentional.

### UI‑2 — Attachment posting (end‑to‑end)
- LiveView uploads + attachment previews + alt text.
- Post creation includes attachments and timeline renders them.

**Deliverables**
- Upload and post image attachment from web UI.

### UI‑3 — Timeline cards + quality
- Extract `StatusCard` dispatcher and specialized card components (NoteCard, PollCard, AnnounceCard).
- Improve typography, spacing, and action row.
- Add pagination/infinite scroll + loading skeletons.

**Deliverables**
- Timeline feels smooth and readable; cards are consistent and interactive.

### UI‑4 — Notifications + profile pages
- Implement notifications list/view.
- Implement profile page + follow/unfollow UX.

**Deliverables**
- You can live in the UI without needing the API client for basics.

### UI‑5 — Final polish pass
- Accessibility audit pass (keyboard, focus, labels).
- Micro‑interactions (hover, transitions), consistent empty states.
- Visual QA vs reference screenshot(s) and Husky expectations.

**Deliverables**
- “Feels finished” review: no obvious rough edges, consistent design language.

## Testing strategy (non‑negotiable)
- **Every milestone starts with a failing LiveView test** describing the user-visible behavior.
- Prefer `data-role="..."` hooks for tests instead of brittle CSS selectors.
- Mock boundaries:
  - `MediaStorage.Mock` for uploads
  - `Auth.Mock` / `AuthZ.Mock` for auth gates where needed
- Avoid global env tweaks in tests; keep config behind behaviours (as we’re doing).

## Security and safety in UI rendering
- Continue to sanitize HTML (`fast_sanitize`) and keep rendering rules centralized.
- Add safe link handling:
  - `rel="nofollow noopener noreferrer"`
  - optional external link indicator
- Be cautious with remote media:
  - lazy load, constrain sizes, consider proxying later (out of scope for now).

## References / inspiration
- Pleroma UI screenshot (provided) as a “spatial” reference for multi‑column layout.
- Husky/Tusky expectations: attachments and emoji reactions must feel first‑class.
- Keep design distinctive; avoid cloning Mastodon UI, but match its usability bar.
