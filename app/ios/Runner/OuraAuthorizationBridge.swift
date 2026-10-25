import AuthenticationServices
import Flutter
import UIKit

/// Presents Oura consent. The backend owns token exchange, refresh and storage;
/// the app receives only a state-bound completion and rechecks server status.
final class OuraAuthorizationBridge: NSObject, ASWebAuthenticationPresentationContextProviding {
  private var session: ASWebAuthenticationSession?
  private var pendingResult: FlutterResult?
  private var requestID: UUID?
  private var anchor: UIWindow?

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "authenticate":
      authenticate(call.arguments, result: result)
    case "cancel":
      cancel()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func authenticate(_ arguments: Any?, result: @escaping FlutterResult) {
    guard session == nil else {
      result(FlutterError(code: "oura_busy", message: "An Oura connection is already in progress.", details: nil))
      return
    }
    guard let arguments = arguments as? [String: Any],
      let authorizationURL = arguments["authorizationUrl"] as? String,
      let redirectURI = arguments["redirectUri"] as? String,
      let request = OuraAuthorizationRequest(authorizationURL: authorizationURL, redirectURI: redirectURI)
    else {
      result(FlutterError(code: "oura_invalid_authorization", message: "Oura connection settings are invalid.", details: nil))
      return
    }
    guard let window = UIApplication.shared.connectedScenes
      .compactMap({ $0 as? UIWindowScene })
      .filter({ $0.activationState == .foregroundActive })
      .flatMap({ $0.windows })
      .first(where: { $0.isKeyWindow })
    else {
      result(FlutterError(code: "oura_unavailable", message: "Open Tonyo to connect Oura.", details: nil))
      return
    }
    let identifier = UUID()
    requestID = identifier
    pendingResult = result
    anchor = window
    let session = ASWebAuthenticationSession(url: request.url, callbackURLScheme: "tonyo") { [weak self] callback, error in
      DispatchQueue.main.async {
        guard let self, self.requestID == identifier else { return }
        if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
          self.finish(FlutterError(code: "oura_cancelled", message: "Oura connection was cancelled.", details: nil))
        } else if error != nil {
          self.finish(FlutterError(code: "oura_authorization_failed", message: "Oura could not finish connecting. Try again.", details: nil))
        } else if let callback, let response = request.result(from: callback) {
          self.finish(response)
        } else {
          self.finish(FlutterError(code: "oura_invalid_callback", message: "Oura returned an invalid connection response.", details: nil))
        }
      }
    }
    session.presentationContextProvider = self
    session.prefersEphemeralWebBrowserSession = true
    self.session = session
    if !session.start() {
      finish(FlutterError(code: "oura_unavailable", message: "Oura sign-in could not open. Try again.", details: nil))
    }
  }

  private func cancel() {
    let active = session
    finish(FlutterError(code: "oura_cancelled", message: "Oura connection was cancelled.", details: nil))
    active?.cancel()
  }

  private func finish(_ value: Any?) {
    let completion = pendingResult
    pendingResult = nil
    requestID = nil
    session = nil
    completion?(value)
  }

  func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
    // Set before a session can start. Retain the last anchor through cancellation
    // so an already queued AuthenticationServices presentation callback is safe.
    guard let anchor else { preconditionFailure("Oura sign-in requires a presentation window.") }
    return anchor
  }
}
