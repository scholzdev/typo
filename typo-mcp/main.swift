import Foundation
import TypoKit
import JSONRPC
import MCPProtocol
import TypoMCP
import TypstEngine

// stdout carries only protocol messages: whatever else prints (Swift, the Rust bridge) goes to stderr.
let protocolOut = FileHandle(fileDescriptor: dup(STDOUT_FILENO), closeOnDealloc: true)
dup2(STDERR_FILENO, STDOUT_FILENO)

let args = Array(CommandLine.arguments.dropFirst())
var start = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
if let i = args.firstIndex(of: "--project"), i + 1 < args.count {
    start = URL(fileURLWithPath: (args[i + 1] as NSString).expandingTildeInPath)
}
let root = TypoMCPTools.projectRoot(from: start)
FileHandle.standardError.write(Data("typo-mcp: project \(root?.path ?? "none (pass --project <folder>)")\n".utf8))
TypstRuntime.warmUp()

let (lines, sink) = AsyncStream.makeStream(of: Data.self)
Thread {
    JSONRPCLines.read(STDIN_FILENO) { sink.yield($0) }
    sink.finish()
}.start()

Task { @MainActor in
    // Bundle.main is Typo.app here, so its defaults are the app's: the local packages folder it set.
    let server = MCPServer(name: "typo", version: TypoMCPInfo.version,
                           tools: TypoMCPTools(root: root, localPackages: LocalPackagesFolder.stored()))
    for await line in lines {
        if let reply = await server.handle(line: line) { protocolOut.write(reply + [0x0A]) }
    }
    exit(0)    // the client closed stdin
}
dispatchMain()
