import { spawn } from 'node:child_process';
import { dirname, delimiter } from 'node:path';
import { fileURLToPath } from 'node:url';

const directory = fileURLToPath(new URL('.', import.meta.url));
const cli = fileURLToPath(new URL('node_modules/firebase-tools/lib/bin/firebase.js', import.meta.url));

// Avoid inheriting live credentials, SDK project selection or DEBUG (the CLI
// logs its child environment in debug mode). Tests need only local runtimes.
const environment = {
  PATH: `${dirname(process.execPath)}${delimiter}${process.env.PATH ?? ''}`,
  CI: 'true',
  FIREBASE_CLI_DISABLE_USAGE: 'true',
  XDG_CONFIG_HOME: fileURLToPath(new URL('.runtime/config', import.meta.url)),
  FIREBASE_EMULATORS_PATH: process.env.FIREBASE_EMULATORS_PATH
    ?? fileURLToPath(new URL('.runtime/emulators', import.meta.url)),
};
for (const name of ['JAVA_HOME', 'TMPDIR', 'TEMP', 'TMP', 'SYSTEMROOT', 'NODE_EXTRA_CA_CERTS']) {
  if (process.env[name]) environment[name] = process.env[name];
}
const child = spawn(process.execPath, [cli, 'emulators:exec', '--only', 'firestore',
  '--project', 'demo-tonyo-privacy', '--config', '../../firebase.json',
  'node --test --test-concurrency=1 firestore.rules.test.mjs'], {
  cwd: directory, env: environment, stdio: 'inherit',
});
child.on('error', error => { console.error(error.message); process.exitCode = 1; });
child.on('exit', (code, signal) => { process.exitCode = signal ? 1 : (code ?? 1); });
for (const signal of ['SIGINT', 'SIGTERM']) {
  process.on(signal, () => child.kill(signal));
}
