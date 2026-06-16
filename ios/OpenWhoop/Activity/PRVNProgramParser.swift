import Foundation

// MARK: - PRVNProgramParser
// Parsea texto pegado desde PRVN Español (SugarWOD / app PRVN).
// Espera secciones FUERZA · METCON · ACCESORIOS y opcionalmente días LUNES…DOMINGO.

enum PRVNProgramParser {

    private static let dayPattern = #"(?mi)^\s*(LUNES|MARTES|MI[ÉE]RCOLES|JUEVES|VIERNES|S[ÁA]BADO|DOMINGO|MON|TUE|WED|THU|FRI|SAT|SUN)\s*$"#

    private static let blockHeaders: [(kind: ProgramBlockKind, pattern: String)] = [
        (.warmup,    #"(?mi)^\s*(CALENTAMIENTO|WARM\s*-?\s*UP|WARMUP)\s*:?\s*$"#),
        (.strength,  #"(?mi)^\s*(FUERZA|STRENGTH|HALTERO|HALTEROFILIA|SKILLS?|T[EÉ]CNICA|FUERZA\s*/\s*STRENGTH)\s*:?\s*$"#),
        (.metcon,    #"(?mi)^\s*(METCON|MET\s*-?\s*CON|CONDICIONAMIENTO|WOD)\s*:?\s*$"#),
        (.accessory, #"(?mi)^\s*(ACCESORIOS|ACCESSORIES|ACCESORIO|EXTRA)\s*:?\s*$"#),
    ]

    /// Parsea una semana completa o un solo día (sin cabecera de día → `dayOffset` desde `weekStart`).
    static func parse(
        _ text: String,
        weekStart: Date,
        calendar: Calendar = .current
    ) -> PRVNWeekProgram {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let monday = calendar.startOfDay(for: weekStart)
        let weekStartKey = PRVNProgramStore.dayKey(for: monday, calendar: calendar)

        let dayChunks = splitByDays(normalized)
        let days: [PRVNDayProgram]
        if dayChunks.count > 1 || dayChunks.first?.weekdayOffset != nil {
            days = dayChunks.compactMap { chunk -> PRVNDayProgram? in
                guard let offset = chunk.weekdayOffset else { return nil }
                guard let date = calendar.date(byAdding: .day, value: offset, to: monday) else { return nil }
                return makeDay(id: PRVNProgramStore.dayKey(for: date, calendar: calendar),
                               weekday: offset + 1,
                               body: chunk.body)
            }
        } else {
            // Un solo día: reparte en los 7 slots si hay múltiples bloques, o asigna a hoy dentro de la semana
            let body = dayChunks.first?.body ?? normalized
            if body.isEmpty {
                days = []
            } else {
                let today = calendar.startOfDay(for: Date())
                let offset = max(0, min(6, calendar.dateComponents([.day], from: monday, to: today).day ?? 0))
                if let date = calendar.date(byAdding: .day, value: offset, to: monday) {
                    days = [makeDay(id: PRVNProgramStore.dayKey(for: date, calendar: calendar),
                                    weekday: offset + 1,
                                    body: body)]
                } else {
                    days = []
                }
            }
        }

        return PRVNWeekProgram(
            weekStart: weekStartKey,
            trackName: "PRVN Español",
            days: days.sorted { $0.id < $1.id },
            importedAt: Date()
        )
    }

    static func inferDayType(blocks: [ProgramBlock]) -> PRVNDayType {
        let hasStrength = blocks.contains { $0.kind == .strength }
        let hasMetcon = blocks.contains { $0.kind == .metcon }
        let strength = blocks.first { $0.kind == .strength }?.body.lowercased() ?? ""
        let metcon = blocks.first { $0.kind == .metcon }?.body.lowercased() ?? ""
        let all = (strength + " " + metcon).lowercased()

        if all.contains("descanso") || all.contains("rest day") { return .rest }
        if hasStrength && hasMetcon { return .mixed }
        if metcon.isEmpty && strength.isEmpty { return .mixed }

        let heavySignals = ["for load", "al max", "al máx", "complex", "complex", "1rm", "1 rm", "heavy",
                            "pesado", "build to", "x5", "x3", "x1", "@", "%"]
        let engineSignals = ["amrap", "emom", "for time", "por tiempo", "calorie", "caloría", "cal ",
                             "every ", "cada ", "tabata", "interval"]
        let skillSignals = ["skill", "técnica", "tecnica", "gymnastic", "gimnástica"]

        let heavyScore = heavySignals.filter { all.contains($0) }.count
        let engineScore = engineSignals.filter { all.contains($0) }.count
        let skillScore = skillSignals.filter { all.contains($0) }.count

        if engineScore >= 2 || (engineScore >= 1 && heavyScore == 0) { return .engine }
        if heavyScore >= 2 || (heavyScore >= 1 && engineScore == 0) { return .heavy }
        if skillScore >= 1 && heavyScore == 0 && engineScore == 0 { return .skill }
        return .mixed
    }

    // MARK: - Private

    private struct DayChunk {
        let weekdayOffset: Int?
        let body: String
    }

    private static func splitByDays(_ text: String) -> [DayChunk] {
        guard let dayRegex = try? NSRegularExpression(pattern: dayPattern) else {
            return [DayChunk(weekdayOffset: nil, body: text)]
        }
        let ns = text as NSString
        let matches = dayRegex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else {
            return [DayChunk(weekdayOffset: nil, body: text)]
        }

        var chunks: [DayChunk] = []
        for (idx, match) in matches.enumerated() {
            let name = ns.substring(with: match.range).trimmingCharacters(in: .whitespacesAndNewlines)
            let bodyStart = match.range.location + match.range.length
            let bodyEnd = idx + 1 < matches.count ? matches[idx + 1].range.location : ns.length
            let body = ns.substring(with: NSRange(location: bodyStart, length: bodyEnd - bodyStart))
            chunks.append(DayChunk(weekdayOffset: weekdayOffset(for: name), body: body))
        }
        return chunks
    }

    private static func weekdayOffset(for name: String) -> Int? {
        let n = name.uppercased()
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "es_ES"))
        switch n {
        case "LUNES", "MON": return 0
        case "MARTES", "TUE": return 1
        case "MIERCOLES", "WED": return 2
        case "JUEVES", "THU": return 3
        case "VIERNES", "FRI": return 4
        case "SABADO", "SAT": return 5
        case "DOMINGO", "SUN": return 6
        default: return nil
        }
    }

    private static func makeDay(id: String, weekday: Int, body: String) -> PRVNDayProgram {
        let blocks = parseBlocks(body)
        return PRVNDayProgram(
            id: id,
            weekday: weekday,
            dayType: inferDayType(blocks: blocks),
            blocks: blocks
        )
    }

    static func parseBlocks(_ text: String) -> [ProgramBlock] {
        let lines = text.components(separatedBy: "\n")
        var blocks: [ProgramBlock] = []
        var currentKind: ProgramBlockKind?
        var buffer: [String] = []
        var inlineTitle: String?

        func flush() {
            guard let kind = currentKind else { return }
            let body = buffer.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else { return }
            blocks.append(ProgramBlock(kind: kind, title: inlineTitle, body: body))
            buffer = []
            inlineTitle = nil
        }

        for line in lines {
            if let (kind, title) = matchBlockHeader(line) {
                flush()
                currentKind = kind
                inlineTitle = title
                continue
            }
            if currentKind == nil {
                if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                    currentKind = .other
                }
            }
            buffer.append(line)
        }
        flush()

        if blocks.isEmpty, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            blocks.append(ProgramBlock(kind: .other, body: text))
        }
        return blocks
    }

    private static func matchBlockHeader(_ line: String) -> (ProgramBlockKind, String?)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        for (kind, pattern) in blockHeaders {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let ns = trimmed as NSString
            let range = NSRange(location: 0, length: ns.length)
            if regex.firstMatch(in: trimmed, range: range) != nil {
                return (kind, nil)
            }
        }
        // "METCON — Morpheus" inline
        for (kind, label) in [(ProgramBlockKind.metcon, "METCON"), (.strength, "FUERZA"), (.accessory, "ACCESORIOS")] {
            if trimmed.uppercased().hasPrefix(label) {
                let rest = trimmed.dropFirst(label.count).trimmingCharacters(in: CharacterSet(charactersIn: ":-–— "))
                return (kind, rest.isEmpty ? nil : rest)
            }
        }
        return nil
    }
}
