// Run from app/:
// swiftc -module-cache-path /private/tmp/tonyo-oura-swift-cache \
//   ios/Runner/OuraAuthorizationURL.swift tool/check_oura_authorization.swift \
//   -o /private/tmp/tonyo-oura-auth-check && /private/tmp/tonyo-oura-auth-check
import Foundation

@main
struct OuraAuthorizationChecks {
  static func main() {
    let state = String(repeating: "s", count: 43)
    let redirect = "https://example.cloudfunctions.net/ouraCallback"
    let fields = [
      URLQueryItem(name: "client_id", value: "test-client"),
      URLQueryItem(name: "response_type", value: "code"),
      URLQueryItem(name: "redirect_uri", value: redirect),
      URLQueryItem(name: "scope", value: "daily"),
      URLQueryItem(name: "state", value: state),
      URLQueryItem(name: "code_challenge", value: String(repeating: "a", count: 43)),
      URLQueryItem(name: "code_challenge_method", value: "S256"),
    ]
    func url(_ changes: [String: String] = [:], extra: [URLQueryItem] = []) -> String {
      var components = URLComponents(string: "https://cloud.ouraring.com/oauth/authorize")!
      components.queryItems = fields.map { URLQueryItem(name: $0.name, value: changes[$0.name] ?? $0.value) } + extra
      return components.url!.absoluteString
    }
    func request(_ raw: String) -> OuraAuthorizationRequest? {
      OuraAuthorizationRequest(authorizationURL: raw, redirectURI: redirect)
    }
    guard let valid = request(url()) else { fatalError("Valid server authorization rejected") }
    assert(request(url().replacingOccurrences(of: "cloud.ouraring.com/oauth/authorize", with: "developer.ouraring.com/authorize")) != nil)
    for bad in [
      url(["response_type": "token"]),
      url(["scope": "daily personal"]),
      url(["code_challenge_method": "plain"]),
      url(["code_challenge": "short"]),
      url(["state": "short"]),
      url(["redirect_uri": "https://attacker.example/callback"]),
      url(extra: [URLQueryItem(name: "state", value: state)]),
      url(extra: [URLQueryItem(name: "access_token", value: "not-allowed")]),
      url().replacingOccurrences(of: "https://", with: "http://"),
      url().replacingOccurrences(of: "cloud.ouraring.com", with: "cloud.ouraring.com.attacker.example"),
      url().replacingOccurrences(of: "https://", with: "https://user@"),
      url() + "#fragment",
    ] { assert(request(bad) == nil, "Unsafe authorization accepted") }
    assert(OuraAuthorizationRequest(authorizationURL: url(), redirectURI: "http://example.cloudfunctions.net/ouraCallback") == nil)
    for result in ["success", "failure", "cancelled"] {
      let callback = URL(string: "tonyo://oura/callback?state=\(state)&result=\(result)")!
      assert(valid.result(from: callback) == ["state": state, "result": result])
    }
    for bad in [
      "tonyo://oura/callback?state=wrong&result=success",
      "tonyo://oura/callback?state=\(state)&result=unknown",
      "tonyo://oura/callback?state=\(state)&result=success&state=\(state)",
      "tonyo://oura/callback?state=\(state)&result=success&access_token=secret",
      "tonyo://oura/callback?state=\(state)&result=success#fragment",
      "tonyo://oura/other?state=\(state)&result=success",
      "tonyo://user@oura/callback?state=\(state)&result=success",
      "tonyo://oura:443/callback?state=\(state)&result=success",
      "tonyo://other/callback?state=\(state)&result=success",
      "https://oura/callback?state=\(state)&result=success",
    ] { assert(valid.result(from: URL(string: bad)!) == nil, "Unsafe callback accepted") }
    print("Oura native authorization checks passed (28 cases).")
  }
}
