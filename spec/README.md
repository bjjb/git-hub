# spec

Tests for `git-hub`.

## Conventions

- Every `src/*.cr` file has a corresponding
  `spec/*_spec.cr`
- No `spec_helper.cr` — each spec requires what it needs
  directly (`require "spec"` and specific source files)
- Spec examples should be self-contained — no hidden
  shared state
- Reusable test helpers belong in `spec/support/`
- Run the full suite with `crystal spec`
