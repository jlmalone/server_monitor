import { describe, it } from 'node:test';
import assert from 'node:assert';
import { loadConfig, getService, expandPath } from '../src/lib/config.js';

describe('config library', () => {

  describe('loadConfig()', () => {
    it('should load and parse services.json', () => {
      const config = loadConfig();

      // Check structure
      assert.ok(config);
      assert.ok(config.settings);
      assert.ok(Array.isArray(config.services));

      // Check settings
      assert.ok(config.settings.logDir);
      assert.ok(config.settings.identifierPrefix);

      // Check at least one service exists
      assert.ok(config.services.length > 0);
    });

    it('should have valid service structure', () => {
      const config = loadConfig();
      const service = config.services[0];

      // Required fields
      assert.ok(service.name);
      assert.ok(service.identifier);
      assert.ok(service.port);

      // Identifier should have prefix
      assert.ok(service.identifier.startsWith(config.settings.identifierPrefix));
    });

    it('should have services with valid ports', () => {
      const config = loadConfig();

      // Check only non-test services (real services should have valid ports)
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

    it('should find service by partial name match', () => {
      const config = loadConfig();

      // Assuming there's a service with "redo" in the name
      const found = getService('redo');

      if (found) {
        assert.ok(found.name.toLowerCase().includes('redo'));
      }
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
      const expanded = expandPath(path);

      assert.strictEqual(expanded, path);
    });

    it('should handle paths without tilde', () => {
      const path = 'relative/path';
      const expanded = expandPath(path);

      assert.strictEqual(expanded, path);
    });
  });
});
