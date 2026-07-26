# Agent Guidelines

- **Work TDD.** Write the failing test first, implement to pass, then refactor.
  If that genuinely isn't feasible for a change, say so explicitly rather than
  quietly skipping it.

- **Get a review before you commit.** Have the change reviewed and address the
  findings first — don't commit and then review.

- **Commit small and topical.** One concern per commit, conventional commit
  messages. If a working tree has accumulated unrelated changes, commit them in
  separate topical chunks rather than one large one.

- **Reference upstream Pleroma for guidance.** The implementation in
  `../pleroma` is the reference for protocol behavior and compatibility
  questions. Prefer the fixtures in `test/fixtures/` (vendored from upstream)
  when writing or updating federation tests. Pleroma supplies evidence, not
  truth: where it diverges from the specification, decide deliberately and
  record why.

- **`Egregoros.Object.data` is canonical external ActivityPub JSON.** Never
  persist internal or derived state into it — that data is served to and
  federated with other servers, so anything you put there is a future exposure
  risk. Use `Egregoros.Object.internal` for internal caching and metadata.

- **Issues live in `meta/`.** Pick or write an issue in `meta/issues.md` before
  starting work, and break large items into sub-issues. Move an entry to
  `meta/issues_archive.md` only once its acceptance criteria are actually met.

Setup, tests, the precommit gate, and architecture notes are in
[`docs/README.md`](docs/README.md). Audits under `docs/audits/` are historical —
their unchecked boxes are not the backlog.
