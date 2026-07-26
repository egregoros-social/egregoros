# Fix quadratic HTTP response body accumulation

## Summary

`Egregoros.HTTP.Req` builds the response body with repeated binary
concatenation (`resp.body <> chunk`) inside the streaming `into` callback,
which is O(n^2) in the number of chunks. It is bounded by the 1MB response
cap, so this is a CPU/GC cost rather than a memory-exhaustion bug, but it is
on every federation fetch.

## Requirements

- Accumulate chunks in a list (or iodata) and join once at the end.
- Keep the existing response size cap and its early-abort behavior.

## Acceptance Criteria

- The size cap still aborts oversized responses, with a test.
- Body accumulation no longer concatenates binaries per chunk.

## Notes

- From `docs/audits/codebase-audit-2026-01-18.md`.
