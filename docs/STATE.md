\# Research Infrastructure Engine (RIE)



Tier-0 Instrument — Canonical State Snapshot

Date: 2026-03-06



---



\# WHAT THIS PROJECT IS (TO SPEC)



\*\*Research Infrastructure Engine (RIE)\*\* is a \*\*deterministic research retrieval instrument\*\*, not an AI answer engine.



Its purpose is to allow a user to input:



\* keywords

\* formulas

\* images

\* concepts

\* citations



and retrieve \*\*verified educational sources\*\* such as:



\* lectures

\* textbooks

\* research papers

\* lab publications

\* university course materials

\* verified educational channels



RIE \*\*never generates answers or explanations\*\*.

Instead it returns \*\*evidence references\*\*.



Examples:



| Query                  | Output                                                       |

| ---------------------- | ------------------------------------------------------------ |

| Maxwell curl equation  | lecture timestamps, textbook section, MIT OCW lecture        |

| Laplace transform      | course lecture, textbook chapter, verified derivation videos |

| photo of lab apparatus | research papers + lab documentation                          |



The system is closer to:



\*\*Google Scholar + citation engine + verified education index\*\*



not:



\* ChatGPT

\* Wolfram Alpha

\* Grammarly

\* AI tutoring systems



---



\# CORE PRINCIPLES (LOCKED)



\### 1. No-Answer Law



RIE \*\*must never produce solutions or explanations\*\*.



Allowed outputs:



\* sources

\* references

\* timestamps

\* citations

\* datasets

\* textbooks

\* labs

\* course materials



Forbidden outputs:



\* solved homework

\* generated explanations

\* AI summaries

\* step-by-step solutions



---



\### 2. Evidence First



All results must reference:



\* educational institutions

\* labs

\* textbooks

\* journals

\* accredited educators



---



\### 3. Deterministic Retrieval



Queries must resolve to deterministic result sets where possible.



RIE is an \*\*instrument\*\*, not an AI oracle.



---



\### 4. Verified Source Model



Each indexed object must include:



```

source\_record.v1

```



Example:



```json

{

&nbsp; "schema": "rie.source\_record.v1",

&nbsp; "source\_id": "s\_vid\_001",

&nbsp; "content\_kind": "video",

&nbsp; "title": "Example Lecture",

&nbsp; "provenance": {

&nbsp;   "discovered\_from": "https://example.edu/course/page",

&nbsp;   "retrieved\_at\_utc": "2026-02-23T00:00:00Z"

&nbsp; },

&nbsp; "tags": \["demo"]

}

```



---



\# CORE DATA TYPES



\## Source Record



```

rie.source\_record.v1

```



Represents:



\* lecture

\* paper

\* textbook

\* lab documentation



---



\## Retrieval Result



```

rie.result\_set.v1

```



Represents:



\* list of source records

\* ranked

\* grouped by type



---



\## Evidence Bundle



```

rie.evidence\_bundle.v1

```



Exportable research artifact containing:



\* query

\* results

\* sources

\* citations



---



\# REPO STRUCTURE (LOCKED)



```

rie

│

├─ scripts

│   rie\_lib\_v1.ps1

│   \_selftest\_rie\_v1.ps1

│

├─ test\_vectors

│   minimal\_valid

│      source\_record.v1.json

│      source\_record.forbidden\_prop.json

│

├─ proofs

│   logs

│   handoff

│

├─ docs

│   SPEC.md

│   STATE.md

```



---



\# CURRENT STATE



Current runtime state after debugging session:



| Component                    | Status             |

| ---------------------------- | ------------------ |

| repo skeleton                | GREEN              |

| selftest runner              | RED                |

| JSON parser                  | unstable           |

| validator                    | unstable           |

| tags array handling          | failing            |

| PS5.1 compatibility          | partial            |

| deterministic run discipline | mostly implemented |



Primary runtime failure:



```

TAGS\_NOT\_ARRAY:tv.source\_record

```



Diagnostic output shows:



```

TAGS\_TYPE=System.String

TAGS\_JOIN=demo

```



Meaning:



```

"tags": \["demo"]

```



is currently being parsed as:



```

"tags": "demo"

```



by the JSON layer.



Root cause likely lies in:



```

JavaScriptSerializer + DeepToHashtable conversion

```



coercing single-element arrays incorrectly.



---



\# WBS — REMAINING WORK



\## PHASE 1 — Parser Stabilization



Tasks:



\* Fix `RIE-ParseJson` array handling

\* Ensure arrays remain arrays after conversion

\* Stabilize `DeepToHashtable`



Outcome:



```

tags -> object\[] or ArrayList

```



instead of string.



---



\## PHASE 2 — Validator Contract Lock



Tasks:



\* finalize `RIE-ValidateSourceRecordV1`

\* enforce:



Required fields:



```

schema

source\_id

content\_kind

title

provenance

tags

```



Forbidden fields:



```

answer

solution

steps

```



---



\## PHASE 3 — Deterministic Selftest



Selftest must verify:



Positive case:



```

POS\_SOURCE\_RECORD\_OK

```



Negative case:



```

NEG\_FORBIDDEN\_PROP\_OK

```



Final success token:



```

RIE\_SELFTEST\_V1\_OK

```



---



\## PHASE 4 — Hash Resolution Layer



Add deterministic hash lookup.



Functions:



```

RIE-HashFileUtf8NoBomLf

RIE-ResolveByHash

```



Purpose:



\* reference sources by hash

\* guarantee content integrity



---



\## PHASE 5 — Evidence Bundle Export



Implement:



```

rie.evidence\_bundle.v1

```



Contains:



\* query

\* sources

\* citations

\* hashes



Export format:



```

bundle.json

sha256sums.txt

```



---



\## PHASE 6 — Retrieval Engine



Initial retrieval layer:



\* keyword

\* formula

\* tag

\* concept



Later expansions:



\* image lookup

\* citation graph

\* formula parser



---



\# DEFINITION OF DONE (Tier-0)



RIE Tier-0 is complete when:



1️⃣ Deterministic selftest passes



```

RIE\_SELFTEST\_V1\_OK

```



2️⃣ JSON parsing stable under PS5.1



3️⃣ validator rejects forbidden fields



4️⃣ evidence bundle export works



5️⃣ hash verification works



6️⃣ repository parse-gates clean



---



\# CURRENT COMPLETION ESTIMATE



Specification completeness: \*\*80%\*\*



Implementation completeness: \*\*55%\*\*



Tier-0 readiness: \*\*35%\*\*



Primary blocker:



```

PS5.1 JSON array coercion

```



Once the parser stabilizes and the selftest goes green, completion will jump quickly.



Expected milestone progression:



```

Selftest green → 60%

Hash layer → 70%

Evidence bundles → 80%

Retrieval prototype → 90%

Tier-0 complete → 100%

```



---



\# POSITION IN THE ECOSYSTEM



RIE will integrate with:



\* \*\*Observatory\*\* (knowledge ingest)

\* \*\*CSL\*\* (canonical JSON)

\* \*\*WatchTower\*\* (verification)

\* \*\*NFL\*\* (witness receipts)

\* \*\*Index Lens\*\* (content indexing)



RIE becomes the \*\*educational knowledge instrument\*\* of the ecosystem.

