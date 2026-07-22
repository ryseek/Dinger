# Dictionary storage size findings

Status: nice-to-have architecture work; no application change is included in this note.

Date investigated: 2026-07-22

## Summary

The installed size is dominated by the production `de-en.sqlite` database, not by the app binary or a prospective translation-ranking index.

The observed iPhone storage report was:

| iOS category | Reported size |
|---|---:|
| App Size | 388.8 MB |
| Documents & Data | 373.5 MB |
| Total | 762.3 MB |

The bundled `Dinger/Resources/de-en.sqlite` file is 352 MiB (about 369 MB in decimal units). It accounts for nearly all of **App Size**. On first launch, `AppDatabase.ensureOnDeviceSeed` copies the complete seed database to `Application Support/Dinger/dinger.sqlite`, accounting for nearly all of **Documents & Data**. The remaining space is the executable, assets, user records, and potentially SQLite WAL/SHM files.

Relevant implementation: `Dinger/Core/Persistence/AppDatabase.swift`, particularly `ensureOnDeviceSeed` around lines 94–108.

## Actual seed database composition

The measurements below come from SQLite's `dbstat` virtual table against the production seed.

| Component | Approximate size |
|---|---:|
| `example_sentence` table (577,583 rows) | 99.6 MiB |
| Example-sentence FTS structures | 41.2 MiB |
| Example uniqueness index | 9.2 MiB |
| `term` table (1,197,629 rows) | 81.0 MiB |
| Term FTS structures | 35.2 MiB |
| Term B-tree indexes | 42.9 MiB |
| Raw `entry` table (205,907 rows) | 29.8 MiB |
| `sense` table and index (411,964 rows) | 13.1 MiB |
| **Total** | **351.9 MiB** |

The example-sentence subsystem occupies about 150 MiB. Term rows and their search indexes occupy about 159 MiB. The remaining roughly 43 MiB is primarily raw dictionary entries and senses.

## Why a compact index estimate is much smaller

A separate proof-of-concept SQLite index containing one joined German/English row per sense measured about 48 MiB with FTS. That estimate did not include the full production representation:

- 577,583 example-sentence pairs;
- original and normalized copies of sentence text;
- nearly 1.2 million separate term rows;
- complete raw dictionary source lines;
- multiple B-tree indexes;
- FTS token-position and document-size metadata.

The current 1,188-card lexical index itself is small: approximately 70–90 KB as compact JSON, depending on whether all dictionary alternatives are indexed. Precomputed translation ranking would add only a few kilobytes for current cards, or roughly 0.6–1.1 MB for the full dictionary. It is not a material contributor to installed size.

## Option 1: split immutable and mutable storage

Keep the bundled dictionary database read-only and create a separate writable database containing only:

- decks;
- cards and selected-term references;
- SRS state;
- review history;
- search/open history.

The dictionary can be attached read-only to the user database so cross-database joins remain possible. SQLite cannot enforce foreign keys across attached databases, but the current `card` schema already stores `sense_id`, `front_term_id`, and `back_term_id` as plain integer references rather than foreign keys to dictionary tables.

This is an architectural change, but it does not need to break user data. A safe migration should:

1. Leave the legacy `dinger.sqlite` untouched while migration is prepared.
2. Create a new user-only database.
3. Copy user tables while preserving primary keys and review history.
4. Attach the bundled seed read-only.
5. Verify that every stored sense and term ID resolves in the seed.
6. Compare deck, card, SRS, and review counts.
7. Atomically activate the new user database.
8. Remove the legacy database only after a later successful launch.

The seed's dictionary IDs must remain stable. A future compact-database rebuild should either preserve IDs or remap cards using stable semantic information already present in exports: source/target language, raw entry, sense position, and selected term surfaces.

Expected benefit: recover approximately 370 MB from **Documents & Data**. The bundled app would still contain the 352 MiB seed until the seed itself is optimized.

## Option 2: separate example sentences

Move example sentences into an optional downloadable/read-only database. This removes roughly 150 MiB from the base seed and lets users remove the pack independently.

This is less invasive than a full dictionary-schema redesign, but existing installations still need a migration or database replacement to reclaim allocated SQLite pages. Dropping tables alone does not shrink the file without `VACUUM` or rebuilding into a new database.

## Option 3: compact the runtime dictionary schema

Potential reductions include:

- omit `entry.raw` if it is not required at runtime, or replace it with a stable compact key;
- avoid storing both display and normalized text where normalization is deterministic;
- review whether every B-tree index is required by actual queries;
- use contentless FTS and disable unnecessary position/document-size detail;
- store example text once instead of duplicating normalized text;
- keep examples as a separate removable pack.

The measured compact proof of concept suggests a dictionary-only target of approximately 50–80 MB is realistic, depending on retained metadata and search behavior.

## Possible target footprint

| Component | Target estimate |
|---|---:|
| Base app and compact dictionary | 60–90 MB |
| Writable user database | Under 5 MB for normal usage |
| Optional example-sentence pack | Separate and removable |
| Translation-ranking metadata | Under 2 MB for the full dictionary |

These are engineering targets, not yet validated release-build measurements.

## Reproduction queries

```sh
ls -lh Dinger/Resources/de-en.sqlite

sqlite3 Dinger/Resources/de-en.sqlite \
  "PRAGMA page_size; PRAGMA page_count; PRAGMA freelist_count;"

sqlite3 -header -column Dinger/Resources/de-en.sqlite \
  "SELECT name, SUM(pgsize) AS bytes, COUNT(*) AS pages
     FROM dbstat
    GROUP BY name
    ORDER BY bytes DESC;"

sqlite3 -header -column Dinger/Resources/de-en.sqlite \
  "SELECT 'entry' AS table_name, COUNT(*) AS rows FROM entry
   UNION ALL SELECT 'sense', COUNT(*) FROM sense
   UNION ALL SELECT 'term', COUNT(*) FROM term
   UNION ALL SELECT 'example_sentence', COUNT(*) FROM example_sentence;"
```

## Recommended order

1. Split the writable user database from immutable content, using a guarded migration.
2. Make example sentences a separate optional pack.
3. Rebuild and benchmark a compact seed against existing dictionary-search tests.
4. Measure Release/App Store installation size, first-launch migration time, and peak temporary disk usage on a physical device.

