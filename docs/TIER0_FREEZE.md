# RIE Tier-0 Freeze

## What is frozen
This document records the first locked green Tier-0 state for RIE.

## Authoritative runner
- `scripts/_RUN_rie_tier0_v1.ps1`

## Authoritative selftests
- `scripts/_selftest_rie_v1.ps1`
- `scripts/_selftest_rie_hash_lookup_v1.ps1`
- `scripts/_selftest_rie_query_v1.ps1`

## Core locked capabilities
- deterministic source-record validation
- deterministic keyword index generation
- deterministic query result-set generation
- deterministic hash-store publish/resolve
- deterministic receipts and hash manifests

## Freeze evidence
- `proofs/receipts/rie.tier0.runner.v1.ndjson`
- `proofs/hashes/rie_tier0_runner_20260307_033840_sha256sums.txt`
- `proofs/index/rie.keyword_index.v1.json`
- `proofs/queries/rie_result_set_example_lecture_demo.json`
- `test_vectors/frozen_latest_green/FREEZE_MANIFEST.txt`
- `test_vectors/frozen_latest_green/CANONICAL_STATUS.md`

## Freeze token
`RIE_TIER0_V1_OK`

## Notes
This freeze captures standalone Tier-0 behavior only. UI/product layers and future integrations must conform to this frozen behavior rather than redefine it.
