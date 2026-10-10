import { spawn } from 'node:child_process';
import { writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';

if (process.env.FIRESTORE_EMULATOR_HOST !== '127.0.0.1:8080'
    || process.env.FIREBASE_AUTH_EMULATOR_HOST !== '127.0.0.1:9099'
    || process.env.GCLOUD_PROJECT !== 'demo-tonyo-privacy') {
  throw new Error('Both loopback emulators and the fixed demo project are required.');
}
const appDirectory = fileURLToPath(new URL('../..', import.meta.url));
function run(command, args, { capture = false } = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, { cwd: appDirectory, env: process.env,
      stdio: capture ? ['ignore', 'pipe', 'pipe'] : 'inherit' });
    let output = '';
    if (capture) child.stdout.on('data', chunk => { output += chunk; });
    child.on('error', reject);
    child.on('exit', code => code === 0 ? resolve(output.trim())
      : reject(new Error(`${command} ${args[0]} exited ${code}`)));
  });
}
const runtimes = JSON.parse(await run('xcrun', ['simctl', 'list', 'runtimes', '--json'], { capture: true }));
const runtime = runtimes.runtimes.find(value => value.isAvailable && value.identifier.includes('.iOS-'));
if (!runtime) throw new Error('An installed iOS Simulator runtime is required.');
const types = JSON.parse(await run('xcrun', ['simctl', 'list', 'devicetypes', '--json'], { capture: true }));
const type = types.devicetypes.find(value => value.name === 'iPhone 17')
  ?? types.devicetypes.find(value => value.name.startsWith('iPhone'));
if (!type) throw new Error('An iPhone simulator type is required.');
// A new target is mandatory: no argument can select or overwrite a normal app.
const simulator = await run('xcrun', ['simctl', 'create', 'Tonyo Local Integration',
  type.identifier, runtime.identifier], { capture: true });
await writeFile(new URL('.runtime/app-integration-simulator-id', import.meta.url), simulator);
console.log(`Created isolated simulator: ${type.name} / ${runtime.name} (${simulator}).`);
try {
  await run('xcrun', ['simctl', 'boot', simulator]);
  await run('xcrun', ['simctl', 'bootstatus', simulator, '-b']);
  await run(process.env.FLUTTER_BIN, ['test', '--no-pub', '--no-uninstall',
    'integration_test/phase1_cloud_test.dart', '-d', simulator,
    '--dart-define=TONYO_LOCAL_EMULATORS=true', '--reporter=expanded']);
  try {
    await run('xcrun', ['simctl', 'terminate', simulator, 'com.ios.tonyo'], { capture: true });
  } catch {
    // Flutter may already have stopped its test app. Verify no live process.
    const jobs = await run('xcrun', ['simctl', 'spawn', simulator, 'launchctl', 'list'], { capture: true });
    if (jobs.split('\n').some(line => line.includes('com.ios.tonyo') && /^\d+\s/.test(line))) {
      throw new Error('The first test process could not be terminated.');
    }
  }
  console.log('First native test process stopped; starting independent restart verification.');
  await run(process.env.FLUTTER_BIN, ['test', '--no-pub', '--no-uninstall',
    'integration_test/phase1_cloud_test.dart', '-d', simulator,
    '--dart-define=TONYO_LOCAL_EMULATORS=true',
    '--dart-define=TONYO_VERIFY_PROCESS_RESTART=true', '--reporter=expanded']);
} finally {
  await run('xcrun', ['simctl', 'shutdown', simulator]);
  console.log('Only the newly created integration simulator was shut down; its synthetic container is retained.');
}
