# Research Infrastructure Engine (RIE)

RIE is a STEM retrieval + evidence instrument.

It accepts queries (keywords, formulas, images/diagrams) and returns **educational sources** (videos w/ timestamps, textbook sections, papers, datasets) with **provenance + credential signals**.

RIE is **not** an answer engine:
- no final answers
- no step-by-step solutions
- no essay-writing / rewriting / Grammarly-style output

## Repo structure
- `docs/` — project layer description + constitution
- `schemas/` — canonical JSON Schemas for core objects
- `test_vectors/` — minimal positive + negative vectors for schema conformance

## Canonical objects (v1)
- `rie.query_record.v1`
- `rie.source_record.v1`
- `rie.segment_pointer.v1`
- `rie.trust_signal.v1`
- `rie.evidence_bundle_manifest.v1`
- `rie.result_set.v1`

See:
- docs/INSTRUMENT_CONSTITUTION_V1.md
- docs/TRUST_MODEL_V1.md
- schemas/*.schema.json
