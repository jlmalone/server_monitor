import { describe, it, before, after } from 'node:test';
import assert from 'node:assert';
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'fs';
import { tmpdir } from 'os';
import { join } from 'path';
import {
  loadSecretsSyncConfig,
  normalizeSecretsSyncConfig,
  rsyncArgv,
  syncSecrets
} from '../src/lib/secrets-sync.js';

describe('secrets-sync', () => {
  let tmpDir;

  before(() => {
    tmpDir = mkdtempSync(join(tmpdir(), 'sm-secrets-'));
  });

  after(() => {
    if (tmpDir) rmSync(tmpDir, { recursive: true, force: true });
  });

  it('expands ~/ into the home directory', () => {
    const config = normalizeSecretsSyncConfig({
      sourceDir: '~/.config/secrets',
      hosts: ['peer.example']
    });
    assert.ok(config.sourceDir.endsWith('/.config/secrets'));
    assert.ok(!config.sourceDir.startsWith('~'));
    assert.notEqual(config.sourceDir, '/.config/secrets');
  });

  it('rejects empty hosts', () => {
    assert.throws(
      () => normalizeSecretsSyncConfig({ sourceDir: '~/.config/secrets', hosts: [] }),
      /hosts/
    );
  });

  it('builds rsync argv without shell interpolation', () => {
    const config = normalizeSecretsSyncConfig({
      sourceDir: '/tmp/secrets',
      hosts: ['peer.example'],
      exclude: ['redo-backups/'],
      remoteNice: 19
    });
    const args = rsyncArgv('peer.example', config, { dryRun: true });
    assert.ok(args.includes('--dry-run'));
    assert.ok(args.includes('--exclude'));
    assert.ok(args.includes('redo-backups/'));
    assert.ok(args.includes('--rsync-path=nice -n 19 rsync'));
    assert.equal(args.at(-1), 'peer.example:.config/secrets/');
    assert.ok(!args.some((a) => a.includes(';')));
  });

  it('loads overlay JSON from SERVERMONITOR_SECRETS_SYNC', () => {
    const cfgPath = join(tmpDir, 'secrets-sync.json');
    writeFileSync(cfgPath, JSON.stringify({
      sourceDir: '/tmp/secrets',
      hosts: ['peer.example']
    }));
    process.env.SERVERMONITOR_SECRETS_SYNC = cfgPath;
    try {
      const loaded = loadSecretsSyncConfig();
      assert.equal(loaded.hosts[0], 'peer.example');
    } finally {
      delete process.env.SERVERMONITOR_SECRETS_SYNC;
    }
  });

  it('records per-host results from the runner', () => {
    const sourceDir = join(tmpDir, 'src');
    mkdirSync(sourceDir, { recursive: true });
    writeFileSync(join(sourceDir, 'token'), 'x');
    const config = normalizeSecretsSyncConfig({
      sourceDir,
      hosts: ['ok-peer', 'bad-peer']
    });
    const calls = [];
    const runner = (cmd, args) => {
      calls.push({ cmd, args });
      if (cmd === 'ssh' && args.includes('bad-peer')) {
        return { status: 1, stderr: 'ssh failed', stdout: '' };
      }
      return { status: 0, stdout: '', stderr: '' };
    };
    const results = syncSecrets(config, { runner });
    assert.equal(results.length, 2);
    assert.equal(results[0].ok, true);
    assert.equal(results[1].ok, false);
    assert.equal(results[1].step, 'ssh');
    assert.ok(calls.some((c) => c.cmd === 'rsync'));
  });
});
