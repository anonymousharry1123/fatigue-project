import { initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';
import { defineSecret, defineString } from 'firebase-functions/params';
import { onRequest } from 'firebase-functions/v2/https';
import { onDocumentWritten } from 'firebase-functions/v2/firestore';
import * as functionsV1 from 'firebase-functions/v1';
import { createOuraService, OuraError } from './oura.js';

initializeApp();
const db = getFirestore();
const clientId = defineSecret('OURA_CLIENT_ID');
const clientSecret = defineSecret('OURA_CLIENT_SECRET');
const callbackUrl = defineString('OURA_CALLBACK_URL', { default: '' });
const store = {
  get: async path => (await db.doc(path).get()).data(),
  transaction: operation => db.runTransaction(transaction => operation({
    get: async path => (await transaction.get(db.doc(path))).data(),
    set: (path, value) => transaction.set(db.doc(path), value),
    delete: path => transaction.delete(db.doc(path)),
  })),
};
const service = createOuraService({
  store,
  getClaims: async uid => {
    const user = await getAuth().getUser(uid);
    if (user.disabled) throw new OuraError('privacy_required', 403);
    return user.customClaims ?? {};
  },
  config: () => ({ clientId: clientId.value(), clientSecret: clientSecret.value(), callbackUrl: callbackUrl.value() }),
});
const options = { region: 'us-central1', timeoutSeconds: 180, memory: '256MiB',
  maxInstances: 10, secrets: [clientId, clientSecret], cors: false };

function privateResponse(res) {
  res.set('Cache-Control', 'no-store');
  res.set('Referrer-Policy', 'no-referrer');
  res.set('X-Content-Type-Options', 'nosniff');
}

export const ouraIntegration = onRequest(options, async (req, res) => {
  privateResponse(res);
  if (req.method !== 'POST') return res.status(405).json({ error: { code: 'invalid_request', message: 'Use POST.' } });
  const authorization = req.get('Authorization') ?? '';
  const match = /^Bearer ([A-Za-z0-9._-]+)$/.exec(authorization);
  let user;
  try {
    if (!match || match[1].length > 8192) throw new Error('invalid');
    user = await getAuth().verifyIdToken(match[1], true);
  } catch {
    return res.status(401).json({ error: { code: 'unauthenticated', message: 'Sign in to your Tonyo account again.' } });
  }
  const action = req.body?.action;
  if (!req.is('application/json') || !req.body || typeof req.body !== 'object' ||
      Array.isArray(req.body) || Object.keys(req.body).length !== 1 ||
      !['start', 'status', 'sync', 'disconnect'].includes(action)) {
    return res.status(400).json({ error: { code: 'invalid_request', message: 'Choose a valid Oura action.' } });
  }
  try { return res.json(await service[action](user.uid)); }
  catch (error) {
    // Never pass SDK/provider error objects (which may contain request URLs,
    // tokens or personal records) to the client or application logs.
    const safe = error instanceof OuraError ? error : new OuraError('provider_unavailable', 503);
    return res.status(safe.status).json({ error: { code: safe.code, message: safe.message } });
  }
});

export const ouraCallback = onRequest(options, async (req, res) => {
  privateResponse(res);
  if (req.method !== 'GET') return res.status(405).send('Use GET.');
  try {
    const destination = await service.callback({ state: req.query.state, code: req.query.code, error: req.query.error });
    return res.redirect(302, destination);
  } catch { return res.status(400).send('This Oura connection request expired. Return to Tonyo and try again.'); }
});

// Re-read current account state because Firestore event delivery can be out of
// order. Cleanup runs only for a consent/deletion change, not every sync write.
export const ouraPrivacyCleanup = onDocumentWritten({ document: 'users/{uid}',
  region: 'us-central1', retry: true, maxInstances: 10 }, async event => {
  const before = event.data?.before.data();
  const after = event.data?.after.data();
  if (after && before && !Object.hasOwn(after, 'privacyDeletion') &&
      JSON.stringify(before.privacyConsent) === JSON.stringify(after.privacyConsent)) return;
  await service.cleanupIfRequired(event.params.uid);
});

// Also erase credentials if an operator deletes Firebase Auth directly.
export const ouraAuthCleanup = functionsV1.region('us-central1').auth.user().onDelete(
  user => service.disconnect(user.uid),
);
