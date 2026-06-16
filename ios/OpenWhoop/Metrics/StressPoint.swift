import Foundation

struct StressPoint: Identifiable, Equatable {
    let ts: Int
    let score: Double?
    let quality: String

    var id: Int { ts }

    var isScored: Bool { score != nil && quality == "good" }
}
