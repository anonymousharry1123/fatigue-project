# Oura connection service

This optional backend reads Oura nighttime HRV and resting-heart information alongside Tonyo's existing Apple Health import. It requests only Oura's `daily` scope. Oura does not list HRV or resting heart rate among its Apple Health exports, so Apple Health alone cannot supply these Oura metrics. This service uses the Oura V2 sleep API directly.

## Setup before live use

1. Create an OAuth application in [Oura's developer portal](https://cloud.ouraring.com/oauth/applications). Register `https://us-central1-YOUR_PROJECT_ID.cloudfunctions.net/ouraCallback` as its exact redirect URI. Oura's default developer app user limit and review requirements apply before wider release; check the current portal requirements.
2. From this directory, run `npm ci`. Node 22 is the deployed runtime. Run `npm test`; these tests use invented responses and make no external requests.
3. From `app/`, use the Firebase CLI to set `OURA_CLIENT_ID` and `OURA_CLIENT_SECRET` with `firebase functions:secrets:set OURA_CLIENT_ID` and `firebase functions:secrets:set OURA_CLIENT_SECRET`. Supply values only at the CLI's secure prompt; never put them in Dart, a committed file, or a command argument.
4. Copy `functions/.env.example` to `functions/.env.YOUR_PROJECT_ID` and replace the callback URL. Firebase Functions requires a billing-enabled project. Deployment is a separate operator action: `firebase deploy --only functions:oura,firestore:rules`. No deployment is performed by the code changes.
5. Configure the mobile build with its public integration endpoint, `https://us-central1-YOUR_PROJECT_ID.cloudfunctions.net/ouraIntegration`. The separate callback must be on the same trusted Firebase function host and use `/ouraCallback`. For Flutter, pass `--dart-define=OURA_API_BASE_URL=https://us-central1-YOUR_PROJECT_ID.cloudfunctions.net/ouraIntegration`. This public URL is the only Oura build value; never pass the client secret through a Dart define.
6. Enable Firestore TTL for field `expiresAt` on collection group `ouraOAuthStates`, so abandoned one-use authorization records expire. The service rejects state after ten minutes even before TTL cleanup. Deploy the two cleanup functions along with both HTTP endpoints.
7. Validate on an iPhone with a real consenting Oura test account: consent/cancel, first sync, repeated sync, disconnect, reauthorization, token refresh, revocation in Oura, and simultaneous Apple Health import. Server tests do not establish live OAuth/provider behavior or App Store readiness.

## Wire contract

`POST /ouraIntegration` uses `Authorization: Bearer <Firebase ID token>` and JSON containing exactly `{"action":"start|status|sync|disconnect"}`. Firebase checks token revocation; the server derives the UID and does not accept a client-supplied UID. `start`, `status` and `sync` also re-read the existing account privacy acknowledgement and verified guardian claim when applicable. Disconnect and erasure remain available after consent withdrawal.

- `start`: `{authorizationUrl,state,redirectUri,callbackUrl}`. The native authentication session opens the Oura HTTPS authorization URL. `redirectUri` is the server's configured HTTPS callback. `callbackUrl` is fixed to `tonyo://oura/callback`. The authorization request uses a random state, S256 PKCE and `daily` only.
- Public `GET /ouraCallback`: consumes the hashed one-use state, exchanges the authorization code with the server-held secret and redirects to `tonyo://oura/callback?state=…&result=success|failure|cancelled`. No Oura access token, refresh token, Firebase token or account identifier is placed in this redirect. Native code must verify state and the fixed callback; the client then calls `status`.
- `status`: `{connected,lastSyncAt}`. A stored connection is not a guarantee that Oura has new data or that a permission was not revoked moments ago.
- `sync`: `{connected:true,syncedAt,startDate,endDate,sleep:[…]}`. Date bounds are inclusive, covering a 30-day lookback plus one local-date boundary on either side (UTC today minus 30 through UTC today plus one). These boundary dates retain already completed sleep for users ahead of UTC without guessing their timezone. All Oura pages must complete before anything is returned. Each retained `long_sleep` row carries only `id`, `day`, `type`, `bedtime_start`, `bedtime_end`, `total_sleep_duration`, `time_in_bed`, `average_hrv`, `lowest_heart_rate`, and `heart_rate:{interval,timestamp,items}`. The app validates the measurements and chooses the primary sleep session. The five-minute series is retained because Oura's API minimum can differ from the minimum shown in the Oura app. Missing values remain missing.
- `disconnect`: `{connected:false}` after deleting credentials/pending authorization and attempting provider revocation. A provider outage does not prevent local server credential deletion. Previously imported reading deletion is handled by the app's ordinary data-sync/deletion path.

Errors contain only `{error:{code,message}}`; no provider body or error object is returned. Important codes: `unauthenticated`, `not_configured`, `privacy_required`, `not_connected`, `reconnect_required`, `busy`, `provider_unavailable`, `incomplete_sync`, `session_changed`.

## Storage and lifecycle

`ouraConnections/{uid}` holds tokens and operation leases; `ouraOAuthStates/{sha256(state)}` holds the ten-minute PKCE handshake. Firestore rules deny all client reads/writes to both collections. They are never placed inside the app's exportable `users/{uid}` data tree. Firebase/Google Cloud encryption at rest protects stored documents; access is restricted to the function's service account and project administrators. Never log these records or upstream request URLs. Oura's documented revoke endpoint includes its token in a URL query, which this code does not log.

Refresh tokens are single-use. A transactional four-minute lease serializes refresh/sync and releases after failure. Disconnect deletes the connection so a pending exchange/refresh/sync cannot recreate it. If a rotating token is consumed but its response is lost, reconnection may be required. Uncertain pagination never yields a partial replacement snapshot. Calls have fixed HTTPS hosts, disabled redirects, timeouts, page/record/response-size bounds and fixed error messages.

`ouraPrivacyCleanup` reacts to privacy/deletion changes and user-document deletion, re-reading current state to handle out-of-order events. `ouraAuthCleanup` handles direct Firebase Auth deletion. These remove server credentials; normal application privacy deletion erases already imported observations. Revocation is best effort when Oura is unavailable; users can also remove Tonyo in their Oura account's connected applications. No scheduled provider polling, webhooks or automatic ML training are added by this backend.

## Official references

- [Oura OAuth, PKCE, scopes, refresh and revocation](https://cloud.ouraring.com/docs/authentication)
- [Oura V2 API](https://cloud.ouraring.com/v2/docs) and [current OpenAPI schema](https://cloud.ouraring.com/v2/static/json/openapi-1.42.json)
- [Oura Apple Health export categories](https://support.ouraring.com/hc/en-us/articles/360025438734-Apple-Health-Integration)
- [Firebase Firestore function events](https://firebase.google.com/docs/functions/firestore-events)
