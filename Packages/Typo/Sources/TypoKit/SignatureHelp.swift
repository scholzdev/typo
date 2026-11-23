import Foundation
import TypstEngine

extension Project {
    /// Signature help at `offset` (UTF-16) of the current text of `file`: nil outside a call's parentheses, inside a
    /// content block, for an unknown callee, or when a newer request superseded this one.
    public func signatureHelp(in file: RelPath, at offset: Int) async -> SignatureHelp? {
        let answer = await ask { reply in .signatureHelp(SignatureHelpRequest(file: file, cursor: offset, reply: reply)) }
        defer { trimLog() }
        return answer?.help
    }
}
