# QA Cases for Smart Web Fetch Contract

This file maps lightweight offline fixtures to `docs/fetch-contract.md` rules so changes can be validated without live network calls.

## Fixture Mapping

- `fixtures/markdown-success.json`
  - Expected: pass as non-empty, threshold-compliant structured response.
  - Contract refs: section 3 (success criteria).
  - Note: for Bash, this case should still pass for `markdown.new` when `jq` is unavailable (via built-in fallback extraction).

- `fixtures/structured-error.json`
  - Expected: fail as structured error payload.
  - Contract refs: section 4 (structured error detection).

- `fixtures/html-error-page.html`
  - Expected: fail for JSON-expected providers when content type is HTML.
  - Contract refs: section 5 (HTML error page detection).

- `fixtures/too-short.txt`
  - Expected: fail for providers requiring minimum length > 5 chars.
  - Contract refs: section 3 (minimum length thresholds).

## Suggested Regression Workflow

1. Update `docs/fetch-rules.json` first when changing thresholds/keywords.
2. Re-check both CLIs for parity with `docs/fetch-contract.md`.
3. Validate fixture expectations before merging behavior changes.
