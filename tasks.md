# Tasks / Backlog

This is a living checklist for **Egregoros** (Postgres + Elixir/OTP + Phoenix/LiveView).

Notes:
- Keep tasks **small** and **TDD-first** (failing test → implementation → refactor).
- Prefer fixtures in `test/fixtures/` for federation compatibility tests.
- When behavior is missing (authz rules, remote lookups, caches), introduce a behaviour boundary and use **Mox** in tests.

## Federation core (ActivityPub)

- [x] **Ingest `Update` activities**
  - [x] Apply **actor profile updates** (`Person`) safely (no cross-actor updates).
  - [x] Apply **object edits** (`Note`) where compatible (edit history + visibility rules).
  - [x] Decide/implement **object upsert semantics** for Updates (currently “insert-or-return existing”).
- [x] Ingest `Move` activities (account migration).
- [ ] Implement/verify `Update`/`Delete` constraints for **impersonation safety** (e.g. Update actor must match updated actor id).
- [x] Improve “fetch-on-demand” ingestion contexts so internally-fetched activities aren’t rejected as “not targeted”.
- [ ] Keep/expand thread completion: fetch missing replies/ancestors/descendants when receiving partial threads.

## Mastodon API compatibility

- [ ] Fill out remaining Mastodon API gaps that clients expect:
  - [x] `GET /api/v1/conversations` (currently returns `[]`)
  - [x] `GET /api/v1/favourites` (was stubbed)
  - [x] `GET /api/v1/bookmarks` (was stubbed)
  - [x] Status edit/Update flows end-to-end (API + AP Update).
  - [ ] Ensure Status entity fields match `docs.joinmastodon.org/entities/Status/` where feasible.

## Performance / scalability

- [ ] Make federation ingress/egress consistently **async** (Oban) with back-pressure, retries, and rate limits.
- [ ] Benchmark suite: realistic seed + perf probes for timelines, thread views, search, ingestion bursts (see `BENCHMARKS.md`).
- [ ] Keep caching behind behaviours so backends can be swapped (ETS → Redis, etc.).

## Security / privacy

- [ ] Work through remaining open items in `security.md` and mark them as addressed.
- [ ] Signature strictness tightening (keep **off by default** for now; provide a config toggle).
- [ ] Continuous audit for privacy leaks (public timelines, streaming, media access, DM visibility).

## UX / UI (LiveView)

- [ ] Work through `frontend_checklist.md` (prioritized UX parity with Mastodon/Pleroma clients).
- [ ] Composer polish: unify controls, fix edge cases, add missing attachments flows, improve keyboard UX.
- [ ] Thread/status view polish (navigation, scroll restoration, reply modal UX).
