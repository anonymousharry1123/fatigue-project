import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { after, before, beforeEach, test } from 'node:test';
import {
  assertFails, assertSucceeds, initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  Timestamp, collection, collectionGroup, deleteDoc, deleteField, doc,
  documentId, getDoc, getDocFromServer, getDocs, getDocsFromServer, query,
  runTransaction, serverTimestamp, setDoc, setLogLevel, updateDoc, where, writeBatch,
} from 'firebase/firestore';

// Never fall back to a real Firebase project. A running loopback emulator is
// mandatory; all fixtures are generated test records in this demo-only project.
const host = process.env.FIRESTORE_EMULATOR_HOST ?? '';
assert.match(host, /^(127\.0\.0\.1|localhost):\d+$/,
  'Set FIRESTORE_EMULATOR_HOST to a local running emulator. Live hosts are refused.');
const [hostname, portText] = host.split(':');
const projectId = 'demo-tonyo-privacy';
const childCollections = ['signals', 'checkIns', 'scoreSnapshots',
  'forecastPoints', 'forecastDays', 'heartRateDays', 'inputChanges',
  'recommendations', 'outcomes', 'riskAlerts'];
const ordinaryCollections = childCollections.filter(value =>
  !['outcomes', 'forecastDays', 'heartRateDays', 'inputChanges'].includes(value));
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
// Synthetic documents use the current cloud_schema.dart wire format. The Dart
// serializer tests separately verify that app objects produce these fields;
// these cases exercise actual emulator merge, transaction and server-read
// behavior under the repository rules, not a simulated repository.
const phase1Signal = (changes = {}) => ({
  type: 'exercise', value: 0, unit: 'hr',
  timestamp: Timestamp.fromDate(new Date('2026-10-03T12:00:00Z')),
  source: 'manual', quality: 1, note: null, groupId: 'activity-test',
  syncedAt: null,
  recordedAt: Timestamp.fromDate(new Date('2026-10-03T12:01:00Z')),
  schemaVersion: 15, ...changes,
});
const phase1Score = (changes = {}) => ({
  energy: 72, cognitive: 63,
  energyModelVersion: 'energy-rules-v3-phase1',
  cognitiveModelVersion: 'cognitive-rules-v3-phase1',
  deterministicEnergy: null, personalizedModelVersion: null,
  hasEnergyScore: true, hasCognitiveScore: true,
  confidence: 0.8, cognitiveConfidence: 0.8,
  freshness: 1, cognitiveFreshness: 1, baselineConfidence: 0,
  personalBaselines: null, inputCount: 2, cognitiveInputCount: 2,
  isEstimate: true, drivers: [], cognitiveDrivers: [],
  previousCognitive: null, cognitiveDelta: null,
  day: Timestamp.fromDate(new Date('2026-10-03T00:00:00Z')),
  calculatedAt: Timestamp.fromDate(new Date('2026-10-03T12:02:00Z')),
  schemaVersion: 15, ...changes,
});
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

const forecastDay = (changes = {}) => ({
  formatVersion: 1, localDate: '2026-10-24',
  day: Timestamp.fromDate(new Date('2026-10-24T07:00:00Z')),
  dayEnd: Timestamp.fromDate(new Date('2026-10-25T07:00:00Z')),
  utcOffsetMinutes: -420, points: [], ...changes,
});
const heartRateDay = (changes = {}) => ({
  schemaVersion: 1, aggregation: 'utc-day-v1', day: '2026-10-24', source: 'healthKit',
  sampleCount: 2, sum: 140, min: 65, max: 75,
  firstAt: '2026-10-24T12:00:00.000Z', latestAt: '2026-10-24T13:00:00.000Z', latestValue: 75,
  qualitySum: 2, qualityMin: 1, zeroQualityCount: 0,
  sampleIdDigest: 'a'.repeat(64), contentDigest: 'b'.repeat(64),
  hours: [{ hour: 12, count: 1 }, { hour: 13, count: 1 }],
  timezoneProvenance: { kind: 'device-local-at-import', zoneNames: ['America/Los_Angeles'],
    offsetMinutes: [-420], unknownSampleCount: 0 },
  writerId: 'fixture-phone', ...changes,
});
const addInputChange = (batch, db, collectionName, id, after, revision,
  { sourceAfter = after, changeId = `${collectionName}__${id}`, changes = {} } = {}) => {
  const reference = child(db, collectionName, id);
  if (sourceAfter == null) batch.delete(reference);
  else batch.set(reference, sourceAfter, { merge: true });
  batch.set(child(db, 'inputChanges', changeId), {
    collection: collectionName, id, revision, after, ...changes,
  });
};
const trackedWrite = (db, collectionName, id, after, revision, options) => {
  const batch = writeBatch(db);
  batch.update(root(db), { inputSyncVersion: 1, inputRevision: revision });
  addInputChange(batch, db, collectionName, id, after, revision, options);
  return batch.commit();
};

test('packed forecast days preserve owner scope, shape and calendar bounds', async () => {
  await seed();
  const db = signedIn();
  const target = child(db, 'forecastDays', '2026-10-24');
  await assertSucceeds(setDoc(target, forecastDay()));
  await assertSucceeds(getDocs(query(collection(db, 'users/owner/forecastDays'),
    where('localDate', '>=', '2026-10-20'), where('localDate', '<=', '2026-10-30'))));
  await assertFails(setDoc(target, forecastDay({ formatVersion: 2 })));
  await assertFails(setDoc(target, forecastDay({ localDate: '2026-10-25' })));
  await assertFails(setDoc(target, forecastDay({ dayEnd: forecastDay().day })));
  await assertFails(setDoc(target, forecastDay({ points: Array(49).fill({}) })));
  await assertFails(getDoc(child(signedIn('other'), 'forecastDays', '2026-10-24')));
});

test('heart-rate summaries validate daily aggregates and retain the original writer', async () => {
  await seed();
  const db = signedIn();
  const target = child(db, 'heartRateDays', '2026-10-24');
  await assertSucceeds(setDoc(target, heartRateDay()));
  await assertSucceeds(updateDoc(target, { contentDigest: 'c'.repeat(64) }));
  await assertFails(updateDoc(target, { writerId: 'different-phone' }));
  for (const changes of [{ day: '2026-10-25' }, { sampleCount: 0 }, { sum: 1000 },
    { sampleIdDigest: 'bad' }, { hours: Array(25).fill({}) }, { qualitySum: 3 }]) {
    await assertFails(setDoc(target, heartRateDay(changes)));
  }
  await assertFails(setDoc(child(signedIn('other'), 'heartRateDays', '2026-10-24'), heartRateDay()));
});

test('cardiac context extends the same daily summary with native or estimated provenance', async () => {
  await seed();
  const db = signedIn();
  const target = child(db, 'heartRateDays', '2026-10-24');
  const payload = heartRateDay({ schemaVersion: 2, rawContentDigest: 'd'.repeat(64),
    cardiacContext: {
      hrv: { mean: 45, sampleCount: 3, source: 'healthKit', unit: 'ms' },
      restingHeartRate: { mean: 58, sampleCount: 1, source: 'estimatedFromHeartRate', unit: 'bpm' },
    } });
  await assertSucceeds(setDoc(target, payload));
  await assertSucceeds(setDoc(target, { ...payload, cardiacContext: {
    restingHeartRate: { mean: 60, sampleCount: 2, source: 'healthKit', unit: 'bpm' },
  } }));
  for (const changes of [
    { schemaVersion: 1 }, { rawContentDigest: 'invalid' }, { cardiacContext: {} },
    { cardiacContext: { unexpected: 1 } },
    { cardiacContext: { hrv: { mean: 45, sampleCount: 1, source: 'estimatedFromHeartRate', unit: 'ms' } } },
    { cardiacContext: { hrv: { mean: 45, sampleCount: 1, source: 'healthKit', unit: 'bpm' } } },
    { cardiacContext: { hrv: { mean: 0, sampleCount: 1, source: 'healthKit', unit: 'ms' } } },
    { cardiacContext: { restingHeartRate: { mean: 58, sampleCount: 0, source: 'healthKit', unit: 'bpm' } } },
  ]) await assertFails(setDoc(target, { ...payload, ...changes }));
  await assertFails(setDoc(child(signedIn('other'), 'heartRateDays', '2026-10-24'), payload));
  await assertFails(updateDoc(target, { writerId: 'different-phone' }));
});

test('sampled bpm variation is bounded and cannot masquerade as HRV', async () => {
  await seed();
  const db = signedIn();
  const target = child(db, 'heartRateDays', '2026-10-24');
  const variation = {
    rmsSuccessiveDifferenceBpm: 2.3, sampleCount: 6, pairCount: 5,
    firstAt: '2026-10-24T12:00:00.000Z', latestAt: '2026-10-24T15:00:00.000Z',
    source: 'healthKit', unit: 'bpm', method: 'sampled-bpm-successive-difference-v1',
    timezoneBasis: 'device-local-at-import',
  };
  const payload = heartRateDay({ schemaVersion: 2, rawContentDigest: 'd'.repeat(64),
    sampleCount: 6, sum: 420, qualitySum: 6, latestAt: variation.latestAt,
    cardiacContext: { sampledHeartRateVariation: variation } });
  await assertSucceeds(setDoc(target, payload));
  for (const changes of [{ unit: 'ms' }, { method: 'SDNN' }, { sampleCount: 5 },
    { sampleCount: 7 }, { pairCount: 6 }, { rmsSuccessiveDifferenceBpm: 281 },
    { timezoneBasis: 'current-device' }, { firstAt: '2026-10-23T12:00:00.000Z' }]) {
    await assertFails(setDoc(target, { ...payload,
      cardiacContext: { sampledHeartRateVariation: { ...variation, ...changes } } }));
  }
});

test('sync metadata can activate but cannot downgrade, disappear or skip revisions', async () => {
  await seed();
  const db = signedIn();
  await assertSucceeds(updateDoc(root(db), { inputSyncVersion: 1, inputRevision: 1,
    heartRateStorageVersion: 1 }));
  for (const changes of [{ inputSyncVersion: 0 }, { inputSyncVersion: deleteField() },
    { heartRateStorageVersion: 0 }, { heartRateStorageVersion: deleteField() },
    { inputRevision: 0 }, { inputRevision: 3 }, { inputRevision: 1.5 }]) {
    await assertFails(updateDoc(root(db), changes));
  }
  await assertSucceeds(updateDoc(root(db), { inputRevision: 2 }));
  await assertSucceeds(updateDoc(root(db), { profile: { displayName: 'Retained metadata' } }));
});

test('first atomic patch activates tracked sync and later source writes need a matching journal', async () => {
  await seed();
  const db = signedIn();
  await assertSucceeds(trackedWrite(db, 'signals', 'row', phase1Signal(), 1));
  await assertFails(updateDoc(child(db), { value: 2 }));
  await assertFails(deleteDoc(child(db)));
  await assertFails(setDoc(child(db, 'signals', 'untracked'), phase1Signal()));
  await assertSucceeds(trackedWrite(db, 'signals', 'row', phase1Signal({ value: 2 }), 2));
  await assertSucceeds(trackedWrite(db, 'signals', 'row', null, 3));
  assert.equal((await getDocFromServer(child(db))).exists(), false);
  assert.equal((await getDocFromServer(child(db, 'inputChanges', 'signals__row'))).data().after, null);
  await assertFails(deleteDoc(child(db, 'inputChanges', 'signals__row')));
});

test('tracked source values reject mismatched payloads, identities, revisions and false deletions', async () => {
  await seed(profile({ inputSyncVersion: 1, inputRevision: 1 }));
  const db = signedIn();
  for (const options of [
    { sourceAfter: phase1Signal({ value: 2 }) },
    { changeId: 'signals__wrong' },
    { changes: { collection: 'checkIns' } },
    { changes: { id: 'wrong' } },
    { changes: { revision: 1 } },
    { changes: { unexpected: true } },
    { changes: { after: null } },
  ]) {
    await assertFails(trackedWrite(db, 'signals', 'row', phase1Signal(), 2, options));
  }
  await assertFails(trackedWrite(db, 'signals', 'row', null, 2,
    { changes: { after: phase1Signal() } }));
});

test('tracked writes preserve unknown source fields and validate research check-ins', async () => {
  await seed();
  const db = signedIn();
  await assertSucceeds(setDoc(child(db), phase1Signal({ futureField: 'preserved' })));
  await assertSucceeds(trackedWrite(db, 'signals', 'row', phase1Signal({ value: 1 }), 1));
  assert.equal((await getDocFromServer(child(db))).data().futureField, 'preserved');
  await assertSucceeds(trackedWrite(db, 'checkIns', 'research', researchCheckIn(), 2));
  await assertSucceeds(trackedWrite(db, 'checkIns', 'research', researchCheckIn({ note: 'edited' }), 3));
  await assertFails(trackedWrite(db, 'checkIns', 'research', { energy: 4 }, 4));
});

test('tracked check-ins cannot omit known answers or bypass bounded questionnaire validation', async () => {
  await seed(profile({ inputSyncVersion: 1, inputRevision: 1 }));
  const db = signedIn();
  const full = researchCheckIn();
  for (const key of ['energy', 'questionnaireVersion', 'questionnaireSnapshot', 'timestamp']) {
    const incomplete = { ...full };
    delete incomplete[key];
    await assertFails(trackedWrite(db, 'checkIns', 'research', incomplete, 2, { sourceAfter: full }));
  }
  for (const mutate of [
    value => { value.questionnaireSnapshot.items[0].prompt = 'x'.repeat(501); },
    value => { value.questionnaireSnapshot.items[1].anchors['1'] = []; },
    value => { value.questionnaireSnapshot.items[2].extra = true; },
    value => { value.questionnaireSnapshot.items[3].optional = false; },
    value => { value.answeredItemCount = 6; },
  ]) {
    const data = researchCheckIn();
    mutate(data);
    await assertFails(trackedWrite(db, 'checkIns', 'research', data, 2));
  }
  await assertSucceeds(trackedWrite(db, 'checkIns', 'research', full, 2));
});

test('sixteen complete research check-ins fit the atomic rules budgets', async () => {
  await seed(profile({ inputSyncVersion: 1, inputRevision: 1 }));
  const db = signedIn();
  const batch = writeBatch(db);
  batch.update(root(db), { inputRevision: 2 });
  for (let index = 0; index < 16; index++) {
    addInputChange(batch, db, 'checkIns', `row-${index}`, researchCheckIn({
      energy: 7, fatigue: 7, sleepiness: 7, focus: 7, mood: 7, stress: 7,
      completionStatus: 'complete', answeredItemCount: 6,
    }), 2);
  }
  await assertSucceeds(batch.commit());
});

test('summary writes and tracked patches retain fail-closed privacy checks', async () => {
  await seed({ consentFlags: flags(false), inputSyncVersion: 1, inputRevision: 1 });
  const db = signedIn();
  await assertFails(setDoc(child(db, 'forecastDays', '2026-10-24'), forecastDay()));
  await assertFails(setDoc(child(db, 'heartRateDays', '2026-10-24'), heartRateDay()));
  await assertFails(trackedWrite(db, 'signals', 'row', phase1Signal(), 2));
  await assertSucceeds(getDocs(collection(db, 'users/owner/forecastDays')));
  await assertSucceeds(getDocs(collection(db, 'users/owner/heartRateDays')));
  await assertSucceeds(getDocs(collection(db, 'users/owner/inputChanges')));
});

test('sixteen source changes plus journals fit the atomic rules access budget', async () => {
  await seed(profile({ inputSyncVersion: 1, inputRevision: 1 }));
  const db = signedIn();
  const batch = writeBatch(db);
  batch.update(root(db), { inputRevision: 2 });
  for (let index = 0; index < 16; index++) {
    addInputChange(batch, db, 'signals', `row-${index}`, phase1Signal({ value: index }), 2);
  }
  await assertSucceeds(batch.commit());
  const changes = await getDocsFromServer(query(collection(db, 'users/owner/inputChanges'),
    where('revision', '>', 1), where('revision', '<=', 2)));
  assert.equal(changes.size, 16);
});

test('summary storage blocks new raw HealthKit heart rates while preserving other observations', async () => {
  await seed(profile({ inputSyncVersion: 1, inputRevision: 1, heartRateStorageVersion: 1 }));
  const db = signedIn();
  await assertFails(trackedWrite(db, 'signals', 'heart', phase1Signal({ type: 'heartRate', source: 'healthKit' }), 2));
  await assertSucceeds(trackedWrite(db, 'signals', 'hrv', phase1Signal({ type: 'hrv', source: 'healthKit' }), 2));
  await assertSucceeds(trackedWrite(db, 'signals', 'rest', phase1Signal({ type: 'restingHeartRate', source: 'healthKit' }), 3));
  await assertSucceeds(trackedWrite(db, 'signals', 'manual', phase1Signal({ type: 'heartRate', source: 'manual' }), 4));
});

test('privacy deletion permits cleanup of tracked sources and tombstones without journal rewrites', async () => {
  await seed();
  const db = signedIn();
  await assertSucceeds(trackedWrite(db, 'signals', 'row', phase1Signal(), 1));
  await assertSucceeds(setDoc(root(db), marker(), { merge: true }));
  await assertSucceeds(deleteDoc(child(db)));
  await assertSucceeds(deleteDoc(child(db, 'inputChanges', 'signals__row')));
});

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

test('legacy and revoked accounts can still inspect, export and delete all known collections', async () => {
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

test('Phase 1 manual zero persists on the server; missing and cleared overrides stay distinct', async () => {
  await seed(profile({ schemaVersion: 15 }));
  const db = signedIn();
  const imported = phase1Signal({ value: 1.5, source: 'healthKit',
    groupId: null, recordedAt: null });
  await assertSucceeds(setDoc(child(db, 'signals', 'imported-exercise'), imported));
  const manual = child(db, 'signals', 'manual-exercise');
  // This is the same parent-read/merged child-write operation used by the
  // input patch adapter. Zero must remain data, not become a delete operation.
  await assertSucceeds(runTransaction(db, async transaction => {
    await transaction.get(root(db));
    await transaction.get(manual);
    transaction.set(manual, phase1Signal({ value: 0.5 }), { merge: true });
  }));
  await assertSucceeds(runTransaction(db, async transaction => {
    await transaction.get(root(db));
    await transaction.get(manual);
    transaction.set(manual, phase1Signal(), { merge: true });
  }));

  // A new authenticated client and explicit server reads avoid proving only a
  // write client's local cache. This is cloud reload, not a device restart test.
  const reloaded = signedIn();
  const zero = await assertSucceeds(getDocFromServer(child(reloaded, 'signals', 'manual-exercise')));
  assert.equal(zero.exists(), true);
  assert.equal(zero.data().value, 0);
  assert.equal(zero.data().source, 'manual');
  assert.equal(zero.data().groupId, 'activity-test');
  assert.equal(zero.data().schemaVersion, 15);
  const missing = await assertSucceeds(getDocFromServer(child(reloaded, 'signals', 'missing-exercise')));
  assert.equal(missing.exists(), false);
  const exported = await assertSucceeds(getDocsFromServer(collection(reloaded, 'users/owner/signals')));
  assert.equal(exported.size, 2);
  assert.equal(exported.docs.find(value => value.id === 'manual-exercise').data().value, 0);
  assert.equal(exported.docs.find(value => value.id === 'imported-exercise').data().value, 1.5);

  await assertSucceeds(deleteDoc(child(reloaded, 'signals', 'manual-exercise')));
  const afterClear = signedIn();
  assert.equal((await getDocFromServer(child(afterClear, 'signals', 'manual-exercise'))).exists(), false);
  assert.deepEqual((await getDocFromServer(child(afterClear, 'signals', 'imported-exercise'))).data(), imported);
});

test('Phase 1 deterministic merge clears obsolete personalization on a server reload', async () => {
  await seed(profile({ schemaVersion: 15 }));
  const db = signedIn();
  const score = child(db, 'scoreSnapshots', '2026-10-03');
  await assertSucceeds(setDoc(score, phase1Score({ energy: 58,
    energyModelVersion: 'energy-rules-v2', deterministicEnergy: 50,
    personalizedModelVersion: 'obsolete-personalized-model',
    drivers: [{ label: 'Personalized Energy adjustment', contribution: 8,
      detail: 'Synthetic legacy fixture', explanation: '', freshness: 1,
      source: null, evidenceAt: null }],
  })));
  // upsertScoreSnapshot uses set(..., merge: true). Omitting these nulls would
  // retain the old fallback and model ID even after replacing energy/drivers.
  await assertSucceeds(setDoc(score, phase1Score(), { merge: true }));
  const reloaded = await assertSucceeds(getDocFromServer(child(signedIn(), 'scoreSnapshots', '2026-10-03')));
  assert.equal(reloaded.data().energy, 72);
  assert.equal(reloaded.data().energyModelVersion, 'energy-rules-v3-phase1');
  assert.equal(Object.hasOwn(reloaded.data(), 'deterministicEnergy'), true);
  assert.equal(Object.hasOwn(reloaded.data(), 'personalizedModelVersion'), true);
  assert.equal(reloaded.data().deterministicEnergy, null);
  assert.equal(reloaded.data().personalizedModelVersion, null);
  assert.deepEqual(reloaded.data().drivers, []);
});

test('Phase 1 unavailable score merge clears stale cognitive values and availability', async () => {
  await seed(profile({ schemaVersion: 15 }));
  const db = signedIn();
  const score = child(db, 'scoreSnapshots', '2026-10-03');
  await assertSucceeds(setDoc(score, phase1Score({
    personalBaselines: { obsoleteFixture: true }, previousCognitive: 61, cognitiveDelta: 2,
  })));
  await assertSucceeds(setDoc(score, phase1Score({ energy: 0, cognitive: null,
    hasEnergyScore: false, hasCognitiveScore: false,
    confidence: 0, cognitiveConfidence: 0, freshness: 0, cognitiveFreshness: 0,
    inputCount: 0, cognitiveInputCount: 0,
  }), { merge: true }));
  const reloaded = (await assertSucceeds(getDocFromServer(child(signedIn(), 'scoreSnapshots', '2026-10-03')))).data();
  assert.equal(reloaded.hasEnergyScore, false);
  assert.equal(reloaded.hasCognitiveScore, false);
  assert.equal(reloaded.cognitive, null);
  assert.equal(reloaded.personalBaselines, null);
  assert.equal(reloaded.previousCognitive, null);
  assert.equal(reloaded.cognitiveDelta, null);
  assert.equal(reloaded.inputCount, 0);
  assert.equal(reloaded.cognitiveInputCount, 0);
});

test('Phase 1 zero and null payloads retain privacy, guardian and outcome consent gates', async () => {
  const db = signedIn();
  for (const userData of [
    { schemaVersion: 15, consentFlags: flags(false) },
    profile({ schemaVersion: 15, privacyConsent: privacy({ ageBand: '16to17' }) }),
  ]) {
    await seed(userData);
    await assertFails(setDoc(child(db, 'signals'), phase1Signal()));
    await assertFails(setDoc(child(db, 'scoreSnapshots'), phase1Score()));
  }
  await seed(profile({ schemaVersion: 15,
    privacyConsent: privacy({ ageBand: '16to17' }) }));
  const approved = signedIn('owner', guardianClaims);
  await assertSucceeds(setDoc(child(approved, 'signals'), phase1Signal()));
  await assertSucceeds(setDoc(child(approved, 'scoreSnapshots'), phase1Score()));
  await assertFails(setDoc(child(signedIn('other', guardianClaims), 'signals'), phase1Signal()));
  await assertFails(setDoc(child(signedIn('other', guardianClaims), 'scoreSnapshots'), phase1Score()));
  const outcome = { type: 'observedEnergy', value: 4, unit: 'rating_1_10',
    observedAt: Timestamp.now(), recordedAt: Timestamp.now(), source: 'checkIn',
    sourceId: 'synthetic-checkin', recommendationId: null, consentVersion: 1, schemaVersion: 15 };
  await assertFails(setDoc(child(approved, 'outcomes'), outcome));
  await assertSucceeds(updateDoc(root(approved), consentChange(true)));
  await assertSucceeds(setDoc(child(approved, 'outcomes'), outcome));
  await assertSucceeds(updateDoc(root(approved), consentChange(false)));
  await assertFails(updateDoc(child(approved, 'outcomes'), { value: 5 }));
  // Revocation and loss of guardian claims retain owner export/deletion access.
  for (const name of ['signals', 'scoreSnapshots', 'outcomes']) {
    await assertSucceeds(getDocsFromServer(collection(db, `users/owner/${name}`)));
    await assertSucceeds(deleteDoc(child(db, name)));
  }
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

// Phase 2A uses existing owner checkIns documents. These are synthetic custom
// item definitions, not published instruments or real participant responses.
const researchCheckIn = (changes = {}) => ({
  energy: 7, fatigue: 3, sleepiness: null, focus: null, mood: null, stress: null,
  period: 'morning', note: '',
  timestamp: Timestamp.fromDate(new Date('2026-10-04T18:00:00Z')),
  recordedAt: Timestamp.fromDate(new Date('2026-10-04T18:01:00Z')),
  localDate: '2026-10-04', timezone: 'America/Los_Angeles', utcOffsetMinutes: -420,
  questionnaireVersion: 'tonyo-self-report-draft-v1', questionnaireLanguage: 'en',
  source: 'selfReport', completionStatus: 'partial', answeredItemCount: 2,
  schemaVersion: 16,
  questionnaireSnapshot: {
    version: 'tonyo-self-report-draft-v1', language: 'en', kind: 'customSelfReport',
    status: 'draftNotClinicallyValidated', recallPeriod: 'right now', recallPeriodText: 'right now',
    items: ['energy', 'fatigue', 'sleepiness', 'focus', 'mood', 'stress'].map(id => ({
      id, label: id, prompt: '', anchors: {'1': 'low', '5': 'middle', '10': 'high'}, optional: true,
    })),
  }, ...changes,
});

test('Phase 2A partial integer answers and explicit clearing survive real server reload/export', async () => {
  await seed();
  const db = signedIn();
  const ref = child(db, 'checkIns', 'measurement');
  await assertSucceeds(setDoc(ref, researchCheckIn()));
  await assertSucceeds(runTransaction(db, async transaction => {
    const previous = await transaction.get(ref);
    assert.equal(previous.data().energy, 7);
    transaction.set(ref, { energy: null, answeredItemCount: 1 }, { merge: true });
  }));
  const fresh = signedIn();
  const loaded = (await assertSucceeds(getDocFromServer(child(fresh, 'checkIns', 'measurement')))).data();
  assert.equal(loaded.energy, null);
  assert.equal(loaded.fatigue, 3);
  assert.equal(loaded.sleepiness, null);
  assert.equal(loaded.period, 'morning');
  assert.equal(loaded.completionStatus, 'partial');
  assert.equal(loaded.questionnaireSnapshot.items.length, 6);
  assert.equal((await assertSucceeds(getDocsFromServer(collection(fresh, 'users/owner/checkIns')))).size, 1);
});

test('Phase 2A rejects zero, fractional, empty and malformed metadata without filling missing answers', async () => {
  await seed();
  const db = signedIn();
  for (const value of [0, -1, 11, 6.5, '7', Number.NaN]) {
    await assertFails(setDoc(child(db, 'checkIns', 'invalid'), researchCheckIn({ energy: value })));
  }
  for (const changes of [
    { energy: null, fatigue: null, answeredItemCount: 0, completionStatus: 'empty' },
    { answeredItemCount: 6 }, { completionStatus: 'complete' }, { period: 'afternoon' },
    { questionnaireVersion: null }, { questionnaireLanguage: 'unknown' },
    { localDate: 'today' }, { utcOffsetMinutes: 900 }, { source: 'model' },
    { questionnaireSnapshot: {} }, { recordedAt: Timestamp.fromMillis(0) },
  ]) {
    await assertFails(setDoc(child(db, 'checkIns', 'invalid'), researchCheckIn(changes)));
  }
  const missingMarker = researchCheckIn();
  delete missingMarker.questionnaireVersion;
  await assertFails(setDoc(child(db, 'checkIns', 'invalid'), missingMarker));
});

test('Phase 2A definitions cannot be downgraded, rewritten or attached to a legacy response', async () => {
  await seed();
  const db = signedIn();
  const ref = child(db, 'checkIns', 'measurement');
  await assertSucceeds(setDoc(ref, researchCheckIn()));
  await assertFails(setDoc(ref, { period: 'morning', energy: 7, mood: 6, stress: 4 }));
  await assertFails(updateDoc(ref, { questionnaireVersion: deleteField() }));
  await assertFails(updateDoc(ref, { 'questionnaireSnapshot.items': [] }));
  const changed = researchCheckIn();
  changed.questionnaireSnapshot.items[0].anchors['10'] = 'different wording';
  await assertFails(setDoc(ref, changed));
  await assertFails(updateDoc(ref, { timestamp: Timestamp.fromDate(new Date('2026-10-04T17:00:00Z')) }));
  const legacy = child(db, 'checkIns', 'legacy');
  await assertSucceeds(setDoc(legacy, { period: 'morning', energy: 7, mood: 6, stress: 4 }));
  await assertFails(setDoc(legacy, researchCheckIn()));
  await assertSucceeds(updateDoc(legacy, { note: 'retained legacy edit' }));
});

test('Phase 2A complete response stays six independent values and permits deliberate clearing', async () => {
  await seed();
  const db = signedIn();
  const ref = child(db, 'checkIns', 'complete');
  await assertSucceeds(setDoc(ref, researchCheckIn({
    sleepiness: 4, focus: 8, mood: 6, stress: 2, completionStatus: 'complete', answeredItemCount: 6,
  })));
  const data = (await getDocFromServer(ref)).data();
  assert.deepEqual(['energy', 'fatigue', 'sleepiness', 'focus', 'mood', 'stress'].map(key => data[key]), [7, 3, 4, 8, 6, 2]);
  await assertSucceeds(updateDoc(ref, { fatigue: deleteField(), answeredItemCount: 5, completionStatus: 'partial' }));
  assert.equal((await getDocFromServer(ref)).data().fatigue, undefined);
});

test('Phase 2A enforces privacy/guardian/account isolation while optional learning remains separate', async () => {
  await seed();
  const owner = signedIn();
  await assertSucceeds(setDoc(child(owner, 'checkIns', 'measurement'), researchCheckIn()));
  await assertFails(setDoc(child(signedIn('other'), 'checkIns', 'cross'), researchCheckIn()));
  await assertFails(getDoc(child(signedIn('other'), 'checkIns', 'measurement')));
  await assertFails(setDoc(child(owner, 'outcomes', 'not-opted-in'), { value: 7 }));
  await seed(profile({ privacyConsent: privacy({ ageBand: '16to17' }) }));
  await assertFails(setDoc(child(owner, 'checkIns', 'minor'), researchCheckIn()));
  await assertSucceeds(setDoc(child(signedIn('owner', guardianClaims), 'checkIns', 'minor'), researchCheckIn()));
  await seed({ consentFlags: flags(false) });
  await assertFails(setDoc(child(owner, 'checkIns', 'no-consent'), researchCheckIn()));
  await assertSucceeds(getDocsFromServer(collection(owner, 'users/owner/checkIns')));
  await assertSucceeds(deleteDoc(child(owner, 'checkIns', 'measurement')));
});

test('Phase 2A snapshot bounds still reject malformed keys, types and oversized text', async () => {
  await seed();
  const db = signedIn();
  const mutations = [
    data => { data.questionnaireSnapshot.extra = true; },
    data => { delete data.questionnaireSnapshot.status; },
    data => { data.questionnaireSnapshot.items[2].extra = true; },
    data => { delete data.questionnaireSnapshot.items[2].prompt; },
    data => { data.questionnaireSnapshot.items[2].anchors.extra = 'unexpected'; },
    data => { delete data.questionnaireSnapshot.items[2].anchors['5']; },
    data => { data.questionnaireSnapshot.items[2].label = 12; },
    data => { data.questionnaireSnapshot.items[2].prompt = {}; },
    data => { data.questionnaireSnapshot.items[2].anchors['1'] = []; },
    data => { data.questionnaireSnapshot.items[2].label = ''; },
    data => { data.questionnaireSnapshot.items[2].label = 'x'.repeat(101); },
    data => { data.questionnaireSnapshot.items[2].prompt = 'x'.repeat(501); },
    data => { data.questionnaireSnapshot.items[2].anchors['10'] = 'x'.repeat(301); },
    data => { data.questionnaireSnapshot.items[2].optional = false; },
    data => { data.questionnaireSnapshot.items[2].id = 'energy'; },
  ];
  for (const mutate of mutations) {
    const data = researchCheckIn();
    mutate(data);
    await assertFails(setDoc(child(db, 'checkIns', 'bad-shape'), data));
  }
});

test('Phase 2A counts duplicate ratings and supports bounded Unicode text under guardian checks', async () => {
  await seed(profile({ privacyConsent: privacy({ ageBand: '16to17' }) }));
  const db = signedIn('owner', guardianClaims);
  const data = researchCheckIn({ energy: 7, fatigue: 7, sleepiness: 7, focus: 7,
    mood: 7, stress: 7, completionStatus: 'complete', answeredItemCount: 6 });
  data.questionnaireSnapshot.items[0].label = '精力';
  data.questionnaireSnapshot.items[0].prompt = 'línea\n下一行';
  const ref = child(db, 'checkIns', 'same-ratings');
  await assertSucceeds(setDoc(ref, data));
  await assertSucceeds(updateDoc(ref, { note: 'same six answers retained' }));
  const saved = (await getDocFromServer(ref)).data();
  assert.equal(saved.answeredItemCount, 6);
  assert.equal(saved.questionnaireSnapshot.items[0].label, '精力');
  assert.equal(saved.questionnaireSnapshot.items[0].prompt, 'línea\n下一行');
});
