import Foundation

/// Public authorization metadata only. Oura credentials and the PKCE verifier
/// remain on the authenticated server; neither is accepted by this bridge.
struct OuraAuthorizationRequest {
  static let appCallback = "tonyo://oura/callback"

  let url: URL
  let state: String

  init?(authorizationURL: String, redirectURI: String) {
    guard authorizationURL.count <= 8192,
      let redirect = URLComponents(string: redirectURI),
      redirect.scheme == "https", redirect.host?.isEmpty == false,
      redirect.user == nil, redirect.password == nil,
      redirect.port == nil || redirect.port == 443,
      redirect.query == nil, redirect.fragment == nil,
      let components = URLComponents(string: authorizationURL),
      components.scheme == "https",
      components.user == nil, components.password == nil,
      components.port == nil, components.fragment == nil,
      (components.host == "cloud.ouraring.com" && components.path == "/oauth/authorize")
        || (components.host == "developer.ouraring.com" && components.path == "/authorize"),
      let fields = Self.uniqueFields(components.queryItems),
      Set(fields.keys) == Set([
        "response_type", "client_id", "redirect_uri", "scope", "state",
        "code_challenge", "code_challenge_method",
      ]),
      fields["response_type"] == "code", fields["scope"] == "daily",
      fields["redirect_uri"] == redirectURI,
      fields["code_challenge_method"] == "S256",
      let clientID = fields["client_id"], !clientID.isEmpty, clientID.count <= 256,
      let challenge = fields["code_challenge"],
      challenge.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil,
      let state = fields["state"],
      state.range(of: "^[A-Za-z0-9_-]{32,128}$", options: .regularExpression) != nil,
      let url = components.url
    else { return nil }
    self.url = url
    self.state = state
  }

  func result(from callback: URL) -> [String: String]? {
    guard let components = URLComponents(url: callback, resolvingAgainstBaseURL: false),
      components.scheme == "tonyo", components.host == "oura",
      components.path == "/callback", components.user == nil,
      components.password == nil, components.port == nil,
      components.fragment == nil,
      let fields = Self.uniqueFields(components.queryItems),
      Set(fields.keys) == Set(["state", "result"]),
      fields["state"] == state,
      let result = fields["result"], ["success", "failure", "cancelled"].contains(result)
    else { return nil }
    return ["state": state, "result": result]
  }

  private static func uniqueFields(_ items: [URLQueryItem]?) -> [String: String]? {
    guard let items else { return nil }
    var fields: [String: String] = [:]
    for item in items {
      guard fields[item.name] == nil, let value = item.value else { return nil }
      fields[item.name] = value
    }
    return fields
  }
}
