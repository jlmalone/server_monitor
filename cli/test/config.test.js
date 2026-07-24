import { describe, it, before, after } from 'node:test';
import assert from 'node:assert';
import { writeFileSync, mkdtempSync, rmSync } from 'fs';
import { tmpdir } from 'os';
import { join } from 'path';
import { loadConfig, getService, expandPath } from '../src/lib/config.js';

// Hermetic fixture: point the config loader at a throwaway services.json via
// SERVERMONITOR_CONFIG so the suite is deterministic and never depends on (or
// mutates) the developer's real config. config.js resolves the path at call
// time, so setting the env after import is sufficient.
const FIXTURE = {
  version: '2.0.0',
  settings: { logDir: '/tmp/sm-test/logs', identifierPrefix: 'vision.salient' },
  services: [
    { name: 'alpha-service', identifier: 'vision.salient.alpha-service', port: 3000, command: ['node', 'a.js'], enabled: true },
    { name: 'beta-api', identifier: 'vision.salient.beta-api', port: 8080, command: ['node', 'b.js'], enabled: true }
  ]
};

let tmpDir;

describe('config library', () => {
  before(() => {
    tmpDir = mkdtempSync(join(tmpdir(), 'sm-cfg-'));
    const cfgPath = join(tmpDir, 'services.json');
    writeFileSync(cfgPath, JSON.stringify(FIXTURE, null, 2));
    process.env.SERVERMONITOR_CONFIG = cfgPath;
  });

  after(() => {
    delete process.env.SERVERMONITOR_CONFIG;
    if (tmpDir) rmSync(tmpDir, { recursive: true, force: true });
  });

  describe('loadConfig()', () => {
    it('should load and parse services.json', () => {
      const config = loadConfig();

      assert.ok(config);
      assert.ok(config.settings);
      assert.ok(Array.isArray(config.services));
      assert.ok(config.settings.logDir);
      assert.ok(config.settings.identifierPrefix);
      assert.strictEqual(config.services.length, FIXTURE.services.length);
    });

    it('should have valid service structure', () => {
      const config = loadConfig();
      const service = config.services[0];

      assert.ok(service.name);
      assert.ok(service.identifier);
      assert.ok(service.port);
      assert.ok(service.identifier.startsWith(config.settings.identifierPrefix));
    });

    it('should have services with valid ports', () => {
      const config = loadConfig();
      const realServices = config.services.filter(s => !s.name.startsWith('test-'));

      for (const service of realServices) {
        if (service.port) {
          assert.ok(service.port >= 1024 && service.port <= 65535,
            `Port ${service.port} for ${service.name} should be a valid user port (1024-65535)`);
        }
      }
    });
  });

  describe('getService()', () => {
    it('should find service by exact name', () => {
      const config = loadConfig();
      const firstService = config.services[0];

      const found = getService(firstService.name);

      assert.ok(found);
      assert.strictEqual(found.name, firstService.name);
      assert.strictEqual(found.identifier, firstService.identifier);
    });

    it('should find service by case-insensitive name', () => {
      const config = loadConfig();
      const firstService = config.services[0];

      const found = getService(firstService.name.toUpperCase());

      assert.ok(found);
      assert.strictEqual(found.name, firstService.name);
    });

    it('should find service by partial identifier match', () => {
      const found = getService('alpha');

      assert.ok(found);
      assert.ok(found.identifier.toLowerCase().includes('alpha'));
    });

    it('should return null for non-existent service', () => {
      const found = getService('nonexistent-service-xyz-12345');

      assert.strictEqual(found, null);
    });
  });

  describe('expandPath()', () => {
    it('should expand tilde to home directory', () => {
      const expanded = expandPath('~/test');

      assert.ok(expanded.startsWith('/'));
      assert.ok(!expanded.includes('~'));
      assert.ok(expanded.includes('test'));
    });

    it('should handle absolute paths unchanged', () => {
      const path = '/absolute/path/test';
      assert.strictEqual(expandPath(path), path);
    });

    it('should handle paths without tilde', () => {
      const path = 'relative/path';
      assert.strictEqual(expandPath(path), path);
    });
  });
});
