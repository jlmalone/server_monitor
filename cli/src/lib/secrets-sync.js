import { existsSync, readFileSync, statSync } from 'fs';
import { homedir } from 'os';
import { join } from 'path';
import { spawnSync } from 'child_process';
function expandHome(path) {
  if (path === '~') return homedir();
  if (path.startsWith('~/')) return join(homedir(), path.slice(2));
  return path;
}

export function secretsSyncConfigPath() {
  return process.env.SERVERMONITOR_SECRETS_SYNC
    || join(homedir(), '.config', 'server-monitor', 'secrets-sync.json');
}

export function loadSecretsSyncConfig(path = secretsSyncConfigPath()) {
  if (!existsSync(path)) {
    throw new Error(`secrets-sync config not found: ${path}`);
  }
  const parsed = JSON.parse(readFileSync(path, 'utf-8'));
  return normalizeSecretsSyncConfig(parsed);
}

export function normalizeSecretsSyncConfig(raw) {
  if (!raw || typeof raw !== 'object') {
    throw new Error('secrets-sync config must be a JSON object');
  }
  const sourceDir = expandHome(String(raw.sourceDir || '').trim());
  const hosts = Array.isArray(raw.hosts)
    ? raw.hosts.map((h) => String(h).trim()).filter(Boolean)
    : [];
  const exclude = Array.isArray(raw.exclude)
    ? raw.exclude.map((e) => String(e).trim()).filter(Boolean)
    : [];
  const connectTimeoutSeconds = Number.isFinite(raw.connectTimeoutSeconds)
    ? Math.max(1, Number(raw.connectTimeoutSeconds))
    : 12;
  const remoteNice = Number.isFinite(raw.remoteNice) ? Number(raw.remoteNice) : 19;
  if (!sourceDir) {
    throw new Error('secrets-sync sourceDir is required');
  }
  if (hosts.length === 0) {
    throw new Error('secrets-sync hosts must list at least one SSH target');
  }
  return { sourceDir, hosts, exclude, connectTimeoutSeconds, remoteNice };
}

export function rsyncArgv(host, config, { dryRun = false } = {}) {
  const source = config.sourceDir.endsWith('/') ? config.sourceDir : `${config.sourceDir}/`;
  const dest = `${host}:.config/secrets/`;
  const args = ['-a', '--chmod=go-rwx'];
  for (const pattern of config.exclude) {
    args.push('--exclude', pattern);
  }
  args.push(`--rsync-path=nice -n ${config.remoteNice} rsync`);
  args.push('-e', `ssh -o BatchMode=yes -o ConnectTimeout=${config.connectTimeoutSeconds}`);
  if (dryRun) args.push('--dry-run');
  args.push(source, dest);
  return args;
}

function assertSourceDir(sourceDir) {
  if (!existsSync(sourceDir) || !statSync(sourceDir).isDirectory()) {
    throw new Error(`secrets source directory missing: ${sourceDir}`);
  }
}

export function syncSecrets(config, { dryRun = false, runner = spawnSync } = {}) {
  assertSourceDir(config.sourceDir);
  const results = [];
  for (const host of config.hosts) {
    const mkdir = runner('ssh', [
      '-o', 'BatchMode=yes',
      '-o', `ConnectTimeout=${config.connectTimeoutSeconds}`,
      host,
      'mkdir -p "$HOME/.config/secrets" && chmod 700 "$HOME/.config/secrets"'
    ], { encoding: 'utf-8' });
    if (mkdir.status !== 0) {
      results.push({
        host,
        ok: false,
        step: 'ssh',
        error: (mkdir.stderr || mkdir.stdout || 'ssh failed').trim()
      });
      continue;
    }
    const rsync = runner('rsync', rsyncArgv(host, config, { dryRun }), { encoding: 'utf-8' });
    if (rsync.status !== 0) {
      results.push({
        host,
        ok: false,
        step: 'rsync',
        error: (rsync.stderr || rsync.stdout || 'rsync failed').trim()
      });
      continue;
    }
    results.push({ host, ok: true, dryRun });
  }
  return results;
}
