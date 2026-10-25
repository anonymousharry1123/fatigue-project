import { createHash, randomBytes } from 'node:crypto';

const MOBILE_CALLBACK = 'tonyo://oura/callback';
const API = 'https://api.ouraring.com';
const hash = value => createHash('sha256').update(value).digest('base64url');
const nonce = () => randomBytes(32).toString('base64url');
const connectionPath = uid => `ouraConnections/${uid}`;
const statePath = value => `ouraOAuthStates/${hash(value)}`;
const statePattern = /^[A-Za-z0-9_-]{43}$/;
const sleepTypes = new Set(['long_sleep', 'sleep', 'late_nap', 'rest', 'deleted']);

function validDay(value) {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const parsed = new Date(`${value}T00:00:00.000Z`);
  return Number.isFinite(parsed.getTime()) && parsed.toISOString().slice(0, 10) === value;
}

export class OuraError extends Error {
  constructor(code, status = 400) {
    const messages = {
      not_configured: 'Oura integration is not configured yet.',
      privacy_required: 'Review privacy and consent before connecting Oura.',
      not_connected: 'Connect your Oura account first.',
      reconnect_required: 'Reconnect Oura to continue syncing.',
      busy: 'An Oura operation is already running. Try again shortly.',
      provider_unavailable: 'Oura could not be reached. Try again later.',
      incomplete_sync: 'Oura returned an incomplete sync. No readings were imported.',
      invalid_request: 'The Oura request is invalid.',
      session_changed: 'The Oura connection changed. Try again.',
    };
    super(messages[code] ?? 'Oura could not complete this request.');
    this.code = code;
    this.status = status;
  }
}

function millis(value) {
  if (value?.toMillis) return value.toMillis();
  if (value instanceof Date) return value.getTime();
  return NaN;
}

export function privacyAllowed(profile, claims, now) {
  const consent = profile?.privacyConsent;
  return Boolean(profile && !Object.hasOwn(profile, 'privacyDeletion') &&
    consent && Object.keys(consent).length === 5 &&
    consent.policyVersion === 1 && consent.wellnessAcknowledged === true &&
    ['under13', '13to15', '16to17', '18plus'].includes(consent.ageBand) &&
    ['us', 'other', 'unknown'].includes(consent.region) &&
    Number.isFinite(millis(consent.acceptedAt)) && millis(consent.acceptedAt) <= now &&
    (consent.ageBand === '18plus' ||
      (claims?.guardianConsentVerified === true && claims?.guardianConsentPolicyVersion === 1)));
}

/** Dependencies keep credentials out of clients and allow deterministic tests.
 * store: get(path), transaction(callback), with tx.get/set/delete(path).
 * Transactions perform all reads before writes, as required by Firestore.
 */
export function createOuraService({ store, getClaims, config, fetchImpl = fetch, now = Date.now }) {
  function settings() {
    const value = config();
    let callback;
    try { callback = new URL(value.callbackUrl); } catch { /* fail closed */ }
    if (!value.clientId || !value.clientSecret || !callback ||
        callback.protocol !== 'https:' || callback.username || callback.password ||
        callback.search || callback.hash) throw new OuraError('not_configured', 503);
    return value;
  }

  async function allowed(uid, tx = store) {
    let claims;
    try { claims = await getClaims(uid); } catch (error) {
      if (error instanceof OuraError) throw error;
      if (error?.code === 'auth/user-not-found') throw new OuraError('privacy_required', 403);
      throw new OuraError('provider_unavailable', 503);
    }
    const profile = await tx.get(`users/${uid}`);
    if (!privacyAllowed(profile, claims, now())) throw new OuraError('privacy_required', 403);
  }

  async function request(url, options = {}) {
    try {
      const response = await fetchImpl(url, { ...options, redirect: 'error', signal: AbortSignal.timeout(15000) });
      const reader = response.body?.getReader();
      let text = '';
      if (reader) {
        const chunks = [];
        let size = 0;
        while (true) {
          const { done, value } = await reader.read();
          if (done) break;
          size += value.length;
          if (size > 2 * 1024 * 1024) { await reader.cancel(); throw new OuraError('incomplete_sync', 502); }
          chunks.push(value);
        }
        text = Buffer.concat(chunks).toString('utf8');
      } else text = await response.text();
      let body;
      try { body = text ? JSON.parse(text) : {}; } catch { throw new OuraError('provider_unavailable', 502); }
      return { status: response.status, ok: response.ok, body };
    } catch (error) {
      if (error instanceof OuraError) throw error;
      throw new OuraError('provider_unavailable', 502);
    }
  }

  async function token(parameters) {
    const { clientId, clientSecret } = settings();
    const response = await request(`${API}/oauth/token`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({ ...parameters, client_id: clientId, client_secret: clientSecret }),
    });
    if (!response.ok) {
      if (response.body.error === 'invalid_grant' || response.status === 401) throw new OuraError('reconnect_required', 401);
      throw new OuraError('provider_unavailable', 502);
    }
    const value = response.body;
    if (typeof value.access_token !== 'string' || !value.access_token || value.access_token.length > 8192 ||
        typeof value.refresh_token !== 'string' || !value.refresh_token || value.refresh_token.length > 8192 ||
        typeof value.token_type !== 'string' || value.token_type.toLowerCase() !== 'bearer' ||
        !Number.isFinite(value.expires_in) || value.expires_in <= 0 ||
        (value.scope !== undefined && (typeof value.scope !== 'string' || !value.scope.split(' ').includes('daily')))) {
      throw new OuraError('reconnect_required', 401);
    }
    return { accessToken: value.access_token, refreshToken: value.refresh_token,
      expiresAt: now() + value.expires_in * 1000, scope: 'daily' };
  }

  async function revoke(accessToken) {
    if (!accessToken) return;
    // Oura documents this query parameter. Never log this URL or a fetch error.
    const url = new URL(`${API}/oauth/revoke`);
    url.searchParams.set('access_token', accessToken);
    try { await fetchImpl(url, { method: 'GET', redirect: 'error', signal: AbortSignal.timeout(10000) }); } catch { /* Local credential deletion still completes. */ }
  }

  async function withLock(uid, operation) {
    const path = connectionPath(uid);
    const lockId = nonce();
    const acquired = await store.transaction(async tx => {
      const current = await tx.get(path);
      if (!current) throw new OuraError('not_connected', 409);
      if (current.lockUntil > now()) throw new OuraError('busy', 409);
      const result = { ...current, lockId, lockUntil: now() + 240000 };
      tx.set(path, result);
      return result;
    });
    async function save(update) {
      return store.transaction(async tx => {
        const current = await tx.get(path);
        await allowed(uid, tx);
        if (!current || current.lockId !== lockId) throw new OuraError('session_changed', 409);
        const result = { ...current, ...update };
        tx.set(path, result);
        return result;
      });
    }
    try { return await operation(acquired, save); }
    finally {
      await store.transaction(async tx => {
        const current = await tx.get(path);
        if (current?.lockId === lockId) {
          const { lockId: _, lockUntil: __, ...rest } = current;
          tx.set(path, rest);
        }
      });
    }
  }

  async function start(uid) {
    const { clientId, callbackUrl } = settings();
    await allowed(uid);
    const state = nonce();
    const verifier = nonce();
    await store.transaction(async tx => {
      const current = await tx.get(connectionPath(uid));
      await allowed(uid, tx);
      if (current?.lockUntil > now() || current?.authStartedAt > now() - 5000) throw new OuraError('busy', 409);
      if (current?.pendingStatePath) tx.delete(current.pendingStatePath);
      tx.set(statePath(state), { uid, verifier, expiresAt: new Date(now() + 10 * 60000) });
      tx.set(connectionPath(uid), { ...current, pendingStatePath: statePath(state), authStartedAt: now() });
    });
    const url = new URL('https://cloud.ouraring.com/oauth/authorize');
    url.search = new URLSearchParams({ response_type: 'code', client_id: clientId, redirect_uri: callbackUrl,
      scope: 'daily', state, code_challenge: hash(verifier), code_challenge_method: 'S256' }).toString();
    return { authorizationUrl: url.toString(), state, redirectUri: callbackUrl, callbackUrl: MOBILE_CALLBACK };
  }

  async function callback({ state, code, error }) {
    if (typeof state !== 'string' || !statePattern.test(state)) throw new OuraError('invalid_request');
    const path = statePath(state);
    const pending = await store.transaction(async tx => {
      const value = await tx.get(path);
      if (!value || millis(value.expiresAt) <= now()) throw new OuraError('invalid_request');
      const connection = await tx.get(connectionPath(value.uid));
      if (connection?.pendingStatePath !== path) throw new OuraError('invalid_request');
      tx.delete(path); // One use, including denial and failed exchanges.
      return value;
    });
    let result = 'failure';
    if (error === 'access_denied') result = 'cancelled';
    else if (!error && typeof code === 'string' && code.length > 0 && code.length <= 4096) {
      try {
        await allowed(pending.uid);
        await withLock(pending.uid, async (connection, save) => {
          if (connection.pendingStatePath !== path) throw new OuraError('session_changed', 409);
          const tokens = await token({ grant_type: 'authorization_code', code,
            redirect_uri: settings().callbackUrl, code_verifier: pending.verifier });
          try {
            await save({ ...tokens, connectedAt: new Date(now()).toISOString(),
              lastSyncAt: null, pendingStatePath: null, reconnectRequired: false });
          } catch (error) { await revoke(tokens.accessToken); throw error; }
        });
        result = 'success';
      } catch { /* Fixed callback result cannot disclose credentials or internals. */ }
    }
    const url = new URL(MOBILE_CALLBACK);
    url.search = new URLSearchParams({ state, result }).toString();
    return url.toString();
  }

  async function status(uid) {
    settings();
    await allowed(uid);
    const value = await store.get(connectionPath(uid));
    return { connected: Boolean(value?.accessToken && value?.refreshToken && !value?.reconnectRequired),
      lastSyncAt: value?.lastSyncAt ?? null };
  }

  async function sync(uid) {
    settings();
    await allowed(uid);
    return withLock(uid, async (connection, save) => {
      if (!connection.accessToken || !connection.refreshToken || connection.reconnectRequired) throw new OuraError('not_connected', 409);
      let credentials = connection;
      if (credentials.expiresAt <= now() + 60000) {
        try {
          const refreshed = await token({ grant_type: 'refresh_token', refresh_token: credentials.refreshToken });
          try { credentials = await save(refreshed); }
          catch (error) { await revoke(refreshed.accessToken); throw error; }
        } catch (error) {
          if (error.code === 'reconnect_required') await save({ accessToken: null, refreshToken: null, reconnectRequired: true });
          throw error;
        }
      }
      const today = new Date(now());
      today.setUTCHours(0, 0, 0, 0);
      // Oura days are local labels. Include the boundary dates on both sides
      // of a 30-day window so UTC+/- users do not lose completed sleep today.
      const startDate = new Date(today.getTime() - 30 * 86400000).toISOString().slice(0, 10);
      const endDate = new Date(today.getTime() + 86400000).toISOString().slice(0, 10);
      const requestEnd = new Date(today.getTime() + 2 * 86400000).toISOString().slice(0, 10);
      const sleep = [];
      const seenTokens = new Set();
      let next;
      for (let page = 0; page < 10; page++) {
        const url = new URL(`${API}/v2/usercollection/sleep`);
        url.search = new URLSearchParams({ start_date: startDate, end_date: requestEnd, ...(next ? { next_token: next } : {}) }).toString();
        const response = await request(url, { headers: { Authorization: `Bearer ${credentials.accessToken}` } });
        if ([401, 403].includes(response.status)) {
          await save({ reconnectRequired: true });
          throw new OuraError('reconnect_required', 401);
        }
        if (!response.ok) throw new OuraError('provider_unavailable', 502);
        if (!Array.isArray(response.body.data) || response.body.data.length > 1000) throw new OuraError('incomplete_sync', 502);
        for (const row of response.body.data) {
          // Validate before filtering: an unknown type or corrupt day cannot
          // masquerade as an authoritative empty window and erase imports.
          if (!row || typeof row !== 'object' || Array.isArray(row) ||
              !validDay(row.day) || !sleepTypes.has(row.type)) throw new OuraError('incomplete_sync', 502);
          if (row.type !== 'long_sleep' || row.day < startDate || row.day > endDate) continue;
          const result = {};
          for (const field of ['id', 'day', 'type', 'bedtime_start', 'bedtime_end', 'total_sleep_duration',
            'time_in_bed', 'average_hrv', 'lowest_heart_rate']) result[field] = row[field] ?? null;
          if (row.heart_rate != null) {
            if (!Array.isArray(row.heart_rate.items) || row.heart_rate.items.length > 1000) throw new OuraError('incomplete_sync', 502);
            result.heart_rate = { interval: row.heart_rate.interval ?? null,
              timestamp: row.heart_rate.timestamp ?? null, items: row.heart_rate.items };
          } else result.heart_rate = null;
          sleep.push(result);
          if (sleep.length > 1000) throw new OuraError('incomplete_sync', 502);
        }
        next = response.body.next_token;
        if (next == null) break;
        if (typeof next !== 'string' || !next || next.length > 4096 || seenTokens.has(next) || page === 9) throw new OuraError('incomplete_sync', 502);
        seenTokens.add(next);
      }
      const syncedAt = new Date(now()).toISOString();
      await save({ lastSyncAt: syncedAt }); // Recheck consent and disconnect races before releasing readings.
      return { connected: true, syncedAt, startDate, endDate, sleep };
    });
  }

  async function disconnect(uid) {
    // Available after consent withdrawal; erasure must not require consent.
    const previous = await store.transaction(async tx => {
      const current = await tx.get(connectionPath(uid));
      if (current?.pendingStatePath) tx.delete(current.pendingStatePath);
      tx.delete(connectionPath(uid));
      return current;
    });
    await revoke(previous?.accessToken);
    return { connected: false };
  }

  async function cleanupIfRequired(uid) {
    try { await allowed(uid); }
    catch (error) {
      if (error.code !== 'privacy_required') throw error; // Retry transient Auth/Firestore failures.
      await disconnect(uid);
    }
  }

  return { start, callback, status, sync, disconnect, cleanupIfRequired };
}
