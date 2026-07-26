# Polish the thread and status view

## Summary

The status/thread view at `/@:nickname/:uuid` needs work on navigation,
scroll restoration, and the reply modal UX.

## Requirements

- Make ancestor/descendant navigation predictable, including deep threads.
- Restore scroll position when navigating back into a thread.
- Tighten the reply modal: focus handling, dismissal, and error states.

## Acceptance Criteria

- Navigating away from and back to a thread restores position.
- Reply modal behavior is covered by LiveView tests, including dismissal.

## Notes

- Carried over from the old `tasks.md` backlog.
