import Foundation

/// Offline presentation metadata, keyed only by the exact base Title ID.
/// Provenance/status fields stay in the file for maintenance, outside the UI.
public struct LocalizedGameNames: Decodable {
    public struct Entry: Decodable {
        public let status: String
        public let zh_hans: String?
    }
    public let schema: Int
    public let names: [String: Entry]

    public static func load(from file: URL) throws -> LocalizedGameNames {
        try JSONDecoder().decode(Self.self, from: Data(contentsOf: file))
    }

    public func chineseName(for titleID: String) -> String? {
        guard schema == 1, titleID.count == 16,
              titleID.allSatisfy({ $0.isHexDigit }),
              let entry = names[titleID.uppercased()], entry.status == "verified",
              let value = entry.zh_hans?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty, value.range(of: "\\p{Han}", options: .regularExpression) != nil else { return nil }
        return value
    }
}
