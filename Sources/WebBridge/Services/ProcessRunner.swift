import Foundation

struct ProcessResult: Sendable {
    let stdout: String
    let stderr: String
    let status: Int32
    var ok: Bool { status == 0 }
}

enum ProcessError: Error, Sendable {
    case launchFailed(String)
    case timedOut
    case nonZeroExit(Int32, String)
}

/// Central, and only, place processes are spawned. One-shot commands resolve a value;
/// long-running commands stream stdout lines and terminate cleanly on task cancellation.
enum ProcessRunner {

    /// Runs a command to completion and returns its captured output.
    static func run(_ executable: String,
                    _ arguments: [String],
                    timeout: Duration = .seconds(15)) async throws -> ProcessResult {
        let handle = LockedBox<Process?>(nil)

        return try await withThrowingTaskGroup(of: ProcessResult.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ProcessResult, Error>) in
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: executable)
                    process.arguments = arguments
                    let outPipe = Pipe()
                    let errPipe = Pipe()
                    process.standardOutput = outPipe
                    process.standardError = errPipe
                    handle.withLock { $0 = process }

                    do {
                        try process.run()
                    } catch {
                        continuation.resume(throwing: ProcessError.launchFailed(error.localizedDescription))
                        return
                    }

                    let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                    let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()

                    continuation.resume(returning: ProcessResult(
                        stdout: String(decoding: outData, as: UTF8.self),
                        stderr: String(decoding: errData, as: UTF8.self),
                        status: process.terminationStatus))
                }
            }

            group.addTask {
                try await Task.sleep(for: timeout)
                handle.withLock { proc in
                    if let proc, proc.isRunning { proc.terminate() }
                }
                throw ProcessError.timedOut
            }

            defer { group.cancelAll() }
            guard let result = try await group.next() else { throw ProcessError.timedOut }
            return result
        }
    }

    /// Convenience returning trimmed stdout, throwing on non-zero exit.
    static func output(_ executable: String,
                       _ arguments: [String],
                       timeout: Duration = .seconds(15)) async throws -> String {
        let result = try await run(executable, arguments, timeout: timeout)
        guard result.ok else { throw ProcessError.nonZeroExit(result.status, result.stderr) }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Streams stdout line by line for a long-running process. The child is terminated
    /// when the consuming task is cancelled or the stream is torn down.
    ///
    /// Set `mergeStderr` to also surface the child's stderr on the same stream. Needed for
    /// tools like `ios_webkit_debug_proxy`, which report every diagnostic (device attach
    /// failures, protocol errors) on stderr rather than stdout.
    static func lines(_ executable: String, _ arguments: [String], mergeStderr: Bool = false) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let processBox = LockedBox<Process?>(nil)

            continuation.onTermination = { _ in
                processBox.withLock { proc in
                    if let proc, proc.isRunning { proc.terminate() }
                }
            }

            let thread = Thread {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = mergeStderr ? pipe : Pipe()
                processBox.withLock { $0 = process }

                do {
                    try process.run()
                } catch {
                    continuation.finish(throwing: ProcessError.launchFailed(error.localizedDescription))
                    return
                }

                let readHandle = pipe.fileHandleForReading
                var buffer = Data()
                while true {
                    let chunk = readHandle.availableData
                    if chunk.isEmpty { break }
                    buffer.append(chunk)
                    while let newline = buffer.firstIndex(of: 0x0A) {
                        let lineData = buffer[buffer.startIndex..<newline]
                        buffer.removeSubrange(buffer.startIndex...newline)
                        continuation.yield(String(decoding: lineData, as: UTF8.self))
                    }
                }
                process.waitUntilExit()
                continuation.finish()
            }
            thread.stackSize = 512 * 1024
            thread.start()
        }
    }
}
