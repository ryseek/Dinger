import Foundation

// Tiny CLI wrapper around Importer. Usage:
//   swift run dictimporter <input.txt> <output.sqlite> [--name NAME --version VERSION --sentences PATH]
//
// Defaults point at the repo-relative paths so `swift run DictImporter`
// with no arguments does the right thing when invoked from Tools/DictImporter.

struct CLI {
    static func main() async {
        let args = CommandLine.arguments.dropFirst()
        var input: String? = nil
        var output: String? = nil
        var sentences: String? = nil
        var shouldImportSentences = true
        var name = "TU-Chemnitz DE-EN"
        var version = "unknown"

        var it = args.makeIterator()
        while let arg = it.next() {
            switch arg {
            case "--name":    name = it.next() ?? name
            case "--version": version = it.next() ?? version
            case "--sentences": sentences = it.next()
            case "--no-sentences": shouldImportSentences = false
            case "-h", "--help":
                print("usage: dictimporter <input.txt> <output.sqlite> [--name NAME --version VERSION --sentences PATH]")
                exit(0)
            default:
                if input == nil { input = arg }
                else if output == nil { output = arg }
            }
        }

        // Resolve defaults relative to the repo root (two levels up from the
        // executable's Package.swift directory).
        let repoRoot = findRepoRoot() ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let inputURL: URL = {
            if let p = input { return URL(fileURLWithPath: p) }
            return repoRoot.appendingPathComponent("resources/de-en.txt.2026-04-01")
        }()
        let outputURL: URL = {
            if let p = output { return URL(fileURLWithPath: p) }
            return repoRoot.appendingPathComponent("Dinger/Resources/de-en.sqlite")
        }()
        let sentencePairsURL: URL? = {
            guard shouldImportSentences else { return nil }
            if let p = sentences { return URL(fileURLWithPath: p) }
            let defaultURL = repoRoot.appendingPathComponent("resources/sentence_pairs_de-en.tsv")
            return FileManager.default.fileExists(atPath: defaultURL.path) ? defaultURL : nil
        }()

        FileHandle.standardError.write(Data("Importing \(inputURL.lastPathComponent) → \(outputURL.path)\n".utf8))
        if let sentencePairsURL {
            FileHandle.standardError.write(Data("Including examples from \(sentencePairsURL.lastPathComponent)\n".utf8))
        }

        let parser = TuChemnitzParser()
        let importer = Importer(parser: parser,
                                sourceURL: inputURL,
                                outputURL: outputURL,
                                dictName: name,
                                dictVersion: version,
                                sentencePairsURL: sentencePairsURL)

        let start = Date()
        do {
            let stats = try importer.run { count, _ in
                FileHandle.standardError.write(Data("  \(count) entries processed\n".utf8))
            }
            let elapsed = Date().timeIntervalSince(start)
            let sizeMB = (try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? Int)
                .flatMap { Double($0) / 1_048_576.0 } ?? 0
            print("""
            Done in \(String(format: "%.1f", elapsed))s
              entries: \(stats.entries)
              senses:  \(stats.senses)
              terms:   \(stats.terms)
              examples: \(stats.exampleSentences)
              skipped: \(stats.skipped)
              example skipped: \(stats.exampleSkipped)
              output:  \(String(format: "%.1f", sizeMB)) MB
            """)
        } catch {
            FileHandle.standardError.write(Data("ERROR: \(error)\n".utf8))
            exit(1)
        }
    }

    /// Walk up from the current working directory looking for the Dinger.xcodeproj
    /// sibling, so the tool works whether it's invoked from Tools/DictImporter
    /// or the repo root.
    static func findRepoRoot() -> URL? {
        let fm = FileManager.default
        var dir = URL(fileURLWithPath: fm.currentDirectoryPath)
        for _ in 0..<6 {
            if fm.fileExists(atPath: dir.appendingPathComponent("Dinger.xcodeproj").path) {
                return dir
            }
            let parent = dir.deletingLastPathComponent()
            if parent.path == dir.path { break }
            dir = parent
        }
        return nil
    }
}

await CLI.main()
