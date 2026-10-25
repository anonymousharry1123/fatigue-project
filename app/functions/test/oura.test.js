import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { createOuraService, privacyAllowed } from '../oura.js';

const NOW = Date.parse('2026-10-25T20:00:00Z');
const profile = () => ({ privacyConsent: { policyVersion: 1, ageBand: '18plus', region: 'us',
  acceptedAt: new Date(NOW - 86400000), wellnessAcknowledged: true } });
const tokenResponse = (extra = {}) => ({ token_type: 'bearer', access_token: 'private-access',
  refresh_token: 'private-refresh', expires_in: 3600, ...extra });
const sleep = (extra = {}) => ({ id: 'session-a', day: '2026-10-25', type: 'long_sleep',
  bedtime_start: '2026-10-24T23:00:00-07:00', bedtime_end: '2026-10-25T07:00:00-07:00',
  total_sleep_duration: 27000, time_in_bed: 28800, average_hrv: 45, lowest_heart_rate: 48,
  heart_rate: { interval: 300, timestamp: '2026-10-25T06:00:00Z', items: [null, 51, 50] },
  ...extra });
const json = (body, status = 200) => new Response(JSON.stringify(body), { status });

function fixture() {
  const documents = new Map([['users/u', profile()]]);
  let time = NOW;
  let claims = {};
  const calls = [];
  const responses = [];
  let queue = Promise.resolve();
  const store = {
    get: async path => structuredClone(documents.get(path)),
    transaction(operation) {
      const run = queue.then(async () => {
        const updates = [];
        let writesStarted = false;
        const result = await operation({
          get: async path => { assert.equal(writesStarted, false, 'Firestore reads must precede writes'); return structuredClone(documents.get(path)); },
          set: (path, value) => { writesStarted = true; updates.push(() => documents.set(path, structuredClone(value))); },
          delete: path => { writesStarted = true; updates.push(() => documents.delete(path)); },
        });
        updates.forEach(update => update());
        return result;
      });
      queue = run.catch(() => {});
      return run;
    },
  };
  const service = createOuraService({ store, now: () => time,
    config: () => ({ clientId: 'client', clientSecret: 'private-client-secret', callbackUrl: 'https://us-central1-example.cloudfunctions.net/ouraCallback' }),
    getClaims: async () => { if (claims instanceof Error) throw claims; return claims; },
    fetchImpl: async (url, options) => {
      calls.push({ url: new URL(url), options });
      const response = responses.shift();
      if (typeof response === 'function') return response();
      if (response instanceof Error) throw response;
      assert.ok(response, 'unexpected upstream call');
      return response;
    },
  });
  return { service, store, documents, calls, responses,
    setTime: value => { time = value; }, setClaims: value => { claims = value; },
    connect(extra = {}) { documents.set('ouraConnections/u', { accessToken: 'old-access', refreshToken: 'old-refresh',
      expiresAt: NOW + 3600000, scope: 'daily', ...extra }); },
  };
}

test('start requests only daily with PKCE, stores state hashed and excludes credentials', async () => {
  const f = fixture();
  const result = await f.service.start('u');
  const url = new URL(result.authorizationUrl);
  assert.equal(url.origin, 'https://cloud.ouraring.com');
  assert.equal(url.searchParams.get('scope'), 'daily');
  assert.equal(url.searchParams.get('response_type'), 'code');
  assert.equal(url.searchParams.get('code_challenge_method'), 'S256');
  assert.equal(url.searchParams.get('redirect_uri'), result.redirectUri);
  assert.match(result.state, /^[A-Za-z0-9_-]{43}$/);
  const stateDoc = [...f.documents.entries()].find(([path]) => path.startsWith('ouraOAuthStates/'));
  assert.equal(stateDoc[0], `ouraOAuthStates/${createHash('sha256').update(result.state).digest('base64url')}`);
  assert.equal(url.searchParams.get('code_challenge'), createHash('sha256').update(stateDoc[1].verifier).digest('base64url'));
  assert.equal(JSON.stringify(result).includes('private-client-secret'), false);
  assert.equal(result.callbackUrl, 'tonyo://oura/callback');
});

test('callback exchanges with server secret, redirects without credentials and cannot replay', async () => {
  const f = fixture();
  const { state } = await f.service.start('u');
  f.responses.push(json(tokenResponse()));
  const callback = new URL(await f.service.callback({ state, code: 'one-use-code' }));
  assert.equal(callback.searchParams.get('result'), 'success');
  assert.equal(callback.searchParams.get('state'), state);
  assert.equal(callback.search.includes('private'), false);
  assert.equal(f.calls[0].options.body.get('client_secret'), 'private-client-secret');
  assert.equal(f.calls[0].options.body.get('grant_type'), 'authorization_code');
  assert.ok(f.calls[0].options.body.get('code_verifier'));
  assert.deepEqual(await f.service.status('u'), { connected: true, lastSyncAt: null });
  assert.equal([...f.documents.keys()].some(path => path.startsWith('ouraOAuthStates/')), false);
  await assert.rejects(f.service.callback({ state, code: 'one-use-code' }), { code: 'invalid_request' });
});

test('denial consumes state and returns cancelled without an upstream token request', async () => {
  const f = fixture();
  const { state } = await f.service.start('u');
  assert.equal(new URL(await f.service.callback({ state, error: 'access_denied' })).searchParams.get('result'), 'cancelled');
  assert.equal(f.calls.length, 0);
  assert.equal((await f.service.status('u')).connected, false);
});

test('expired and unknown states cannot bind an account', async () => {
  const f = fixture();
  await assert.rejects(f.service.callback({ state: 'x'.repeat(43), code: 'code' }), { code: 'invalid_request' });
  const { state } = await f.service.start('u');
  f.setTime(NOW + 10 * 60000);
  await assert.rejects(f.service.callback({ state, code: 'code' }), { code: 'invalid_request' });
  assert.equal(f.calls.length, 0);
});

test('new authorization invalidates older state without accumulating state docs', async () => {
  const f = fixture();
  const first = await f.service.start('u');
  await assert.rejects(f.service.start('u'), { code: 'busy' });
  f.setTime(NOW + 6000);
  const second = await f.service.start('u');
  assert.notEqual(second.state, first.state);
  assert.equal([...f.documents.keys()].filter(path => path.startsWith('ouraOAuthStates/')).length, 1);
  await assert.rejects(f.service.callback({ state: first.state, code: 'code' }), { code: 'invalid_request' });
});

test('privacy gate matches age, guardian claims, version, acknowledgement and deletion', async () => {
  assert.equal(privacyAllowed(profile(), {}, NOW), true);
  assert.equal(privacyAllowed(undefined, {}, NOW), false);
  for (const change of [{ privacyDeletion: {} }, { privacyConsent: null }]) {
    assert.equal(privacyAllowed({ ...profile(), ...change }, {}, NOW), false);
  }
  for (const change of [{ policyVersion: 2 }, { acceptedAt: new Date(NOW + 1) }, { wellnessAcknowledged: false }, { extra: true }]) {
    assert.equal(privacyAllowed({ privacyConsent: { ...profile().privacyConsent, ...change } }, {}, NOW), false);
  }
  const minor = { privacyConsent: { ...profile().privacyConsent, ageBand: '16to17' } };
  assert.equal(privacyAllowed(minor, {}, NOW), false);
  assert.equal(privacyAllowed(minor, { guardianConsentVerified: true, guardianConsentPolicyVersion: 1 }, NOW), true);
  const f = fixture();
  f.documents.set('users/u', minor);
  await assert.rejects(f.service.start('u'), { code: 'privacy_required' });
  assert.equal(f.documents.size, 1);
});

test('withdrawal after start stops callback before requesting tokens', async () => {
  const f = fixture();
  const { state } = await f.service.start('u');
  f.documents.set('users/u', { ...profile(), privacyDeletion: {} });
  assert.equal(new URL(await f.service.callback({ state, code: 'code' })).searchParams.get('result'), 'failure');
  assert.equal(f.calls.length, 0);
});

test('disconnect during code exchange does not recreate credentials', async () => {
  const f = fixture();
  const { state } = await f.service.start('u');
  f.responses.push(async () => { await f.service.disconnect('u'); return json(tokenResponse()); }, json({}));
  assert.equal(new URL(await f.service.callback({ state, code: 'code' })).searchParams.get('result'), 'failure');
  assert.equal(f.documents.has('ouraConnections/u'), false);
  assert.equal(f.calls.at(-1).url.pathname, '/oauth/revoke');
});

test('sync paginates, restricts dates and fields, retains five-minute heart-rate series', async () => {
  const f = fixture(); f.connect();
  f.responses.push(json({ data: [sleep({ extraSecret: 'omit' }), sleep({ type: 'sleep' }), sleep({ day: '2026-09-24' })], next_token: 'second' }),
    json({ data: [sleep({ id: 'session-b', day: '2026-10-24' })], next_token: null }));
  const result = await f.service.sync('u');
  assert.equal(result.sleep.length, 2);
  assert.equal(result.startDate, '2026-09-25');
  assert.equal(result.endDate, '2026-10-26');
  assert.equal(result.sleep[0].extraSecret, undefined);
  assert.deepEqual(result.sleep[0].heart_rate.items, [null, 51, 50]);
  assert.equal(f.calls[1].url.searchParams.get('next_token'), 'second');
  assert.equal(JSON.stringify(result).includes('old-access'), false);
  assert.equal((await f.service.status('u')).lastSyncAt, new Date(NOW).toISOString());
  assert.equal(f.documents.get('ouraConnections/u').lockId, undefined);
});

test('UTC boundary includes an already completed Oura night labeled tomorrow locally', async () => {
  const f = fixture(); f.connect();
  f.responses.push(json({ data: [sleep({ day: '2026-10-26',
    bedtime_start: '2026-10-25T22:00:00+14:00', bedtime_end: '2026-10-26T08:00:00+14:00' })] }));
  const result = await f.service.sync('u');
  assert.equal(result.sleep.length, 1);
  assert.equal(result.sleep[0].day, '2026-10-26');
  assert.equal(f.calls[0].url.searchParams.get('end_date'), '2026-10-27');
});

test('expired token rotates once before data fetch and stores rotated refresh token', async () => {
  const f = fixture(); f.connect({ expiresAt: NOW - 1 });
  f.responses.push(json(tokenResponse()), json({ data: [], next_token: null }));
  await f.service.sync('u');
  assert.equal(f.calls[0].options.body.get('refresh_token'), 'old-refresh');
  assert.equal(f.calls[1].options.headers.Authorization, 'Bearer private-access');
  assert.equal(f.documents.get('ouraConnections/u').refreshToken, 'private-refresh');
});

test('invalid single-use refresh requires reconnection without returning stored secrets', async () => {
  const f = fixture(); f.connect({ expiresAt: NOW - 1 });
  f.responses.push(json({ error: 'invalid_grant', secret: 'do-not-echo' }, 400));
  await assert.rejects(f.service.sync('u'), error => error.code === 'reconnect_required' && !error.message.includes('do-not-echo'));
  assert.equal((await f.service.status('u')).connected, false);
  assert.equal(f.documents.get('ouraConnections/u').refreshToken, null);
});

test('revoked daily access requires reconnect and does not advance last sync', async () => {
  const f = fixture(); f.connect();
  f.responses.push(json({ detail: 'denied' }, 403));
  await assert.rejects(f.service.sync('u'), { code: 'reconnect_required' });
  assert.equal((await f.service.status('u')).connected, false);
  assert.equal(f.documents.get('ouraConnections/u').lastSyncAt, undefined);
});

test('repeated pagination token rejects the entire sync rather than returning partial readings', async () => {
  const f = fixture(); f.connect();
  f.responses.push(json({ data: [sleep()], next_token: 'same' }), json({ data: [sleep()], next_token: 'same' }));
  await assert.rejects(f.service.sync('u'), { code: 'incomplete_sync' });
  assert.equal(f.documents.get('ouraConnections/u').lastSyncAt, undefined);
});

test('malformed types and days reject the entire snapshot without advancing the previous sync', async () => {
  for (const changes of [{ type: 'unknown' }, { type: null }, { type: undefined },
    { type: 123 }, { day: undefined }, { day: null }, { day: '2026-2-03' },
    { day: '2026-02-30' }, { day: '2026-13-01' }, { day: '2026-10-25T00:00:00Z' }]) {
    const f = fixture();
    const lastSyncAt = '2026-10-24T20:00:00.000Z';
    f.connect({ lastSyncAt });
    f.responses.push(json({ data: [sleep()], next_token: 'later-page' }),
      json({ data: [sleep(changes)], next_token: null }));
    let returned;
    await assert.rejects(async () => { returned = await f.service.sync('u'); }, { code: 'incomplete_sync' });
    assert.equal(returned, undefined, 'No authoritative snapshot may reach client replacement logic');
    assert.equal(f.documents.get('ouraConnections/u').lastSyncAt, lastSyncAt);
  }
});

test('documented non-main-sleep types may be omitted from a complete valid snapshot', async () => {
  const f = fixture(); f.connect();
  f.responses.push(json({ data: ['sleep', 'late_nap', 'rest', 'deleted'].map(type => sleep({ type })) }));
  assert.deepEqual((await f.service.sync('u')).sleep, []);
});

test('network failure is sanitized and releases the operation lock', async () => {
  const f = fixture(); f.connect();
  f.responses.push(new Error('sensitive request url'));
  await assert.rejects(f.service.sync('u'), error => error.code === 'provider_unavailable' && !error.message.includes('sensitive'));
  assert.equal(f.documents.get('ouraConnections/u').lockId, undefined);
});

test('concurrent sync cannot reuse a rotating refresh token', async () => {
  const f = fixture(); f.connect({ expiresAt: NOW - 1 });
  let resolveToken;
  let started;
  const ready = new Promise(resolve => { started = resolve; });
  f.responses.push(() => { started(); return new Promise(resolve => { resolveToken = resolve; }); }, json({ data: [] }));
  const first = f.service.sync('u');
  await ready;
  await assert.rejects(f.service.sync('u'), { code: 'busy' });
  resolveToken(json(tokenResponse()));
  await first;
  assert.equal(f.calls.filter(call => call.url.pathname === '/oauth/token').length, 1);
});

test('disconnect during sync prevents stale readings from being returned', async () => {
  const f = fixture(); f.connect();
  f.responses.push(async () => { await f.service.disconnect('u'); return json({ data: [sleep()] }); }, json({}));
  await assert.rejects(f.service.sync('u'), { code: 'session_changed' });
  assert.equal(f.documents.has('ouraConnections/u'), false);
});

test('consent withdrawal during sync rejects readings and cleanup removes tokens', async () => {
  const f = fixture(); f.connect();
  f.responses.push(() => { f.documents.set('users/u', { ...profile(), privacyDeletion: {} }); return json({ data: [sleep()] }); }, json({}));
  await assert.rejects(f.service.sync('u'), { code: 'privacy_required' });
  await f.service.cleanupIfRequired('u');
  assert.equal(f.documents.has('ouraConnections/u'), false);
});

test('erasure works without valid consent and despite provider revocation failure', async () => {
  const f = fixture(); f.connect();
  f.documents.delete('users/u');
  f.responses.push(new Error('offline'));
  assert.deepEqual(await f.service.disconnect('u'), { connected: false });
  assert.equal(f.documents.has('ouraConnections/u'), false);
  assert.deepEqual(await f.service.disconnect('u'), { connected: false });
});

test('transient Firebase Auth failure does not erase a valid connection', async () => {
  const f = fixture(); f.connect(); f.setClaims(new Error('temporary backend outage'));
  await assert.rejects(f.service.cleanupIfRequired('u'), { code: 'provider_unavailable' });
  assert.equal(f.documents.get('ouraConnections/u').accessToken, 'old-access');
});
