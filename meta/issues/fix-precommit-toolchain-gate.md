# Fix the precommit toolchain gate

## Summary

`mix precommit` fails at its first step, `compile --warnings-as-errors`, on
`main`. `mise.toml` pins `elixir = "1.19.0-otp-28"`, but that version is not
installed in the working environment, so Elixir 1.20/OTP 29 is used instead
and its stricter type warnings fire in files nobody is editing (for example
`lib/egregoros/html.ex` and `lib/egregoros_web/live/status_live.ex`).

The practical effect is that the whole precommit gate is red by default, so
it stops being a signal and no new CI gate can be trusted on top of it.

## Requirements

- Decide the supported toolchain: either install/pin 1.19.0-otp-28 everywhere
  (including CI) or move the pin forward to the version actually in use.
- If moving forward, fix the warnings the newer compiler surfaces rather than
  relaxing `--warnings-as-errors`.
- Make CI and local development agree on the pinned version.

## Acceptance Criteria

- `mix precommit` passes from a clean checkout on the pinned toolchain.
- CI uses the same version as `mise.toml`.
- No step of precommit is skipped or downgraded to make it pass.

## Notes

- Coverage gate context: total is currently ~85%, right at the configured
  threshold, so the coverage step is also fragile.
- Blocks [architecture-guardrails-in-ci](architecture-guardrails-in-ci.md).
