import Foundation

// MARK: - PRVNBlockSummary
// Una línea legible con los movimientos principales de cada bloque PRVN.

enum PRVNBlockSummary {

  /// Resumen compacto para la tarjeta de hoy (ej. "Back Squat · Muscle Clean · Power Clean").
  static func oneLine(for block: ProgramBlock) -> String {
    let sections = block.body
      .components(separatedBy: "\n\n")
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }

    var titles: [String] = []
    for section in sections {
      if let title = primaryTitle(in: section, kind: block.kind) {
        titles.append(title)
      }
    }

    if titles.isEmpty {
      return fallbackLines(block.body, kind: block.kind)
    }
    return dedupe(titles).joined(separator: " · ")
  }

  // MARK: - Private

  private static func primaryTitle(in section: String, kind: ProgramBlockKind) -> String? {
    let lines = section
      .components(separatedBy: .newlines)
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }

    for line in lines {
      if isNoiseLine(line) { continue }
      if let quoted = quotedName(line) { return quoted }
      if kind == .metcon, isMetconHeader(line) { return cleanMetconHeader(line) }
      if line.count >= 3, line.count <= 72 { return line }
    }
    return nil
  }

  private static func fallbackLines(_ body: String, kind: ProgramBlockKind) -> String {
    let lines = body
      .components(separatedBy: .newlines)
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty && !isNoiseLine($0) }

    if kind == .metcon, let wod = lines.compactMap({ quotedName($0) ?? (isMetconHeader($0) ? cleanMetconHeader($0) : nil) }).first {
      return wod
    }

    return lines.prefix(3).joined(separator: " · ")
  }

  private static func quotedName(_ line: String) -> String? {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard let first = trimmed.first, first == "\"" || first == "'" else { return nil }
    return trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
  }

  private static func isMetconHeader(_ line: String) -> Bool {
    let low = line.lowercased()
    return low.contains("amrap") || low.contains("emom") || low.contains("for time")
      || low.contains("por tiempo") || low.contains("por calor")
      || low.contains("tabata") || low.hasPrefix("every ") || low.hasPrefix("cada ")
  }

  private static func cleanMetconHeader(_ line: String) -> String {
    line.replacingOccurrences(of: "  ", with: " ")
  }

  private static func isNoiseLine(_ line: String) -> Bool {
    let low = line.lowercased()
      .folding(options: .diacriticInsensitive, locale: Locale(identifier: "es_ES"))

    if low.count < 2 { return true }

    let exactNoise: Set<String> = [
      "fuerza", "strength", "warmup", "calentamiento", "accesorios", "accesorio",
      "weightlifting", "weigthlifting", "haltero", "halterofilia", "skills", "skill",
      "técnica", "tecnica", "wod", "metcon",
    ]
    if exactNoise.contains(low) { return true }

    let prefixes = [
      "parte a", "parte b", "parte c", "for load", "por carga", "por calidad",
      "por tiempo", "for time", "el porcentaje", "% is based", "registrar",
      "record ", "notas del coach", "notas:", "objetivo principal", "objetivo secundario",
      "nivel 1", "nivel 2", "nivel 3", "hombres —", "mujeres —", "hombres -", "mujeres -",
      "-rest", "rest ", "barra:", "barra ", "score:", "rpe:", "objetivo:",
    ]
    if prefixes.contains(where: { low.hasPrefix($0) }) { return true }

    if low.hasPrefix("luego") || low.hasPrefix("-luego") { return true }

    // Solo sets/reps sin nombre de movimiento
    if low.range(of: #"^\d+\s*(sets?|rondas?|rounds?)\b"#, options: .regularExpression) != nil {
      return true
    }
    if low.range(of: #"^\d+/\d+"#, options: .regularExpression) != nil { return true }

    return false
  }

  private static func dedupe(_ items: [String]) -> [String] {
    var seen = Set<String>()
    var out: [String] = []
    for item in items {
      let key = item.lowercased()
      if seen.insert(key).inserted { out.append(item) }
    }
    return out
  }
}
