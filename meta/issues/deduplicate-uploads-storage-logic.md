# Deduplicate uploads root and file persistence logic

## Summary

Uploads-root resolution and file persistence are duplicated across the
avatar, banner, and media storages and the uploads plug. The same path and
directory logic exists in several places, which is how the storage layout and
the serving layer drift apart.

## Requirements

- Extract one place that owns uploads-root resolution and file persistence.
- Have avatar, banner, media storage, and the uploads plug all use it.
- Do not change the on-disk layout as part of this refactor.

## Acceptance Criteria

- One module owns the path logic; the others delegate.
- Existing upload and serving tests pass with no layout change.

## Notes

- From `docs/audits/codebase-audit-2026-01-18.md`.
