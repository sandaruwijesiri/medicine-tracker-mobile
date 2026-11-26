import { pathToFileURL, fileURLToPath } from 'node:url';
import { resolve, dirname } from 'node:path';
import { spawn } from 'node:child_process';

// Arguments: absolute backend directory, absolute dart executable.
const [backend, dart] = process.argv.slice(2);
if (!backend || !dart) throw new Error('Usage: node tool/backend_smoke.mjs <backend-directory> <dart-executable>');
const { createApplication } = await import(pathToFileURL(resolve(backend, 'server.mjs')));
const app = createApplication({ filename: ':memory:', notificationSender: null });
await new Promise(resolve => app.server.listen(0, '127.0.0.1', resolve));
try {
  const code = await new Promise((done, reject) => {
    const child = spawn(dart, ['run', 'tool/api_smoke.dart', `http://127.0.0.1:${app.server.address().port}`], { cwd: resolve(dirname(fileURLToPath(import.meta.url)), '..'), stdio: 'inherit' });
    child.on('error', reject); child.on('exit', code => done(code));
  });
  process.exitCode = code ?? 1;
} finally { await app.close(); }
