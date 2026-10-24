import { spawn } from 'node:child_process';
import { createHash } from 'node:crypto';
import { readFile, access } from 'node:fs/promises';
import { dirname, delimiter } from 'node:path';
import { fileURLToPath } from 'node:url';

const directory = fileURLToPath(new URL('.', import.meta.url));
const suite = process.argv[2] ?? 'phase1';
if (!['phase1', 'sync'].includes(suite) || process.argv.length > 3) {
  throw new Error('Select only the phase1 or sync integration suite.');
}
const cli = fileURLToPath(new URL('node_modules/firebase-tools/lib/bin/firebase.js', import.meta.url));
const rules = await readFile(new URL('../../firestore.rules', import.meta.url));
console.log(`Current firestore.rules SHA-256: ${createHash('sha256').update(rules).digest('hex')}`);
try {
  await access(new URL('../../ios/Runner/GoogleService-Info.plist', import.meta.url));
  throw new Error('Remove native Firebase project configuration before local-only integration.');
} catch (error) {
  if (error.code !== 'ENOENT') throw error;
}

// Allowlisted child environment: no credentials, production project selection,
// DEBUG, or arbitrary Flutter build arguments reach the emulator or test app.
const environment = {
  PATH: `${dirname(process.execPath)}${delimiter}${process.env.PATH ?? ''}`,
  CI: 'true',
  FIREBASE_CLI_DISABLE_USAGE: 'true',
  XDG_CONFIG_HOME: fileURLToPath(new URL('.runtime/app-config', import.meta.url)),
  FIREBASE_EMULATORS_PATH: fileURLToPath(new URL('.runtime/emulators', import.meta.url)),
  FLUTTER_BIN: process.env.FLUTTER_BIN ?? 'flutter',
  TONYO_APP_INTEGRATION_SUITE: suite,
};
for (const name of ['JAVA_HOME', 'TMPDIR', 'TEMP', 'TMP', 'SYSTEMROOT', 'HOME', 'DEVELOPER_DIR']) {
  if (process.env[name]) environment[name] = process.env[name];
}
const child = spawn(process.execPath, [cli, 'emulators:exec', '--only', 'auth,firestore',
  '--project', 'demo-tonyo-privacy', '--config', '../../firebase.integration.json',
  'node app_integration_driver.mjs'], { cwd: directory, env: environment, stdio: 'inherit' });
child.on('error', error => { console.error(error.message); process.exitCode = 1; });
child.on('exit', (code, signal) => { process.exitCode = signal ? 1 : (code ?? 1); });
for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, () => child.kill(signal));
