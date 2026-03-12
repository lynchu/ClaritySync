//
//  CSVLogger.swift
//  ClaritySync
//
//  Created by 張譯心 on 2026/3/6.
//

import Foundation

final class CSVLogger {
    private var fh: FileHandle?
    private(set) var url: URL?

    func start(prefix: String, header: String) throws {
        let filename = "\(prefix)_\(Self.timestampString()).csv"
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let u = dir.appendingPathComponent(filename)

        FileManager.default.createFile(atPath: u.path, contents: nil)
        let h = try FileHandle(forWritingTo: u)

        self.fh = h
        self.url = u

        try writeLine(header)
    }

    func writeLine(_ line: String) throws {
        guard let fh else { return }
        guard let data = (line + "\n").data(using: .utf8) else { return }
        try fh.write(contentsOf: data)
    }

    func stop() {
        try? fh?.close()
        fh = nil
    }

    private static func timestampString() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd_HHmmss"
        return f.string(from: Date())
    }
}
