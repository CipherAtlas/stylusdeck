import Foundation
import VolumeCore

final class EqBridgeClient {
    private let processor = EqProcessor()

    func status(
        for bank: SurfaceBank,
        route: SurfaceRoute,
        parameter: SurfaceParameter,
        secondaryParameter: SurfaceParameter? = nil
    ) -> EqBridgeResponse {
        processor.status(for: bank, route: route, parameter: parameter, secondaryParameter: secondaryParameter)
    }

    func setValue(
        _ value: Int,
        for bank: SurfaceBank,
        route: SurfaceRoute,
        parameter: SurfaceParameter,
        secondaryParameter: SurfaceParameter? = nil
    ) -> EqBridgeResponse {
        processor.setValue(value, for: bank, route: route, parameter: parameter, secondaryParameter: secondaryParameter)
    }

    func setGesture(
        primaryValue: Int,
        secondaryValue: Int,
        for bank: SurfaceBank,
        route: SurfaceRoute,
        secondaryParameter: SurfaceParameter
    ) -> EqBridgeResponse {
        processor.setGesture(
            primaryValue: primaryValue,
            secondaryValue: secondaryValue,
            for: bank,
            route: route,
            secondaryParameter: secondaryParameter
        )
    }

    func stop() {
        processor.restoreRoute()
    }
}
