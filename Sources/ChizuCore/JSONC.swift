import Foundation

enum JSONC {
    static func jsonData(from data: Data) throws -> Data {
        var bytes = Array(data)
        var index = 0
        var inString = false
        var escaped = false

        while index < bytes.count {
            let byte = bytes[index]
            if inString {
                if escaped {
                    escaped = false
                } else if byte == 0x5C {
                    escaped = true
                } else if byte == 0x22 {
                    inString = false
                }
                index += 1
                continue
            }
            if byte == 0x22 {
                inString = true
                index += 1
                continue
            }
            guard byte == 0x2F, index + 1 < bytes.count else {
                index += 1
                continue
            }
            let next = bytes[index + 1]
            if next == 0x2F {
                while index < bytes.count, bytes[index] != 0x0A, bytes[index] != 0x0D {
                    bytes[index] = 0x20
                    index += 1
                }
            } else if next == 0x2A {
                let start = index
                index += 2
                while index + 1 < bytes.count, !(bytes[index] == 0x2A && bytes[index + 1] == 0x2F) {
                    index += 1
                }
                guard index + 1 < bytes.count else {
                    throw ChizuError.invalidConfiguration("unterminated block comment")
                }
                index += 2
                for position in start..<index where bytes[position] != 0x0A && bytes[position] != 0x0D {
                    bytes[position] = 0x20
                }
            } else {
                index += 1
            }
        }

        index = 0
        inString = false
        escaped = false
        while index < bytes.count {
            let byte = bytes[index]
            if inString {
                if escaped {
                    escaped = false
                } else if byte == 0x5C {
                    escaped = true
                } else if byte == 0x22 {
                    inString = false
                }
            } else if byte == 0x22 {
                inString = true
            } else if byte == 0x2C {
                var next = index + 1
                while next < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[next]) {
                    next += 1
                }
                if next < bytes.count, bytes[next] == 0x5D || bytes[next] == 0x7D {
                    bytes[index] = 0x20
                }
            }
            index += 1
        }
        return Data(bytes)
    }
}
