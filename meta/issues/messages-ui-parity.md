# Finish messages UI parity

## Summary

The direct messages UI has the basics: new chat, conversation list with
preview/timestamp/unread state, recipient autocomplete, and pagination for
both conversations and thread messages. Remaining gaps are the polish items
that make it usable as a daily driver.

## Requirements

- Audit `/messages` against the equivalent Mastodon/Pleroma client flows and
  list the gaps.
- Cover attachments in DMs, delivery/error states, and empty states.
- Make unread state correct across multiple sessions.

## Acceptance Criteria

- The identified gaps are either closed or split into their own issues.
- Unread state is asserted by tests across send, receive, and read paths.

## Notes

- Carried over from the old `tasks.md` backlog. Note that direct messages are
  plaintext: E2EE was removed, see
  [e2ee-revival-decision](e2ee-revival-decision.md).
- Watch out for the N+1 in
  [actor-card-n-plus-1-in-messages](actor-card-n-plus-1-in-messages.md) when
  touching the conversation list.
