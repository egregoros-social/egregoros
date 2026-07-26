# Refactor backlog

This file tracks refactors that were identified during a poll/publish architecture review.
Each item should be tackled as an isolated change (preferably with a small, focused commit),
keeping behavior unchanged unless explicitly desired.

## Backlog

- [x] Extract shared recipient helpers (remove duplicated `recipient_actor_ids/*`)
  - Duplicates:
    - `lib/egregoros/activities/create.ex:184`
    - `lib/egregoros/activities/note.ex:152`
    - `lib/egregoros/activities/update.ex:210`
    - `lib/egregoros/timeline.ex:147`
    - `lib/egregoros/workers/resolve_mentions.ex:273`
  - Related: `lib/egregoros/inbox_targeting.ex:28` (recipient extraction)
  - New module: `lib/egregoros/recipients.ex`
  - Tests: `test/egregoros/recipients_test.exs`

- [x] Consolidate inbox-targeting patterns in `Egregoros.InboxTargeting`
  - Many activities re-implement `validate_inbox_target/2` with small variations:
    - `lib/egregoros/activities/create.ex:119`
    - `lib/egregoros/activities/note.ex:162`
    - `lib/egregoros/activities/question.ex:230`
    - `lib/egregoros/activities/update.ex:220`
    - (and others under `lib/egregoros/activities/*`)
  - New helpers: `InboxTargeting.validate_addressed_or_followed/3`,
    `InboxTargeting.validate_addressed_or_followed_or_object_owned/4`,
    `InboxTargeting.validate_addressed_or_followed_or_addressed_to_object/4`
  - Tests: `test/egregoros/inbox_targeting_test.exs`

- [x] Deduplicate `contentMap` → `content` normalization across `Note` and `Question`
  - `lib/egregoros/activities/note.ex:211`
  - `lib/egregoros/activities/question.ex:138`
  - New module: `lib/egregoros/activity_pub/content_map.ex`
  - Tests: `test/egregoros/activity_pub/content_map_test.exs`

- [x] Unify mention-resolution helpers (`local_domains/normalize_host`) between PostBuilder and ResolveMentions
  - `lib/egregoros/publish/post_builder.ex:152`
  - `lib/egregoros/workers/resolve_mentions.ex:288`
  - New module: `lib/egregoros/mentions/domain.ex`
  - Tests: `test/egregoros/mentions_domain_test.exs`

- [x] Deduplicate Mastodon attachment preview URL extraction
  - `lib/egregoros_web/mastodon_api/status_renderer.ex:516`
  - `lib/egregoros_web/mastodon_api/scheduled_status_renderer.ex:170`
  - `lib/egregoros_web/controllers/mastodon_api/media_controller.ex:101`
  - New module: `lib/egregoros_web/mastodon_api/media_urls.ex`
  - Tests: `test/egregoros_web/mastodon_api/media_urls_test.exs`

- [x] Centralize poll parsing (options/multiple/expiry) used in multiple layers
  - `lib/egregoros/publish/polls.ex:352`
  - `lib/egregoros_web/mastodon_api/poll_renderer.ex:23`
  - `lib/egregoros_web/view_models/status.ex:402`
  - New helpers: `Egregoros.Objects.Polls.options/1` and `Egregoros.Objects.Polls.closed_at/1`

## Architecture polish (non-urgent)

- [x] Prefer `Egregoros.Activities.Question.build/…` (like `Note.build/2`) and use it from `Publish.Polls`
  - Currently local poll creation is ad-hoc in `lib/egregoros/publish/polls.ex:177`
  - Compare with Note builder: `lib/egregoros/activities/note.ex:35`
  - Added `Question.build/3` in `lib/egregoros/activities/question.ex`
  - Tests: `test/egregoros/activities/question_build_test.exs`

- [x] If delivery quirks accumulate, move per-software payload rewrites out of `Activities.Create`
  - Example: Answer → Note payload rewrite for delivery:
    - `lib/egregoros/activities/create.ex:105`
  - New module: `lib/egregoros/federation/delivery_payload.ex`
  - Tests: `test/egregoros/federation/delivery_payload_test.exs`
