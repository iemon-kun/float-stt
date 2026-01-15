import Foundation

enum LocalRefiner {
    static func refine(_ text: String) -> String {
        var result = text

        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        result = replaceRepeatedPunctuation(result)
        result = normalizeSpaces(result)
        result = normalizeNewlines(result)
        result = trimLines(result)

        return result
    }

    private static func replaceRepeatedPunctuation(_ text: String) -> String {
        var out = text
        out = out.replacingOccurrences(of: "。。", with: "。")
        out = out.replacingOccurrences(of: "、、", with: "、")
        out = out.replacingOccurrences(of: "！！", with: "！")
        out = out.replacingOccurrences(of: "？？", with: "？")
        return out
    }

    private static func normalizeSpaces(_ text: String) -> String {
        let pattern = "[ \\t]{2,}"
        return text.replacingOccurrences(
            of: pattern,
            with: " ",
            options: .regularExpression
        )
    }

    private static func normalizeNewlines(_ text: String) -> String {
        let pattern = "\\n{3,}"
        return text.replacingOccurrences(
            of: pattern,
            with: "\n\n",
            options: .regularExpression
        )
    }

    private static func trimLines(_ text: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let trimmed = lines.map { $0.trimmingCharacters(in: .whitespaces) }
        return trimmed.joined(separator: "\n")
    }
}
