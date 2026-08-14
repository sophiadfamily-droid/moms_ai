import Flutter
import MapKit
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private static let travelAuthorizationKey =
    "zelia.travelCalculationAuthorized.v1"
  private var routeTravelTimeChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    guard let registrar = engineBridge.pluginRegistry.registrar(
      forPlugin: "ZeliaRouteTravelTime"
    ) else {
      return
    }
    let channel = FlutterMethodChannel(
      name: "com.zelia.app/route_travel_time",
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handleRouteTravelTimeCall(call, result: result)
    }
    routeTravelTimeChannel = channel
  }

  private func handleRouteTravelTimeCall(
    _ call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    switch call.method {
    case "isTravelCalculationAuthorized":
      result(isTravelCalculationAuthorized)
    case "setTravelCalculationAuthorized":
      guard
        let arguments = call.arguments as? [String: Any],
        let authorized = arguments["authorized"] as? Bool
      else {
        result(
          FlutterError(
            code: "invalid_arguments",
            message: "L’autorisation demandée est invalide.",
            details: nil
          )
        )
        return
      }
      UserDefaults.standard.set(
        authorized,
        forKey: Self.travelAuthorizationKey
      )
      result(nil)
    case "estimateTravelTime":
      guard isTravelCalculationAuthorized else {
        result(
          FlutterError(
            code: "travel_calculation_not_authorized",
            message: "Le calcul des trajets n’est pas autorisé sur cet appareil.",
            details: nil
          )
        )
        return
      }
      estimateTravelTime(call.arguments, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private var isTravelCalculationAuthorized: Bool {
    UserDefaults.standard.bool(forKey: Self.travelAuthorizationKey)
  }

  private func estimateTravelTime(
    _ rawArguments: Any?,
    result: @escaping FlutterResult
  ) {
    guard
      let arguments = rawArguments as? [String: Any],
      let origin = boundedPlace(arguments["origin"]),
      let destination = boundedPlace(arguments["destination"]),
      let departureMilliseconds = arguments["departureAtMilliseconds"] as? NSNumber,
      let mode = arguments["mode"] as? String
    else {
      result(
        FlutterError(
          code: "invalid_arguments",
          message: "Les informations du trajet sont incomplètes.",
          details: nil
        )
      )
      return
    }

    resolveMapItem(for: origin) { [weak self] originItem, originError in
      guard let self else { return }
      guard let originItem else {
        result(self.routeError("origin_not_found", originError))
        return
      }
      self.resolveMapItem(for: destination) { destinationItem, destinationError in
        guard let destinationItem else {
          result(self.routeError("destination_not_found", destinationError))
          return
        }
        let request = MKDirections.Request()
        request.source = originItem
        request.destination = destinationItem
        request.departureDate = Date(
          timeIntervalSince1970: departureMilliseconds.doubleValue / 1_000
        )
        request.transportType = self.transportType(for: mode)

        MKDirections(request: request).calculateETA { response, error in
          guard let response else {
            result(self.routeError("route_unavailable", error))
            return
          }
          let minutes = Int(ceil(response.expectedTravelTime / 60))
          guard minutes >= 0, minutes <= 24 * 60 else {
            result(self.routeError("invalid_travel_time", nil))
            return
          }
          result(["minutes": minutes])
        }
      }
    }
  }

  private func resolveMapItem(
    for place: String,
    completion: @escaping (MKMapItem?, Error?) -> Void
  ) {
    let request = MKLocalSearch.Request()
    request.naturalLanguageQuery = place
    request.resultTypes = [.address, .pointOfInterest]
    MKLocalSearch(request: request).start { response, error in
      completion(response?.mapItems.first, error)
    }
  }

  private func boundedPlace(_ rawValue: Any?) -> String? {
    guard let value = rawValue as? String else { return nil }
    let cleaned = value
      .components(separatedBy: .whitespacesAndNewlines)
      .filter { !$0.isEmpty }
      .joined(separator: " ")
    guard !cleaned.isEmpty, cleaned.count <= 240 else { return nil }
    return cleaned
  }

  private func transportType(for mode: String) -> MKDirectionsTransportType {
    switch mode {
    case "walking":
      return .walking
    case "publicTransport":
      return .transit
    default:
      return .automobile
    }
  }

  private func routeError(_ code: String, _ error: Error?) -> FlutterError {
    FlutterError(
      code: code,
      message: "Le trajet n’a pas pu être calculé.",
      details: error.map { String(describing: type(of: $0)) }
    )
  }
}
