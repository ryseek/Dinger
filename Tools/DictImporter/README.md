# DictImporter

`DictImporter` builds the bundled SQLite dictionary used by Dinger.

The generated database is written to `Dinger/Resources/de-en.sqlite`. That file is intentionally ignored by git because it is generated from the source resources.

## Inputs

The importer expects these uncompressed files at the repo root:

- `resources/de-en.txt.2026-04-01`
- `resources/sentence_pairs_de-en.tsv`

Only the compressed source files are tracked in git:

- `resources/de-en.txt.2026-04-01.gz`
- `resources/sentence_pairs_de-en.tsv.gz`

## Regenerate The Database

From the repo root, decompress the source resources if needed:

```sh
gunzip -k resources/de-en.txt.2026-04-01.gz
gunzip -k resources/sentence_pairs_de-en.tsv.gz
```

Then run the importer:

```sh
cd Tools/DictImporter
swift run DictImporter
```

With no arguments, the tool reads:

- `../../resources/de-en.txt.2026-04-01`
- `../../resources/sentence_pairs_de-en.tsv` if present

and writes:

- `../../Dinger/Resources/de-en.sqlite`

You can also pass explicit paths:

```sh
swift run DictImporter \
  ../../resources/de-en.txt.2026-04-01 \
  ../../Dinger/Resources/de-en.sqlite \
  --sentences ../../resources/sentence_pairs_de-en.tsv \
  --name "TU-Chemnitz DE-EN" \
  --version "2026-04-01"
```

To build the dictionary without example sentences:

```sh
swift run DictImporter --no-sentences
```

## After Regeneration

Build the app so Xcode copies the regenerated SQLite into the app bundle:

```sh
xcodebuild -project Dinger.xcodeproj \
  -scheme Dinger \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  build
```

Existing app installs keep their user data. On launch, Dinger migrates the existing on-device database and copies bundled example sentences into it if they are missing.
