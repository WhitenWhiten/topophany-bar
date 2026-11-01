Synthetic monitor frames captured from `topo monitor stream` with `source: "preview"`. No credentials, saved profiles or live infrastructure were used. Tests evaluate at each frame's `generated_at` clock.

- `preview.ndjson`: preview scenario 0, 2026-11-01, Topophany commit `f9e4fba`. Selectors: check `m-clash`, link `home-cf`.
- `assessment.ndjson`: preview scenario 10, 2026-11-01, Topophany commit `1ce54a3` (after 1.5.2), run with an empty environment and a temporary `HOME`. Rows: `summary.verdict` (coverage reasons), `services.list`, `service.card` for `memos`, `blog` and `home-rproxy` (assessment, `unknown_reason`), and `check.card` for `w-ts-transit` (Tailscale) and `m-clash` (diagnostic `policy`, `duration_ms`).
