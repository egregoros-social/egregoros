# Tasks / Backlog

This is a living checklist for **Egregoros** (Postgres + Elixir/OTP + Phoenix/LiveView).

Notes:
- Keep tasks **small** and **TDD-first** (failing test → implementation → refactor).
- Prefer fixtures in `test/fixtures/` for federation compatibility tests.
- When behavior is missing (authz rules, remote lookups, caches), introduce a behaviour boundary and use **Mox** in tests.

## Next priorities (recommended)

- [x] **Mastodon `Status` entity completeness** (reduce client quirks)
  - [x] Add contract-style tests for required keys/types from `docs.joinmastodon.org/entities/Status/`.
  - [x] Ensure optional-but-expected keys are present (`application`, `edited_at`, `filtered`, etc.).
  - [x] Ensure reblogs (`Announce`) map cleanly to Mastodon “reblog” shape (bookmark/like/reblog flags reflect the original status).
  - [x] Ensure reply metadata is complete (`in_reply_to_id` + `in_reply_to_account_id`) when parent + actor are known.
- [ ] **Status/thread view polish** (`/@:nickname/:uuid`)
  - [ ] Make reply UI consistent with the main composer (same component, same options).
  - [ ] Reply in-place/modal from timeline (no navigation required).
  - [ ] Improve thread rendering UX (ancestors/descendants layout, navigation, empty/loading states).
- [x] **Thread completion expansion**
  - [x] Fetch missing ancestors/OPs best-effort when ingesting replies and when fetches are triggered by likes/announces (bounded + async).
- [x] **Finish `Update`/`Delete` impersonation constraints**
  - [x] Add/verify tests so cross-actor edits/deletes are impossible.

## Federation core (ActivityPub)

- [x] **Ingest `Update` activities**
  - [x] Apply **actor profile updates** (`Person`) safely (no cross-actor updates).
  - [x] Apply **object edits** (`Note`) where compatible (edit history + visibility rules).
  - [x] Decide/implement **object upsert semantics** for Updates (currently “insert-or-return existing”).
- [x] Ingest `Move` activities (account migration).
- [x] Implement/verify `Update`/`Delete` constraints for **impersonation safety** (e.g. Update actor must match updated actor id).
- [x] Improve “fetch-on-demand” ingestion contexts so internally-fetched activities aren’t rejected as “not targeted”.
- [x] Keep/expand thread completion: fetch missing replies/ancestors/descendants when receiving partial threads.

## Mastodon API compatibility

- [ ] Fill out remaining Mastodon API gaps that clients expect:
  - [x] `GET /api/v1/conversations` (currently returns `[]`)
  - [x] `GET /api/v1/favourites` (was stubbed)
  - [x] `GET /api/v1/bookmarks` (was stubbed)
  - [x] Status edit/Update flows end-to-end (API + AP Update).
  - [ ] Ensure Status entity fields match `docs.joinmastodon.org/entities/Status/` where feasible.

## Performance / scalability

- [ ] Make federation ingress/egress consistently **async** (Oban) with back-pressure, retries, and rate limits.
- [x] Benchmark suite: realistic seed + perf probes for timelines, thread views, search, ingestion bursts (see `BENCHMARKS.md`).
- [ ] Keep caching behind behaviours so backends can be swapped (ETS → Redis, etc.).

## Security / privacy

- [x] Work through remaining open items in `security.md` and mark them as addressed.
- [ ] Signature strictness tightening (keep **off by default** for now; provide a config toggle).
- [ ] Continuous audit for privacy leaks (public timelines, streaming, media access, DM visibility).

## UX / UI (LiveView)

- [ ] Work through `frontend_checklist.md` (prioritized UX parity with Mastodon/Pleroma clients).
- [ ] Composer polish: unify controls, fix edge cases, add missing attachments flows, improve keyboard UX.
- [ ] Thread/status view polish (navigation, scroll restoration, reply modal UX).
