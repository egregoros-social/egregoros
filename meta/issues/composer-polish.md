# Polish the composer

## Summary

The composer's controls are inconsistent across entry points, some edge cases
are rough, attachment flows are incomplete, and keyboard UX is limited.

## Requirements

- Unify the controls so the main composer and the reply composer behave the
  same.
- Fix the known edge cases (validation, error states, draft loss on
  navigation).
- Complete the missing attachment flows.
- Improve keyboard UX: submit, newline, escape, and focus management.

## Acceptance Criteria

- Main and reply composers share one component and one set of options.
- Keyboard interactions are covered by LiveView tests.
- Attachment flows work end to end, including alt text and removal.

## Notes

- Carried over from the old `tasks.md` backlog. Coordinate with
  [frontend-parity-checklist](frontend-parity-checklist.md) so the same work
  is not tracked twice.
