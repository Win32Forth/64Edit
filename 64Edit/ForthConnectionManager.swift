//
//  ForthConnectionManager.swift
//  64Edit
//
//  Created by Tom's MacBook Air on 9/30/26.
//

import Foundation
import Combine

final class ForthConnectionManager: NSObject, ObservableObject {
    static var socketURL: URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return root.appendingPathComponent("64Forth", isDirectory: true)
            .appendingPathComponent("edit.sock")
    }

    @Published private(set) var isConnected = false
    @Published private(set) var lastError: String?
    @Published private(set) var consoleLines: [String] = []

    private var fd: Int32 = -1
    private var readSource: DispatchSourceRead?
    private let ioQueue = DispatchQueue(label: "com.Win32Forth.SixtyFourForth.edit-client")
    private var incoming = Data()

    func start() {
        guard fd < 0 else { return }

        let path = Self.socketURL.path
        guard FileManager.default.fileExists(atPath: path) else {
            lastError = "64Forth is not listening (\(path))"
            isConnected = false
            return
        }

        let cfd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard cfd >= 0 else {
            lastError = "socket() failed"
            return
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        path.withCString { cstr in
            withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
                let raw = UnsafeMutableRawPointer(ptr)
                _ = strncpy(raw.assumingMemoryBound(to: CChar.self), cstr, 104)
            }
        }

        let ok = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(cfd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        if ok != 0 {
            Darwin.close(cfd)
            lastError = "connect failed — start 64Forth first"
            isConnected = false
            return
        }

        fd = cfd
        isConnected = true
        lastError = nil

        let src = DispatchSource.makeReadSource(fileDescriptor: cfd, queue: ioQueue)
        src.setEventHandler { [weak self] in
            self?.readAvailable()
        }
        src.setCancelHandler {
            Darwin.close(cfd)
        }
        src.resume()
        readSource = src
    }

    func stop() {
        readSource?.cancel()
        readSource = nil
        fd = -1
        isConnected = false
    }

    func send(_ request: EditorRequest) {
        if fd < 0 {
            start()
        }
        guard fd >= 0 else { return }

        do {
            var data = try IPCCodec.encodeRequest(request)
            data.append(0x0A)
            let n = data.withUnsafeBytes { raw in
                Darwin.write(self.fd, raw.baseAddress, data.count)
            }
            if n < 0 {
                DispatchQueue.main.async {
                    self.lastError = "write failed"
                    self.isConnected = false
                }
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func readAvailable() {
        var buf = [UInt8](repeating: 0, count: 16_384)
        let n = Darwin.read(fd, &buf, buf.count)
        if n <= 0 {
            DispatchQueue.main.async {
                self.isConnected = false
                self.lastError = "64Forth connection closed"
            }
            readSource?.cancel()
            readSource = nil
            fd = -1
            return
        }
        incoming.append(contentsOf: buf.prefix(Int(n)))
        while let range = incoming.firstIndex(of: 10) {
            let line = incoming.subdata(in: incoming.startIndex..<range)
            incoming.removeSubrange(incoming.startIndex...range)
            guard !line.isEmpty else { continue }
            handleIncoming(line)
        }
    }

    private func handleIncoming(_ data: Data) {
        do {
            let response = try IPCCodec.decodeResponse(data)
            DispatchQueue.main.async {
                self.apply(response)
            }
        } catch {
            DispatchQueue.main.async {
                self.lastError = error.localizedDescription
                self.appendConsole("Bad response: \(error.localizedDescription)")
            }
        }
    }

    private func apply(_ response: ForthResponse) {
        switch response {
        case .consoleOutput(let text):
            appendConsole(text)
        case .breakpointHit(let line, let stackTrace):
            appendConsole("BREAK line \(line)")
            stackTrace.forEach { appendConsole("  \($0)") }
        case .variableChanged(let name, let value):
            appendConsole("\(name) = \(value)")
        case .executionFinished(let exitCode):
            appendConsole("Finished (\(exitCode))")
        case .error(let message):
            lastError = message
            appendConsole("Error: \(message)")
        }
    }

    private func appendConsole(_ line: String) {
        let pieces = line.split(whereSeparator: \.isNewline)
        if pieces.isEmpty {
            if !line.isEmpty { consoleLines.append(line) }
            return
        }
        for p in pieces {
            consoleLines.append(String(p))
        }
    }
}
