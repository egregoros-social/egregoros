# Fix the precommit toolchain gate

## Summary

**Resolved — the premise was wrong.** This issue was filed on the belief that
`mix precommit` was failing on `main` at `compile --warnings-as-errors`, and that
the repository therefore had to choose between installing the pinned toolchain
everywhere or moving the pin forward.

Neither was true. `.github/workflows/ci.yml` pins Elixir 1.19.0 / OTP 28.3,
exactly matching `mise.toml`, and CI has been green throughout. The failure was
local: 1.19.0-otp-28 was not installed on the development machine, mise fell back
to 1.20.0/OTP 29, and that compiler's stricter type checking reported warnings in
files nobody had edited (`lib/egregoros/html.ex`,
`lib/egregoros_web/live/status_live.ex`).

Installing the pinned toolchain locally makes `mix precommit` pass cleanly: zero
warnings, full suite green, coverage 85.11%.

Had the original recommendation been followed — moving the pin forward to
1.20/OTP 29 — it would have broken agreement with CI and spent effort
"fixing" warnings CI never emits.

## What was actually done

- Installed the pinned toolchain locally.
- Documented the trap in `docs/development.md`, since nothing warned a
  contributor that a mismatched toolchain produces warnings unique to them.

## Notes

- Lesson worth keeping: a red gate observed locally is not evidence of a red gate.
  Check CI before concluding the repository is at fault. This is the reasoning
  the `AGENTS.md` rule about not describing untraced mechanisms is meant to catch.
- No longer blocks
  [architecture-guardrails-in-ci](architecture-guardrails-in-ci.md).
