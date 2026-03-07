# Instrument Constitution v1 (No-Answers Rule)

RIE is an **instrument**, not an answer engine.

## Prohibited outputs (MUST NOT)
- final answers to questions
- step-by-step solution procedures
- “here is the solution” math derivations
- essay writing, paraphrasing, rewriting, grammar correction
- code generation that directly solves a graded or homework-like prompt

## Allowed outputs (MAY)
- lists of sources with bibliographic metadata
- short excerpts/snippets (bounded by policy in the consuming UI)
- timestamp pointers into videos/lectures
- section pointers into textbooks/notes
- provenance fields (URLs, DOIs, archive identifiers, access times)
- credential/trust signals (ORCID, university affiliation evidence, DOI publisher metadata)
- “where to look” guidance as pointers, not explanations

## Required labeling
Every result MUST carry:
- `provenance` fields (at minimum: discovered_from, retrieved_at_utc)
- an explicit `content_kind` classification
- zero “answer” fields (no `answer`, `solution`, `explain`, `steps`, etc.)

## Negative vectors
Schemas and conformance tests SHOULD reject:
- any record containing answer-like fields
- missing provenance in exported bundles
