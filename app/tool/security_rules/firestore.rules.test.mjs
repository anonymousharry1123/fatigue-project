import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { after, before, beforeEach, test } from 'node:test';
import {
  assertFails, assertSucceeds, initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  Timestamp, collection, collectionGroup, deleteDoc, deleteField, doc,
  documentId, getDoc, getDocs, query, serverTimestamp, setDoc, setLogLevel,
  updateDoc, where, writeBatch,
} from 'firebase/firestore';

// Never fall back to a real Firebase project. A running loopback emulator is
// mandatory; all fixtures are generated test records in this demo-only project.
const host = process.env.FIRESTORE_EMULATOR_HOST ?? '';
assert.match(host, /^(127\.0\.0\.1|localhost):\d+$/,
  'Set FIRESTORE_EMULATOR_HOST to a local running emulator. Live hosts are refused.');
const [hostname, portText] = host.split(':');
const projectId = 'demo-tonyo-privacy';
const childCollections = ['signals', 'checkIns', 'scoreSnapshots',
  'forecastPoints', 'recommendations', 'outcomes', 'riskAlerts'];
const ordinaryCollections = childCollections.filter(value => value !== 'outcomes');
const features = ['sleepDeviation', 'movement', 'hydration', 'studyScreenLoad',
  'caffeine', 'mood', 'stress', 'recoveryDeviation'];
let environment;
setLogLevel('silent');

const privacy = (changes = {}) => ({
  policyVersion: 1, ageBand: '18plus', region: 'us',
  acceptedAt: Timestamp.fromMillis(Date.now() - 60_000),
  wellnessAcknowledged: true, ...changes,
});
const flags = (enabled = false) => ({
  wellnessOnlyAcknowledged: true,
  outcomeCollection: enabled, trainingRecordUse: enabled,
});
const profile = (changes = {}) => ({
  privacyConsent: privacy(), consentFlags: flags(),
  outcomeConsentUpdatedAt: Timestamp.fromMillis(Date.now() - 60_000),
  profile: { displayName: 'Test account' }, schemaVersion: 14, ...changes,
});
const newProfile = (changes = {}) => profile({
  privacyConsent: privacy({ acceptedAt: serverTimestamp() }),
  outcomeConsentUpdatedAt: serverTimestamp(), ...changes,
});
const model = () => ({
  modelVersion: 1, schemaVersion: 1,
  window: { start: '2026-07-02T00:00:00Z', end: '2026-08-01T00:00:00Z',
    timezone: 'UTC' },
  trainedAt: '2026-08-01T01:00:00Z', labelCount: 20,
  deterministicMae: 10, holdoutMae: 8,
  featureCoverage: Object.fromEntries(features.map(value => [value, 1])),
});
const guardianClaims = {
  guardianConsentVerified: true, guardianConsentPolicyVersion: 1,
};
const signedIn = (uid = 'owner', claims = {}) => environment
  .authenticatedContext(uid, { auth_time: Math.floor(Date.now() / 1000), ...claims })
  .firestore();
const root = db => doc(db, 'users/owner');
const child = (db, name = 'signals', id = 'row') => doc(db, `users/owner/${name}/${id}`);
const marker = () => ({ privacyDeletion: { version: 1, requestedAt: serverTimestamp() } });
const consentChange = enabled => ({ consentFlags: flags(enabled),
  outcomeConsentUpdatedAt: serverTimestamp() });
const seed = async (userData = profile(), includeChildren = false) => {
  await environment.withSecurityRulesDisabled(async context => {
    const db = context.firestore();
    await setDoc(root(db), userData);
    if (includeChildren) {
      await Promise.all(childCollections.map(name => setDoc(child(db, name), { value: 1 })));
    }
  });
};

before(async () => {
  environment = await initializeTestEnvironment({
    projectId,
    firestore: { host: hostname, port: Number(portText),
      rules: await readFile(new URL('../../firestore.rules', import.meta.url), 'utf8') },
  });
});
beforeEach(async () => { await environment.clearFirestore(); });
after(async () => { await environment?.cleanup(); });

test('unauthenticated requests cannot inspect or mutate any real-user path', async () => {
  await seed(profile(), true);
  const db = environment.unauthenticatedContext().firestore();
  await assertFails(getDoc(root(db)));
  for (const name of childCollections) {
    await assertFails(getDoc(child(db, name)));
    await assertFails(setDoc(child(db, name), { value: 2 }));
    await assertFails(deleteDoc(child(db, name)));
  }
});

test('another account cannot get, list, create, update or delete private records', async () => {
  await seed(profile({ consentFlags: flags(true) }), true);
  const db = signedIn('other', guardianClaims);
  await assertFails(getDoc(root(db)));
  await assertFails(updateDoc(root(db), { profile: {} }));
  await assertFails(deleteDoc(root(db)));
  for (const name of childCollections) {
    await assertFails(getDoc(child(db, name)));
    await assertFails(getDocs(collection(db, `users/owner/${name}`)));
    await assertFails(setDoc(child(db, name, 'new'), { value: 1 }));
    await assertFails(updateDoc(child(db, name), { value: 2 }));
    await assertFails(deleteDoc(child(db, name)));
  }
});

test('user-directory and collection-group queries remain denied even with owner filters', async () => {
  await seed(profile(), true);
  const db = signedIn();
  await assertSucceeds(getDoc(root(db)));
  await assertFails(getDocs(collection(db, 'users')));
  await assertFails(getDocs(query(collection(db, 'users'), where(documentId(), '==', 'owner'))));
  await assertFails(getDocs(collectionGroup(db, 'signals')));
});

test('legacy and revoked accounts can still inspect, export and delete all seven collections', async () => {
  await seed({ consentFlags: flags(false) }, true);
  const db = signedIn('owner', { auth_time: 1 });
  await assertSucceeds(getDoc(root(db)));
  for (const name of childCollections) {
    await assertSucceeds(getDoc(child(db, name)));
    await assertSucceeds(getDocs(collection(db, `users/owner/${name}`)));
    await assertSucceeds(deleteDoc(child(db, name)));
  }
});

test('fresh explicit adult consent creates a minimal receipt before profile migration', async () => {
  const db = signedIn();
  await assertSucceeds(setDoc(root(db), {
    privacyConsent: privacy({ acceptedAt: serverTimestamp() }),
    ...consentChange(false), schemaVersion: 14, updatedAt: serverTimestamp(),
  }));
  await assertSucceeds(updateDoc(root(db), { profile: { displayName: 'Owner' } }));
  for (const name of ordinaryCollections) {
    await assertSucceeds(setDoc(child(db, name), { value: 1 }));
    await assertSucceeds(updateDoc(child(db, name), { value: 2 }));
  }
});

test('missing parent, legacy flags, missing acknowledgement and malformed receipts fail closed', async () => {
  const db = signedIn();
  await assertFails(setDoc(child(db), { value: 1 }));
  for (const userData of [
    { consentFlags: flags(true) },
    profile({ privacyConsent: privacy({ wellnessAcknowledged: false }) }),
    profile({ privacyConsent: privacy({ policyVersion: 0 }) }),
    profile({ privacyConsent: privacy({ ageBand: 'unknown' }) }),
    profile({ privacyConsent: privacy({ region: 'invalid' }) }),
    profile({ privacyConsent: privacy({ acceptedAt: '2026-01-01' }) }),
  ]) {
    await seed(userData);
    for (const name of childCollections) {
      await assertFails(setDoc(child(db, name), { value: 1 }));
    }
  }
});

test('fresh consent rejects backdated, future, missing and client-forged verification fields', async () => {
  const db = signedIn();
  await assertFails(setDoc(root(db), profile()));
  await assertFails(setDoc(root(db), newProfile({ privacyConsent: privacy({
    acceptedAt: Timestamp.fromMillis(Date.now() + 86_400_000),
  }) })));
  await assertFails(setDoc(root(db), { consentFlags: flags(true) }));
  await assertFails(setDoc(root(db), newProfile({ guardianConsentVerified: true })));
  await assertFails(setDoc(root(db), newProfile({ privacyConsent: privacy({
    acceptedAt: serverTimestamp(), guardianConsentVerified: true,
  }) })));
});

test('all under-18 bands require both current server-issued guardian claims', async () => {
  for (const ageBand of ['under13', '13to15', '16to17']) {
    await environment.clearFirestore();
    const data = newProfile({ privacyConsent: privacy({ ageBand, acceptedAt: serverTimestamp() }) });
    await assertFails(setDoc(root(signedIn()), data));
    await assertFails(setDoc(root(signedIn('owner', { guardianConsentVerified: true })), data));
    await assertFails(setDoc(root(signedIn('owner', {
      guardianConsentVerified: true, guardianConsentPolicyVersion: 0,
    })), data));
    const verified = signedIn('owner', guardianClaims);
    await assertSucceeds(setDoc(root(verified), data));
    await assertSucceeds(setDoc(child(verified), { value: 1 }));
    await assertFails(setDoc(child(signedIn()), { value: 2 }));
  }
});

test('client cannot change or remove acknowledged age, region or policy', async () => {
  await seed(profile({ privacyConsent: privacy({ ageBand: '16to17' }) }));
  const db = signedIn('owner', guardianClaims);
  await assertFails(updateDoc(root(db), { privacyConsent: privacy({ acceptedAt: serverTimestamp() }) }));
  await assertFails(updateDoc(root(db), { privacyConsent: privacy({
    ageBand: '16to17', region: 'other', acceptedAt: serverTimestamp(),
  }) }));
  await assertFails(updateDoc(root(db), { privacyConsent: deleteField() }));
  await assertFails(updateDoc(root(db), { 'privacyConsent.policyVersion': 2 }));
  await assertSucceeds(updateDoc(root(db), { privacyConsent: privacy({
    ageBand: '16to17', acceptedAt: serverTimestamp(),
  }) }));
});

test('a legacy receipt can be explicitly reviewed but never silently backfilled', async () => {
  await seed({ consentFlags: flags(false), profile: {} });
  const db = signedIn();
  await assertFails(updateDoc(root(db), { privacyConsent: privacy(), consentFlags: flags() }));
  await assertSucceeds(updateDoc(root(db), {
    privacyConsent: privacy({ acceptedAt: serverTimestamp() }), ...consentChange(false),
  }));
});

test('unknown protected server metadata survives normal sync but cannot be client-changed', async () => {
  await seed(profile({ serverReview: { verified: true } }));
  const db = signedIn();
  await assertSucceeds(updateDoc(root(db), { profile: { displayName: 'Changed' } }));
  await assertFails(updateDoc(root(db), { serverReview: deleteField() }));
  await assertFails(updateDoc(root(db), { serverReview: { verified: false } }));
  await assertFails(updateDoc(root(db), { guardianConsentVerified: true }));
  await assertFails(updateDoc(root(db), { syntheticLabAdmin: true }));
});

test('outcome collection requires both flags even for a privacy-approved owner', async () => {
  const db = signedIn();
  for (const consentFlags of [flags(), { ...flags(), outcomeCollection: true },
    { ...flags(), trainingRecordUse: true }]) {
    await seed(profile({ consentFlags }));
    await assertFails(setDoc(child(db, 'outcomes'), { value: 4 }));
  }
  await assertSucceeds(updateDoc(root(db), consentChange(true)));
  await assertSucceeds(setDoc(child(db, 'outcomes'), { value: 4 }));
  await assertSucceeds(updateDoc(child(db, 'outcomes'), { value: 5 }));
});

test('optional consent timestamps cannot be omitted, backdated, deleted or fabricated by ordinary sync', async () => {
  const db = signedIn();
  const missingTimestamp = newProfile();
  delete missingTimestamp.outcomeConsentUpdatedAt;
  await assertFails(setDoc(root(db), missingTimestamp));
  await seed(profile());
  await assertFails(updateDoc(root(db), { consentFlags: flags(true) }));
  await assertFails(updateDoc(root(db), { consentFlags: flags(true),
    outcomeConsentUpdatedAt: Timestamp.fromMillis(Date.now() - 60_000) }));
  await assertFails(updateDoc(root(db), { outcomeConsentUpdatedAt: deleteField() }));
  await assertSucceeds(setDoc(root(db), { consentFlags: {
    outcomeCollection: true, trainingRecordUse: true,
  }, outcomeConsentUpdatedAt: serverTimestamp(), updatedAt: serverTimestamp() }, { merge: true }));
  const beforeSync = (await getDoc(root(db))).data();
  await assertSucceeds(setDoc(root(db), { profile: { displayName: 'Changed' },
    consentFlags: { outcomeCollection: true, trainingRecordUse: true },
    updatedAt: serverTimestamp() }, { merge: true }));
  const afterSync = (await getDoc(root(db))).data();
  assert.ok(afterSync.outcomeConsentUpdatedAt.isEqual(beforeSync.outcomeConsentUpdatedAt));
  assert.ok(afterSync.privacyConsent.acceptedAt.isEqual(beforeSync.privacyConsent.acceptedAt));
  assert.equal(afterSync.consentFlags.wellnessOnlyAcknowledged, true);
});

test('accepted owner batches reuse the same parent guard within rule access limits', async () => {
  await seed(profile());
  const db = signedIn();
  const batch = writeBatch(db);
  for (let index = 0; index < 100; index++) {
    batch.set(child(db, 'signals', `row-${index}`), { value: index });
  }
  await assertSucceeds(batch.commit());
  assert.equal((await getDocs(collection(db, 'users/owner/signals'))).size, 100);
});

test('a token without guardian approval disables youth writes but permits safety revocation', async () => {
  await seed(profile({ privacyConsent: privacy({ ageBand: '16to17' }),
    consentFlags: flags(true), personalizedEnergyModel: model() }), true);
  const db = signedIn();
  await assertFails(setDoc(child(db), { value: 2 }));
  await assertFails(setDoc(child(db, 'outcomes'), { value: 2 }));
  await assertFails(updateDoc(root(db), { profile: { displayName: 'Changed' } }));
  await assertSucceeds(updateDoc(root(db), { ...consentChange(false),
    personalizedEnergyModel: deleteField(), updatedAt: serverTimestamp() }));
  await assertSucceeds(getDoc(child(db, 'outcomes')));
  await assertSucceeds(deleteDoc(child(db, 'outcomes')));
});

test('metadata promotion remains compact, privacy-gated and dual-consent gated', async () => {
  await seed(profile());
  const db = signedIn();
  await assertFails(updateDoc(root(db), { personalizedEnergyModel: model() }));
  await assertSucceeds(updateDoc(root(db), consentChange(true)));
  await assertSucceeds(updateDoc(root(db), { personalizedEnergyModel: model() }));
  await assertFails(updateDoc(root(db), { personalizedEnergyModel: { ...model(), weights: [1] } }));
  await assertFails(updateDoc(root(db), { personalizedEnergyModel: { ...model(), holdoutMae: 9.6 } }));
  await assertFails(updateDoc(root(db), { personalizedEnergyModel: { ...model(), labelCount: 1 } }));
  await assertSucceeds(updateDoc(root(db), consentChange(false)));
  await assertSucceeds(updateDoc(root(db), { personalizedEnergyModel: deleteField() }));
});

test('unknown collections and deeper nesting are denied even to an approved owner', async () => {
  await seed(profile({ consentFlags: flags(true) }));
  const db = signedIn();
  for (const path of ['users/owner/models/weights', 'users/owner/trainingExamples/day',
    'users/owner/guardians/proof', 'users/owner/signals/row/private/nested']) {
    const target = doc(db, path);
    await assertFails(setDoc(target, { value: 1 }));
    await assertFails(getDoc(target));
    await assertFails(deleteDoc(target));
  }
});

test('deletion marker requires recent auth and only the marker may change', async () => {
  await seed(profile());
  const old = signedIn('owner', { auth_time: Math.floor(Date.now() / 1000) - 301 });
  await assertFails(setDoc(root(old), marker(), { merge: true }));
  const future = signedIn('owner', { auth_time: Math.floor(Date.now() / 1000) + 60 });
  await assertFails(setDoc(root(future), marker(), { merge: true }));
  const db = signedIn();
  await assertFails(setDoc(root(db), { ...marker(), profile: {} }, { merge: true }));
  await assertFails(setDoc(root(db), { privacyDeletion: { version: 1,
    requestedAt: Timestamp.fromMillis(Date.now() - 1000) } }, { merge: true }));
  await assertFails(setDoc(root(db), { privacyDeletion: { version: 1,
    requestedAt: serverTimestamp(), complete: true } }, { merge: true }));
  await assertSucceeds(setDoc(root(db), marker(), { merge: true }));
  await assertSucceeds(setDoc(root(db), marker(), { merge: true }));
});

test('pending deletion blocks every new write while keeping export and deletion available', async () => {
  await seed(profile({ consentFlags: flags(true) }), true);
  const db = signedIn();
  await assertSucceeds(setDoc(root(db), marker(), { merge: true }));
  await assertFails(updateDoc(root(db), { profile: { displayName: 'Stale sync' } }));
  await assertFails(updateDoc(root(db), consentChange(false)));
  await assertFails(updateDoc(root(db), { privacyDeletion: deleteField() }));
  await assertFails(updateDoc(root(db), { privacyConsent: privacy({ acceptedAt: serverTimestamp() }) }));
  await assertSucceeds(getDoc(root(db)));
  for (const name of childCollections) {
    await assertFails(setDoc(child(db, name, 'new'), { value: 2 }));
    await assertFails(updateDoc(child(db, name), { value: 2 }));
    await assertSucceeds(getDocs(collection(db, `users/owner/${name}`)));
    await assertSucceeds(deleteDoc(child(db, name)));
  }
  await assertSucceeds(deleteDoc(root(db)));
});

test('root deletion needs both intent marker and recent auth; missing-root retry stays possible', async () => {
  await seed(profile());
  const db = signedIn();
  await assertFails(deleteDoc(root(db)));
  await assertSucceeds(setDoc(root(db), marker(), { merge: true }));
  const old = signedIn('owner', { auth_time: 1 });
  await assertFails(deleteDoc(root(old)));
  await assertSucceeds(deleteDoc(root(db)));
  await assertSucceeds(setDoc(root(db), marker(), { merge: true }));
  await assertSucceeds(deleteDoc(root(db)));
  // An old app's full cached-profile upload cannot recreate a deleted account.
  await assertFails(setDoc(root(db), profile()));
});

test('atomic deletion intent cannot be combined with a child write', async () => {
  await seed(profile({ consentFlags: flags(true) }));
  const db = signedIn();
  for (const name of childCollections) {
    const batch = writeBatch(db);
    batch.set(root(db), marker(), { merge: true });
    batch.set(child(db, name), { value: 2 });
    await assertFails(batch.commit());
  }
});

test('atomic outcome consent revocation cannot smuggle an outcome write', async () => {
  await seed(profile({ consentFlags: flags(true) }));
  const db = signedIn();
  const batch = writeBatch(db);
  batch.update(root(db), consentChange(false));
  batch.set(child(db, 'outcomes'), { value: 2 });
  await assertFails(batch.commit());
});

test('ordinary and guardian accounts cannot use synthetic paths as a sharing channel', async () => {
  const paths = ['syntheticUsers/student', 'syntheticUsers/student/signals/row',
    'syntheticUsers/student/nested/row/private/data', 'syntheticCohort/summary'];
  await environment.withSecurityRulesDisabled(async context => {
    for (const path of paths) await setDoc(doc(context.firestore(), path), { fake: true });
  });
  for (const db of [signedIn(), signedIn('guardian', guardianClaims),
    environment.unauthenticatedContext().firestore()]) {
    for (const path of paths) {
      await assertFails(getDoc(doc(db, path)));
      await assertFails(setDoc(doc(db, path), { fake: false }));
      await assertFails(deleteDoc(doc(db, path)));
    }
    await assertFails(getDocs(collection(db, 'syntheticUsers')));
  }
});

test('server-authorized lab operators can use synthetic paths but not other users', async () => {
  await seed(profile(), true);
  const db = signedIn('operator', { syntheticLabAdmin: true });
  for (const path of ['syntheticUsers/student', 'syntheticUsers/student/signals/row',
    'syntheticCohort/summary']) {
    await assertSucceeds(setDoc(doc(db, path), { fake: true }));
    await assertSucceeds(getDoc(doc(db, path)));
    await assertSucceeds(deleteDoc(doc(db, path)));
  }
  await assertSucceeds(getDocs(collection(db, 'syntheticUsers')));
  await assertFails(getDoc(root(db)));
  await assertFails(getDoc(child(db)));
  await assertFails(setDoc(child(db), { value: 2 }));
});
