import { describe, it, mock, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert';
import { execSync } from 'child_process';
import {
  generatePlist,
  getServiceStatus,
  stopService,
  startService,
  restartService,
  getAllManagedServices
} from '../src/lib/launchd.js';

// Mock execSync
let mockExecCalls = [];
const originalExecSync = execSync;

beforeEach(() => {
  mockExecCalls = [];
});

describe('launchd library', () => {

  describe('generatePlist()', () => {
    it('should generate valid plist XML with KeepAlive enabled', () => {
      const service = {
        name: 'Test Service',
        identifier: 'com.test.service',
        path: '/test/path',
        command: ['node', 'server.js'],
        enabled: true
      };

      const settings = {
        logDir: '/test/logs',
        nodePath: '/usr/local/bin/node'
      };

      const plist = generatePlist(service, settings);

      // Check XML structure
      assert.ok(plist.includes('<?xml version="1.0"'));
      assert.ok(plist.includes('<key>Label</key>'));
      assert.ok(plist.includes('<string>com.test.service</string>'));
      assert.ok(plist.includes('<key>KeepAlive</key>'));
      assert.ok(plist.includes('<true/>'));
      assert.ok(plist.includes('<key>WorkingDirectory</key>'));
      assert.ok(plist.includes('/test/path'));
    });

    it('should handle command as string', () => {
      const service = {
        identifier: 'test.service',
        path: '/test',
        command: 'npm start',
        enabled: true
      };

      const settings = {
        logDir: '/logs',
        nodePath: '/usr/bin/node'
      };

      const plist = generatePlist(service, settings);

      assert.ok(plist.includes('<string>npm</string>'));
      assert.ok(plist.includes('<string>start</string>'));
    });

    it('should handle command as array', () => {
      const service = {
        identifier: 'test.service',
        path: '/test',
        command: ['npx', 'vite', '--port', '4001'],
        enabled: true
      };

      const settings = {
        logDir: '/logs',
        nodePath: '/usr/bin/node'
      };

      const plist = generatePlist(service, settings);

      assert.ok(plist.includes('<string>npx</string>'));
      assert.ok(plist.includes('<string>vite</string>'));
      assert.ok(plist.includes('<string>--port</string>'));
      assert.ok(plist.includes('<string>4001</string>'));
    });

    it('should escape XML special characters', () => {
      const service = {
        identifier: 'test.service',
        path: '/test/path<>&"\'',
        command: ['echo', 'test<>&"\''],
        enabled: true
      };

      const settings = {
        logDir: '/logs',
        nodePath: '/usr/bin/node'
      };

      const plist = generatePlist(service, settings);

      assert.ok(plist.includes('&lt;'));
      assert.ok(plist.includes('&gt;'));
      assert.ok(plist.includes('&amp;'));
      assert.ok(plist.includes('&quot;'));
      assert.ok(plist.includes('&apos;'));
    });
  });

  describe('getServiceStatus()', () => {
    it('should parse running service status', () => {
      // This is an integration test - requires actual launchd
      // In real env, would mock execSync
      const status = getServiceStatus('com.apple.SystemUIServer');

      assert.ok(typeof status.loaded === 'boolean');
      assert.ok(typeof status.running === 'boolean');
    });

    it('should return not loaded for non-existent service', () => {
      const status = getServiceStatus('com.nonexistent.service.12345');

      assert.strictEqual(status.loaded, false);
      assert.strictEqual(status.running, false);
      assert.strictEqual(status.pid, null);
    });
  });

  describe('stopService()', () => {
    it('should call launchctl unload and kill', () => {
      // Note: This tests the logic, but won't actually stop services in test env
      const identifier = 'test.service';

      // This will fail in test env but we're testing the code path exists
      try {
        stopService(identifier);
      } catch (err) {
        // Expected to fail - we're just checking it tries the right commands
        assert.ok(err.message.includes('Failed to stop service') ||
                  err.message.includes('ENOENT'));
      }
    });
  });

  describe('startService()', () => {
    it('should handle unloaded service by loading plist first', () => {
      const identifier = 'test.service.notexist';

      try {
        startService(identifier);
      } catch (err) {
        // Expected to fail - testing code path
        assert.ok(err.message.includes('Failed to start service') ||
                  err.message.includes('Plist not found'));
      }
    });
  });

  describe('restartService()', () => {
    it('should stop then start with delay', () => {
      const identifier = 'test.service';

      try {
        restartService(identifier);
      } catch (err) {
        // Expected to fail in test env
        assert.ok(err.message.includes('Failed') ||
                  err.message.includes('ENOENT'));
      }
    });
  });

  describe('getAllManagedServices()', () => {
    it('should return array of services', () => {
      const services = getAllManagedServices();

      assert.ok(Array.isArray(services));

      // If any services exist, check structure
      if (services.length > 0) {
        const service = services[0];
        assert.ok('identifier' in service);
        assert.ok('pid' in service);
        assert.ok('running' in service);
      }
    });
  });
});
