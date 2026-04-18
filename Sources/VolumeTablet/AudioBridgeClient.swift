import Foundation

final class EqBridgeClient {
    private let processor = EqProcessor()

    func status(for route: SurfaceRoute) -> EqBridgeResponse {
        switch route {
        case .volume:
            return processor.getOutputVolume()
        case .low, .mid, .high:
            return processor.status(for: route.bandKey)
        }
    }

    func setValue(_ value: Int, for route: SurfaceRoute) -> EqBridgeResponse {
        switch route {
        case .volume:
            return processor.setOutputVolume(value)
        case .low, .mid, .high:
            return processor.setBand(route.bandKey ?? "", value: value)
        }
    }

    func stop() {
        processor.restoreRoute()
    }
}
