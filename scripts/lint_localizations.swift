#!/usr/bin/env swift
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Sources/HelperApp/Resources")
let expectedLocales = ["en", "de", "fr", "es", "es-MX", "pt-BR", "ko", "ja", "zh-Hans", "zh-Hant"]

func keys(at url: URL) throws -> Set<String> {
    let text = try String(contentsOf: url, encoding: .utf8)
    let expression = try NSRegularExpression(pattern: #"(?m)^\s*\"([^\"]+)\"\s*="#)
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    return Set(expression.matches(in: text, range: range).compactMap { match in
        guard let keyRange = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[keyRange])
    })
}

let referenceURL = root.appendingPathComponent("en.lproj/Localizable.strings")
let referenceKeys = try keys(at: referenceURL)
var failures: [String] = []

for locale in expectedLocales {
    let url = root.appendingPathComponent("\(locale).lproj/Localizable.strings")
    guard FileManager.default.fileExists(atPath: url.path) else {
        failures.append("missing locale: \(locale)")
        continue
    }
    let localeKeys = try keys(at: url)
    let missing = referenceKeys.subtracting(localeKeys).sorted()
    let extra = localeKeys.subtracting(referenceKeys).sorted()
    if !missing.isEmpty { failures.append("\(locale) missing: \(missing.joined(separator: ", "))") }
    if !extra.isEmpty { failures.append("\(locale) extra: \(extra.joined(separator: ", "))") }
}

if failures.isEmpty {
    print("Localization coverage passed: \(expectedLocales.count) locales, \(referenceKeys.count) keys")
} else {
    failures.forEach { fputs("\($0)\n", stderr) }
    exit(EXIT_FAILURE)
}

