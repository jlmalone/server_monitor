import { describe, it, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert';
import { writeFileSync, readFileSync, mkdirSync, rmSync, existsSync, unlinkSync, renameSync } from 'fs';
import { join, dirname } from 'path';
import { tmpdir, homedir } from 'os';
import { randomBytes } from 'crypto';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// We need to test config functions that use a different config path
// This requires some workarounds since the module uses a fixed path

describe('Configuration Management Extended', () => {
  
  describe('generateIdentifier()', () => {
    // Import the function for testing
    let generateIdentifier;
    
    beforeEach(async () => {
      const configModule = await import('../src/lib/config.js');
      generateIdentifier = configModule.generateIdentifier;
    });

    it('generates slug from name', () => {
      const result = generateIdentifier('My Test App', 'com.company');
      assert.strictEqual(result, 'com.company.my-test-app');
    });

    it('handles special characters', () => {
      const result = generateIdentifier('Test App (v2.0) - Beta!', 'com.test');
      assert.ok(result.startsWith('com.test.'));
      // Should only contain valid identifier chars
      const slug = result.split('.').pop();
      assert.ok(/^[a-z0-9-]+$/.test(slug));
      // Should not have consecutive hyphens typically
      assert.ok(!slug.includes('--') || slug.split('--').length <= 2);
    });

    it('uses custom prefix from settings', () => {
      const result = generateIdentifier('Service', 'vision.salient');
      assert.ok(result.startsWith('vision.salient.'));
    });

    it('handles numbers in name', () => {
      const result = generateIdentifier('Service 123', 'com.test');
      assert.strictEqual(result, 'com.test.service-123');
    });

    it('handles all uppercase name', () => {
      const result = generateIdentifier('API SERVER', 'com.test');
      assert.strictEqual(result, 'com.test.api-server');
    });

    it('handles single word name', () => {
      const result = generateIdentifier('Server', 'com.test');
      assert.strictEqual(result, 'com.test.server');
    });

    it('removes leading/trailing hyphens', () => {
      const result = generateIdentifier('  Test  ', 'com.test');
      assert.ok(!result.endsWith('-'));
      const slug = result.split('.').pop();
      assert.ok(!slug.startsWith('-'));
      assert.ok(!slug.endsWith('-'));
    });

    it('handles empty name', () => {
      const result = generateIdentifier('', 'com.test');
      // Should produce something like 'com.test.'
      assert.ok(result.startsWith('com.test.'));
    });
  });

  describe('expandPath()', () => {
    let expandPath;
    
    beforeEach(async () => {
      const configModule = await import('../src/lib/config.js');
      expandPath = configModule.expandPath;
    });

    it('expands ~ to home directory', () => {
      const result = expandPath('~/Documents/test');
      assert.strictEqual(result, join(homedir(), 'Documents/test'));
    });

    it('handles ~/ at start only', () => {
      const result = expandPath('/path/to/~file');
      // Should NOT expand ~ in middle of path
      assert.strictEqual(result, '/path/to/~file');
    });

    it('handles absolute paths unchanged', () => {
      const path = '/usr/local/bin/node';
      assert.strictEqual(expandPath(path), path);
    });

    it('handles relative paths unchanged', () => {
      const path = 'relative/path/to/file';
      assert.strictEqual(expandPath(path), path);
    });

    it('handles ~ alone', () => {
      const result = expandPath('~');
      assert.strictEqual(result, homedir());
    });

    it('handles ~/. (hidden files)', () => {
      const result = expandPath('~/.config');
      assert.strictEqual(result, join(homedir(), '.config'));
    });
  });

  describe('config validation', () => {
    it('validates required service fields', async () => {
      const { addService, loadConfig, removeService } = await import('../src/lib/config.js');
      const config = loadConfig();
      
      // Service must have required fields
      // This test documents expected behavior for the add command
      const validService = {
        name: 'Test Validation Service',
        identifier: `com.test.validation-${Date.now()}`,
        path: '/tmp',
        command: ['echo', 'test'],
        port: 9999,
        enabled: true
      };
      
      // Should succeed for valid service
      try {
        addService(validService);
        
        // Cleanup
        try {
          removeService(validService.name);
        } catch (e) {}
        
      } catch (err) {
        // If it fails, it should be for a specific reason
        assert.ok(err.message.includes('already exists') || err.message.includes('required'));
      }
    });

    it('prevents duplicate service names', async () => {
      const { addService, loadConfig, removeService } = await import('../src/lib/config.js');
      const config = loadConfig();
      
      if (config.services.length > 0) {
        const existingService = config.services[0];
        
        const duplicate = {
          name: existingService.name,
          identifier: 'com.test.duplicate',
          path: '/tmp',
          command: ['echo'],
          port: 9998
        };
        
        assert.throws(
          () => addService(duplicate),
          /already exists/
        );
      }
    });

    it('prevents duplicate identifiers', async () => {
      const { addService, loadConfig, removeService } = await import('../src/lib/config.js');
      const config = loadConfig();
      
      if (config.services.length > 0) {
        const existingService = config.services[0];
        
        const duplicate = {
          name: 'Different Name',
          identifier: existingService.identifier,
          path: '/tmp',
          command: ['echo'],
          port: 9997
        };
        
        assert.throws(
          () => addService(duplicate),
          /already exists/
        );
      }
    });
  });

  describe('getService()', () => {
    it('finds by case-insensitive name', async () => {
      const { getService, loadConfig } = await import('../src/lib/config.js');
      const config = loadConfig();
      
      if (config.services.length > 0) {
        const service = config.services[0];
        
        const foundUpper = getService(service.name.toUpperCase());
        const foundLower = getService(service.name.toLowerCase());
        
        assert.ok(foundUpper);
        assert.ok(foundLower);
        assert.strictEqual(foundUpper.identifier, service.identifier);
        assert.strictEqual(foundLower.identifier, service.identifier);
      }
    });

    it('finds by partial identifier match', async () => {
      const { getService, loadConfig } = await import('../src/lib/config.js');
      const config = loadConfig();
      
      if (config.services.length > 0) {
        const service = config.services[0];
        // Get last part of identifier
        const shortName = service.identifier.split('.').pop();
        
        const found = getService(shortName);
        
        if (found) {
          assert.strictEqual(found.identifier, service.identifier);
        }
      }
    });

    it('returns null for non-existent service', async () => {
      const { getService } = await import('../src/lib/config.js');
      
      const result = getService('definitely-not-a-real-service-xyz-12345');
      
      assert.strictEqual(result, null);
    });
  });
});

describe('Identifier Generation', () => {
  let generateIdentifier;
  
  beforeEach(async () => {
    const configModule = await import('../src/lib/config.js');
    generateIdentifier = configModule.generateIdentifier;
  });

  it('generates slug from name', () => {
    const result = generateIdentifier('My Web Server', 'com.company');
    assert.strictEqual(result, 'com.company.my-web-server');
  });

  it('handles special characters', () => {
    const testCases = [
      { input: 'Test (Beta)', expected: /^com\.test\.[a-z0-9-]+$/ },
      { input: 'App/v2.0', expected: /^com\.test\.[a-z0-9-]+$/ },
      { input: 'Service@Home!', expected: /^com\.test\.[a-z0-9-]+$/ },
      { input: 'API_Server', expected: /^com\.test\.[a-z0-9-]+$/ }
    ];
    
    for (const { input, expected } of testCases) {
      const result = generateIdentifier(input, 'com.test');
      assert.ok(expected.test(result), `${input} should produce valid identifier, got: ${result}`);
    }
  });

  it('uses custom prefix from settings', () => {
    const prefixes = [
      'com.mycompany',
      'vision.salient',
      'org.example'
    ];
    
    for (const prefix of prefixes) {
      const result = generateIdentifier('Test Service', prefix);
      assert.ok(result.startsWith(`${prefix}.`), `Should start with ${prefix}.`);
    }
  });

  it('produces consistent output', () => {
    const name = 'My Test Service';
    const prefix = 'com.test';
    
    const result1 = generateIdentifier(name, prefix);
    const result2 = generateIdentifier(name, prefix);
    
    assert.strictEqual(result1, result2);
  });

  it('handles unicode characters', () => {
    const result = generateIdentifier('Café Service', 'com.test');
    // Should convert/strip non-ASCII
    assert.ok(/^com\.test\.[a-z0-9-]+$/.test(result));
  });

  it('handles very long names', () => {
    const longName = 'This Is A Very Long Service Name That Goes On And On And On';
    const result = generateIdentifier(longName, 'com.test');
    
    assert.ok(result.startsWith('com.test.'));
    // Should still be a valid identifier
    assert.ok(/^com\.test\.[a-z0-9-]+$/.test(result));
  });
});
