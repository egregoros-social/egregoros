# Frontend Feature Checklist (Mastodon / Pleroma / Twitter‑like)

This is a **web UI** checklist for Pleroma‑Redux. Items are ordered roughly by dependency + what typically matters most for a “daily driver” UI.

## Legend
- **DONE**: implemented end‑to‑end in the web UI
- **PARTIAL**: exists, but incomplete/rough/missing polish or coverage
- **TODO**: not implemented in the web UI

## Current UI entry points (for reference)
- `/` (LiveView) timeline + compose
- `/search` (LiveView) account search + remote follow by handle
- `/notifications` (LiveView) notifications list
- `/@:nickname` (LiveView) profile view
- `/login`, `/register`, `/settings`, `/oauth/authorize` (controllers/templates)

---

## P0 — Core “daily driver” UX

### App shell, navigation, and layout
| Feature | Status | Notes |
|---|---:|---|
| Responsive layout (desktop + mobile) | PARTIAL | `AppShell` exists (bottom nav on mobile) but layout needs a cohesive, world‑class information architecture across all screens. |
| Global navigation (timeline / notifications / profile / settings) | DONE | `AppShell` wraps all primary screens, including controller pages like login/register/settings/OAuth. |
| “Compose” quick access on mobile (FAB / sheet) | PARTIAL | Mobile FAB + sheet exists; keep polishing layout + affordances. |
| Light/dark/system theme toggle | DONE | Theme toggle exists in layout; keep improving contrast + consistency. |
| Flash/toast feedback on user actions | PARTIAL | Controllers use flash; LiveView actions should consistently show success/error (and reduce silent failures). |
| Consistent button affordances (hover/focus/cursor/disabled) | PARTIAL | Many buttons are polished; keep standardizing remaining custom buttons + icon buttons. |
| Consistent design system components (Button, Card, Input, Avatar, etc.) | PARTIAL | Core components exist; keep replacing duplicated class lists with shared components. |

### Authentication and account basics
| Feature | Status | Notes |
|---|---:|---|
| Register local account | DONE | `/register` |
| Login / logout | DONE | `/login`, `/logout` |
| Session persistence and “current user” rendering | DONE | Browser session + layout rendering works. |
| OAuth authorize UI | DONE | `/oauth/authorize` |
| Password reset flow (“forgot password”) | TODO | Email + token + reset UI. |
| Two‑factor auth (TOTP/WebAuthn) | TODO | Optional but common on serious instances. |
| Account switching (multi‑account UI) | TODO | Common power‑user feature. |

### Timeline reading (home/public)
| Feature | Status | Notes |
|---|---:|---|
| Public timeline view | DONE | `/` with timeline selector. |
| Home timeline view | DONE | Requires account; toggles exist. |
| Load more / pagination | DONE | “Load more” exists; consider infinite scroll later. |
| Infinite scroll | DONE | Timeline auto-loads more posts when reaching bottom (keeps “Load more” button for accessibility). |
| Streaming new posts into timeline | DONE | Live updates exist for timeline. |
| “New posts” indicator when scrolled | DONE | Timeline buffers incoming posts while scrolled down and shows a “new posts” button. |
| Human‑friendly timestamps (“5m”, “2h”) | DONE | Rendered as relative time with a full timestamp on hover. |
| Status permalink page (single post view) | PARTIAL | LiveView route `/@:nickname/:uuid` exists; actions (like/repost/reaction/reply) are wired; canonical redirects are implemented, but page still needs polish (error states, richer thread UI). |
| Thread/context view (replies chain) | PARTIAL | Status page renders ancestors + descendants with basic indentation for nested replies; still needs richer threading UI and reply polish. |
| Clickable actor profile from timeline | DONE | Status cards link actor → profile. |
| Link handling (open external safely, copy link) | PARTIAL | Status menu supports “Copy link” + “Open link”; needs richer share affordances. |

### Compose / posting
| Feature | Status | Notes |
|---|---:|---|
| Post text | DONE | Basic compose exists. |
| Post validation feedback (empty/too long/etc) | PARTIAL | Empty handled; expand to full validations + inline errors. |
| Attachments upload (images) | DONE | LiveView uploads + `MediaStorage` wired up. |
| Attachments upload (video/audio) | DONE | Upload + posting works; composer previews video thumbnails and provides preview players for video/audio. |
| Attachment preview grid in composer | PARTIAL | Image/video thumbnails + preview players; still needs richer grid UX (reorder, polished playback/expand). |
| Attachment alt text / description editing | DONE | Per-attachment “Alt text” input is supported. |
| Content warning / spoiler text | DONE | Composer “Content warning” field exists. |
| Mark media as sensitive | DONE | Composer “Mark media as sensitive” toggle exists. |
| Visibility selector (public/unlisted/followers/direct) | DONE | Composer visibility select exists. |
| Reply composer (in‑reply‑to) | PARTIAL | Status permalink page supports replying with attachments + alt text; still needs full parity with main composer (options, polish, etc.). |
| Quote post | TODO | Optional; not in vanilla Mastodon but common. |
| Drafts | TODO | Often requested; can be lightweight (local storage). |
| Polls | TODO | Mastodon‑style polls (optional). |
| Scheduled posts | TODO | Optional. |

### Status rendering (the post card)
| Feature | Status | Notes |
|---|---:|---|
| Safe HTML rendering (sanitized) | DONE | Rendering uses safe HTML pipeline. |
| Local text rendering | DONE | Local posts render as text. |
| Content warning / spoiler rendering | DONE | Status cards render CW as a toggle and hide body + media behind it. |
| Linkify mentions/hashtags/URLs for local content | PARTIAL | `@user`, `@user@host`, `#tags`, and `http(s)` URLs are linkified for plain-text content; remote posts still depend on incoming HTML when it’s provided. |
| Emoji reactions UI | DONE | Reaction picker exists and renders all emojis present; still missing custom emoji (server-provided) + search. |
| Like / unlike | DONE | |
| Repost / unrepost | DONE | |
| Reply action | DONE | Reply works for both local + remote posts via the status permalink page. |
| Bookmark action | DONE | Bookmark/unbookmark is available via the post “…” menu (stored locally). |
| Delete own post | DONE | Available from the status “…” menu for local posts owned by the current user (with confirm step). |
| Edit own post | TODO | (Optional; Mastodon doesn’t support editing by default.) |
| Report post/user action menu | TODO | Common “…” menu. |
| Media attachments render | PARTIAL | Images/video/audio render; documents fall back to download links; still needs lightbox/carousel. |
| Sensitive media hiding/reveal | PARTIAL | Attachments are hidden behind a “Sensitive media” reveal affordance when `sensitive` is set. |
| Attachment lightbox / media viewer | DONE | Modal viewer supports image/video/audio, carousel navigation (arrows), ESC, click-away, focus trap + focus restore. |
| Cards for link previews (OpenGraph) | TODO | “Twitter cards” / link previews (optional). |
| Content collapse (long posts) | DONE | Status cards collapse long bodies behind a “Show more” toggle. |

---

## P1 — Social graph + discovery + notifications

### Profiles and relationships
| Feature | Status | Notes |
|---|---:|---|
| Profile page | DONE | `/@:nickname` |
| Follow / unfollow from profile | DONE | |
| Remote follow by handle | DONE | Present as a “follow remote” workflow. |
| Followers list page | DONE | Dedicated page exists (`/@:nickname/followers`) with load-more pagination + follow/unfollow buttons. |
| Following list page | DONE | Dedicated page exists (`/@:nickname/following`) with load-more pagination + follow/unfollow buttons. |
| Follow requests (locked accounts) | TODO | Accept/deny UI. |
| Blocks / mutes | TODO | UI + clear state indicators. |
| Relationship badges (follows you, mutuals) | TODO | Optional but useful. |
| Profile fields (custom metadata) | TODO | Common on Mastodon/Pleroma. |
| Profile header image | DONE | Local users can upload a header image in Settings; profile renders it when `banner_url` is present. |

### Notifications
| Feature | Status | Notes |
|---|---:|---|
| Notifications list | DONE | `/notifications` |
| Notification types coverage | PARTIAL | Follow/like/repost covered; expand (mentions, emoji reactions, etc.). |
| Live updates for notifications | DONE | Notifications stream into the list while connected. |
| Mark as read / unread | TODO | |
| Notification filtering (mentions only, follows only, etc.) | TODO | |

### Search & discovery
| Feature | Status | Notes |
|---|---:|---|
| Search box (global) | PARTIAL | `/search` supports accounts + status search; still missing hashtag search UI beyond tag pages. |
| Account lookup by `@user@host` | PARTIAL | `/search` supports following remote accounts by handle; still missing a standalone “lookup” flow. |
| Hashtag pages | PARTIAL | Tag timeline exists (`/tags/:tag`) using content search; supports like/repost/reaction + load-more pagination; still needs tag extraction from `tag` fields. |
| Explore / trending | TODO | |
| User directory | TODO | |

### Messaging
| Feature | Status | Notes |
|---|---:|---|
| Direct messages UI | TODO | Mastodon DMs are “direct visibility” statuses; UI still needs it. |

---

## P2 — Quality bar (polish, accessibility, performance)

### Accessibility (A11y)
| Feature | Status | Notes |
|---|---:|---|
| Keyboard navigation for all primary flows | PARTIAL | Needs systematic review + tests. |
| Focus visible and consistent | PARTIAL | Standardize focus rings and focus traps (modals). |
| Icon buttons have labels (`aria-label`) | PARTIAL | Some do; enforce everywhere. |
| Reduced motion support | PARTIAL | Key entrance animations are gated behind `motion-safe:*`; still need a full pass for motion-reduce. |
| High contrast checks (light/dark) | PARTIAL | Validate contrast ratios. |

### Performance / perceived performance
| Feature | Status | Notes |
|---|---:|---|
| Skeleton loading states | TODO | For timelines, profile posts, notifications. |
| Optimistic UI (safe actions) | PARTIAL | Likes/reposts could be optimistic with rollback. |
| Image lazy loading and sizing | PARTIAL | `loading="lazy"` exists; add aspect ratio, srcset, etc. |
| Offline/failed network UI | TODO | “Retry” affordances for failed actions. |

### Product polish
| Feature | Status | Notes |
|---|---:|---|
| Consistent empty states | PARTIAL | Some screens have empty states; unify style and messaging. |
| Consistent error states (inline + toast) | PARTIAL | Avoid silent failures. |
| Consistent copywriting / micro‑interactions | PARTIAL | Make the app feel cohesive and premium. |

---

## Out‑of‑scope (for now) but common on “big” platforms
| Feature | Status | Notes |
|---|---:|---|
| Lists (Mastodon lists) | TODO | Might be important for power users. |
| Bookmarks / favourites pages | DONE | Saved posts views exist (`/bookmarks`, `/favourites`). |
| Filters (mute words, hide boosts, etc.) | TODO | |
| Analytics / insights | TODO | |
| Admin/mod UI in web | TODO | |
