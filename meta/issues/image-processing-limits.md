# Bound image processing against decompression bombs

## Summary

Thumbnail and blurhash generation call `Image.open/1` and `Image.thumbnail/2`
with no explicit pixel-dimension limits, so a small file that decodes to a
huge bitmap can exhaust memory.

## Requirements

- Enforce explicit maximum pixel dimensions (and total pixel count) before
  decoding.
- Reject oversized input with a clear error rather than attempting to process
  it.
- Keep the limits configurable, with safe defaults.

## Acceptance Criteria

- A regression test covers both the max file size and the max dimensions.
- A crafted small-file/large-bitmap input is rejected without a memory spike.

## Notes

- From `docs/audits/codebase-audit-2026-01-18.md`, combining the hardening
  item and its "add security regression tests for media processing"
  follow-up.
