import Foundation
import VolumeCore

private struct Command: Decodable {
    let action: String
    let volume: Int?
}

private struct Response: Encodable {
    let ok: Bool
    let volume: Int?
    let error: String?
}

nonisolated(unsafe) private let controller = VolumeController()
private let decoder = JSONDecoder()
private let encoder = JSONEncoder()

private func writeResponse(_ response: Response) {
    guard let data = try? encoder.encode(response) else {
        return
    }

    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data([0x0A]))
}

private func currentVolumePercent() -> Int {
    Int((controller.currentVolume() * 100).rounded())
}

while let line = readLine() {
    guard let data = line.data(using: .utf8) else {
        writeResponse(Response(ok: false, volume: nil, error: "Invalid UTF-8 input"))
        continue
    }

    do {
        let command = try decoder.decode(Command.self, from: data)

        switch command.action {
        case "get":
            writeResponse(Response(ok: true, volume: currentVolumePercent(), error: nil))
        case "set":
            let clamped = min(max(command.volume ?? 0, 0), 100)
            controller.setVolume(Float32(clamped) / 100)
            writeResponse(Response(ok: true, volume: clamped, error: nil))
        default:
            writeResponse(Response(ok: false, volume: nil, error: "Unknown action"))
        }
    } catch {
        writeResponse(Response(ok: false, volume: nil, error: error.localizedDescription))
    }
}
