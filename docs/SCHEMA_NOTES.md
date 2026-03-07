# Schema Notes

- All schemas are versioned as `rie.<name>.v1`.
- JSON Schema draft: 2020-12.
- Deterministic ordering is a producer responsibility; schemas enforce structure and prohibitions (e.g., no answer fields).
- `additionalProperties: false` is used to prevent accidental drift.
