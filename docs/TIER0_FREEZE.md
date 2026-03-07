# RIE Tier-0 Freeze

This repository contains a frozen latest-green Tier-0 state.

## Freeze Definition

Tier-0 is green when a clean machine can deterministically:

1. parse-gate the authoritative scripts
2. run source validation selftests
3. run hash lookup selftests
4. run query selftests
5. emit a deterministic runner receipt
6. emit a deterministic sha256 manifest
7. print `RIE_TIER0_V1_OK`

## Authoritative Runner

`scripts/_RUN_rie_tier0_v1.ps1`

## Frozen Artifacts

- `test_vectors/frozen_latest_green/FREEZE_MANIFEST.txt`
- `test_vectors/frozen_latest_green/CANONICAL_STATUS.md`
- `proofs/receipts/rie.tier0.runner.v1.ndjson`
- `proofs/hashes/rie_tier0_runner_20260307_033840_sha256sums.txt`

## Lock Meaning

This freeze locks behavior for:
- source validation
- keyword indexing
- keyword querying
- hash publishing
- hash resolution
- result set generation
- receipt/hash manifest emission

UI work must conform to this locked behavior rather than redefine it.
