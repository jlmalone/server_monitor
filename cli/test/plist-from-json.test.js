import { describe, it, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert';
import { readFileSync, writeFileSync, unlinkSync, existsSync, mkdirSync, rmSync, readdirSync } from 'fs';
import { join } from 'path';
import { tmpdir, homedir } from 'os';
import { randomBytes } from 'crypto';
import {
  generatePlistFromService,
  escapeXml,
  extractShortName,
  writePlistAtomic,
  extractUnknownKeys,
  normalizeServiceConfig
} from '../src/lib/plist-from-json.js';

describe('plist-from-json library', () => {

  describe('escapeXml()', () => {
    it('should escape ampersand', () => {
      assert.strictEqual(escapeXml('test & value'), 'test &amp; value');
    });

    it('should escape less than', () => {
      assert.strictEqual(escapeXml('a < b'), 'a &lt; b');
    });

    it('should escape greater than', () => {
      assert.strictEqual(escapeXml('a > b'), 'a &gt; b');
    });

    it('should escape double quotes', () => {
      assert.strictEqual(escapeXml('test "quoted"'), 'test &quot;quoted&quot;');
    });

    it('should escape single quotes', () => {
      assert.strictEqual(escapeXml("test 'quoted'"), 'test &apos;quoted&apos;');
    });

    it('should handle all special characters together', () => {
      const input = '<tag attr="val\'ue">test & data</tag>';
      const expected = '&lt;tag attr=&quot;val&apos;ue&quot;&gt;test &amp; data&lt;/tag&gt;';
      assert.strictEqual(escapeXml(input), expected);
    });

    it('should handle null input', () => {
      assert.strictEqual(escapeXml(null), '');
    });

    it('should handle undefined input', () => {
      assert.strictEqual(escapeXml(undefined), '');
    });

    it('should convert numbers to string', () => {
      assert.strictEqual(escapeXml(123), '123');
    });
  });

  describe('extractShortName()', () => {
    it('should extract last component of identifier', () => {
      assert.strictEqual(extractShortName('com.servermonitor.my-app'), 'my-app');
    });

    it('should handle single component', () => {
      assert.strictEqual(extractShortName('myapp'), 'myapp');
    });

    it('should handle multiple dots', () => {
      assert.strictEqual(extractShortName('vision.salient.redo-https'), 'redo-https');
    });
  });

  describe('generatePlistFromService()', () => {
    it('generates valid XML from minimal service', () => {
      const service = {
        name: 'Test App',
        identifier: 'com.test.app',
        path: '/tmp/test',
        command: ['npm', 'start'],
        port: 3000,
        enabled: true
      };
      const settings = { logDir: '/var/log' };

      const plist = generatePlistFromService(service, settings);

      assert.ok(plist.includes('<?xml version="1.0" encoding="UTF-8"?>'));
      assert.ok(plist.includes('<!DOCTYPE plist PUBLIC'));
      assert.ok(plist.includes('<plist version="1.0">'));
      assert.ok(plist.includes('<key>Label</key>'));
      assert.ok(plist.includes('<string>com.test.app</string>'));
    });

    it('generates valid XML with all fields', () => {
      const service = {
        identifier: 'com.test.fullapp',
        name: 'Full App',
        path: '/usr/local/app',
        command: ['node', 'server.js', '--port', '8080'],
        enabled: true,
        keepAlive: { SuccessfulExit: false },
        throttleInterval: 15,
        environmentVariables: {
          NODE_ENV: 'production',
          PATH: '/usr/local/bin:/usr/bin'
        },
        extraKeys: {
          Nice: 5
        }
      };
      const settings = { logDir: '/var/log/app' };

      const plist = generatePlistFromService(service, settings);

      assert.ok(plist.includes('<key>Label</key>'));
      assert.ok(plist.includes('<string>com.test.fullapp</string>'));
      assert.ok(plist.includes('<key>WorkingDirectory</key>'));
      assert.ok(plist.includes('<string>/usr/local/app</string>'));
      assert.ok(plist.includes('<key>ProgramArguments</key>'));
      assert.ok(plist.includes('<string>node</string>'));
      assert.ok(plist.includes('<string>server.js</string>'));
      assert.ok(plist.includes('<key>RunAtLoad</key>'));
      assert.ok(plist.includes('<key>KeepAlive</key>'));
      assert.ok(plist.includes('<key>SuccessfulExit</key>'));
      assert.ok(plist.includes('<key>ThrottleInterval</key>'));
      assert.ok(plist.includes('<integer>15</integer>'));
      assert.ok(plist.includes('<key>EnvironmentVariables</key>'));
      assert.ok(plist.includes('<key>NODE_ENV</key>'));
      assert.ok(plist.includes('<string>production</string>'));
      assert.ok(plist.includes('<key>StandardOutPath</key>'));
      assert.ok(plist.includes('/var/log/app/fullapp.log'));
      assert.ok(plist.includes('<key>StandardErrorPath</key>'));
      assert.ok(plist.includes('/var/log/app/fullapp.error.log'));
    });

    it('escapes XML special characters in paths', () => {
      const service = {
        identifier: 'com.test.special',
        path: '/path/with <special> & "chars"',
        command: ['echo', 'test<>&"\''],
        enabled: true
      };
      const settings = { logDir: '/var/log' };

      const plist = generatePlistFromService(service, settings);

      assert.ok(plist.includes('&lt;special&gt;'));
      assert.ok(plist.includes('&amp;'));
      assert.ok(plist.includes('&quot;'));
      assert.ok(plist.includes('&apos;'));
    });

    it('handles command as string', () => {
      const service = {
        identifier: 'com.test.stringcmd',
        path: '/test',
        command: 'npm run start:dev --port 3000',
        enabled: true
      };
      const settings = { logDir: '/var/log' };

      const plist = generatePlistFromService(service, settings);

      assert.ok(plist.includes('<string>npm</string>'));
      assert.ok(plist.includes('<string>run</string>'));
      assert.ok(plist.includes('<string>start:dev</string>'));
      assert.ok(plist.includes('<string>--port</string>'));
      assert.ok(plist.includes('<string>3000</string>'));
    });

    it('sets correct environment variables from settings.nodePath', () => {
      const service = {
        identifier: 'com.test.nodepath',
        path: '/test',
        command: ['node', 'app.js'],
        enabled: true
      };
      const settings = {
        logDir: '/var/log',
        nodePath: '/opt/node/20/bin/node'
      };

      const plist = generatePlistFromService(service, settings);

      assert.ok(plist.includes('<key>EnvironmentVariables</key>'));
      assert.ok(plist.includes('<key>PATH</key>'));
      assert.ok(plist.includes('/opt/node/20/bin'));
    });

    it('does not override existing PATH in environmentVariables', () => {
      const service = {
        identifier: 'com.test.existingpath',
        path: '/test',
        command: ['node', 'app.js'],
        environmentVariables: { PATH: '/custom/bin' },
        enabled: true
      };
      const settings = {
        logDir: '/var/log',
        nodePath: '/opt/node/bin/node'
      };

      const plist = generatePlistFromService(service, settings);

      assert.ok(plist.includes('<string>/custom/bin</string>'));
      assert.ok(!plist.includes('/opt/node/bin'));
    });

    it('configures logging paths correctly', () => {
      const service = {
        identifier: 'com.servermonitor.web-server',
        path: '/app',
        command: ['node', 'index.js'],
        enabled: true
      };
      const settings = { logDir: '/var/log/services' };

      const plist = generatePlistFromService(service, settings);

      assert.ok(plist.includes('<key>StandardOutPath</key>'));
      assert.ok(plist.includes('<string>/var/log/services/web-server.log</string>'));
      assert.ok(plist.includes('<key>StandardErrorPath</key>'));
      assert.ok(plist.includes('<string>/var/log/services/web-server.error.log</string>'));
    });

    it('respects keepAlive: true', () => {
      const service = {
        identifier: 'com.test.keepalive-true',
        path: '/test',
        command: ['node', 'app.js'],
        keepAlive: true,
        enabled: true
      };
      const settings = { logDir: '/var/log' };

      const plist = generatePlistFromService(service, settings);

      // Should have <key>KeepAlive</key> followed by <true/>
      const keepAliveIdx = plist.indexOf('<key>KeepAlive</key>');
      assert.ok(keepAliveIdx > -1);
      const afterKeepAlive = plist.substring(keepAliveIdx);
      assert.ok(afterKeepAlive.includes('<true/>'));
    });

    it('respects keepAlive: false', () => {
      const service = {
        identifier: 'com.test.keepalive-false',
        path: '/test',
        command: ['node', 'app.js'],
        keepAlive: false,
        enabled: true
      };
      const settings = { logDir: '/var/log' };

      const plist = generatePlistFromService(service, settings);

      const keepAliveIdx = plist.indexOf('<key>KeepAlive</key>');
      assert.ok(keepAliveIdx > -1);
      const afterKeepAlive = plist.substring(keepAliveIdx, keepAliveIdx + 100);
      assert.ok(afterKeepAlive.includes('<false/>'));
    });

    it('respects keepAlive: {SuccessfulExit: false}', () => {
      const service = {
        identifier: 'com.test.keepalive-dict',
        path: '/test',
        command: ['node', 'app.js'],
        keepAlive: { SuccessfulExit: false },
        enabled: true
      };
      const settings = { logDir: '/var/log' };

      const plist = generatePlistFromService(service, settings);

      assert.ok(plist.includes('<key>KeepAlive</key>'));
      assert.ok(plist.includes('<key>SuccessfulExit</key>'));
      assert.ok(plist.includes('<false/>'));
    });

    it('defaults keepAlive to true when undefined', () => {
      const service = {
        identifier: 'com.test.keepalive-default',
        path: '/test',
        command: ['node', 'app.js'],
        enabled: true
      };
      const settings = { logDir: '/var/log' };

      const plist = generatePlistFromService(service, settings);

      const keepAliveIdx = plist.indexOf('<key>KeepAlive</key>');
      assert.ok(keepAliveIdx > -1);
      const afterKeepAlive = plist.substring(keepAliveIdx, keepAliveIdx + 50);
      assert.ok(afterKeepAlive.includes('<true/>'));
    });

    it('respects enabled: false (RunAtLoad)', () => {
      const service = {
        identifier: 'com.test.disabled',
        path: '/test',
        command: ['node', 'app.js'],
        enabled: false
      };
      const settings = { logDir: '/var/log' };

      const plist = generatePlistFromService(service, settings);

      assert.ok(plist.includes('<key>RunAtLoad</key>'));
      const runAtLoadIdx = plist.indexOf('<key>RunAtLoad</key>');
      const afterRunAtLoad = plist.substring(runAtLoadIdx, runAtLoadIdx + 50);
      assert.ok(afterRunAtLoad.includes('<false/>'));
    });

    it('throws error when identifier is missing', () => {
      const service = {
        path: '/test',
        command: ['node', 'app.js'],
        enabled: true
      };
      const settings = { logDir: '/var/log' };

      assert.throws(
        () => generatePlistFromService(service, settings),
        /Service must have an identifier/
      );
    });

    it('throws error when command is missing', () => {
      const service = {
        identifier: 'com.test.nocmd',
        path: '/test',
        enabled: true
      };
      const settings = { logDir: '/var/log' };

      assert.throws(
        () => generatePlistFromService(service, settings),
        /Service must have a command/
      );
    });

    it('handles service without path (WorkingDirectory omitted)', () => {
      const service = {
        identifier: 'com.test.nopath',
        command: ['echo', 'hello'],
        enabled: true
      };
      const settings = { logDir: '/var/log' };

      const plist = generatePlistFromService(service, settings);

      // Should not include WorkingDirectory
      assert.ok(!plist.includes('<key>WorkingDirectory</key>'));
    });

    it('handles extraKeys with nested objects', () => {
      const service = {
        identifier: 'com.test.extrakeys',
        path: '/test',
        command: ['node', 'app.js'],
        extraKeys: {
          Nice: 10,
          StartCalendarInterval: {
            Hour: 9,
            Minute: 0
          },
          AbandonProcessGroup: true
        },
        enabled: true
      };
      const settings = { logDir: '/var/log' };

      const plist = generatePlistFromService(service, settings);

      assert.ok(plist.includes('<key>Nice</key>'));
      assert.ok(plist.includes('<integer>10</integer>'));
      assert.ok(plist.includes('<key>StartCalendarInterval</key>'));
      assert.ok(plist.includes('<key>Hour</key>'));
      assert.ok(plist.includes('<integer>9</integer>'));
      assert.ok(plist.includes('<key>AbandonProcessGroup</key>'));
      assert.ok(plist.includes('<true/>'));
    });

    it('handles extraKeys with arrays', () => {
      const service = {
        identifier: 'com.test.arraykey',
        path: '/test',
        command: ['node', 'app.js'],
        extraKeys: {
          WatchPaths: ['/path/one', '/path/two']
        },
        enabled: true
      };
      const settings = { logDir: '/var/log' };

      const plist = generatePlistFromService(service, settings);

      assert.ok(plist.includes('<key>WatchPaths</key>'));
      assert.ok(plist.includes('<string>/path/one</string>'));
      assert.ok(plist.includes('<string>/path/two</string>'));
    });

    it('uses default logDir when not specified', () => {
      const service = {
        identifier: 'com.test.defaultlog',
        path: '/test',
        command: ['node', 'app.js'],
        enabled: true
      };
      const settings = {}; // No logDir

      const plist = generatePlistFromService(service, settings);

      assert.ok(plist.includes('<string>/var/log/defaultlog.log</string>'));
    });
  });

  describe('writePlistAtomic()', () => {
    let tempDir;
    
    beforeEach(() => {
      tempDir = join(tmpdir(), `plist-test-${randomBytes(8).toString('hex')}`);
      mkdirSync(tempDir, { recursive: true });
    });
    
    afterEach(() => {
      if (existsSync(tempDir)) {
        rmSync(tempDir, { recursive: true, force: true });
      }
    });

    it('writes content to file', () => {
      const content = '<?xml version="1.0"?><plist><dict></dict></plist>';
      const destPath = join(tempDir, 'test.plist');

      const result = writePlistAtomic(content, destPath);

      assert.strictEqual(result, true);
      assert.ok(existsSync(destPath));
      assert.strictEqual(readFileSync(destPath, 'utf-8'), content);
    });

    it('overwrites existing file', () => {
      const destPath = join(tempDir, 'existing.plist');
      writeFileSync(destPath, 'old content');
      
      const newContent = 'new content';
      writePlistAtomic(newContent, destPath);

      assert.strictEqual(readFileSync(destPath, 'utf-8'), newContent);
    });

    it('does not leave temp files on success', () => {
      const content = 'test content';
      const destPath = join(tempDir, 'clean.plist');
      
      writePlistAtomic(content, destPath);
      
      const files = readdirSync(tempDir);
      // Should only have the destination file, no temp files
      const tempFiles = files.filter(f => f.startsWith('.plist-') && f.endsWith('.tmp'));
      assert.strictEqual(tempFiles.length, 0, 'Should have no temp files');
      assert.ok(files.includes('clean.plist'), 'Should have destination file');
    });

    it('throws error on permission denied', () => {
      // This test attempts to write to a protected path
      // Skip if running as root
      if (process.getuid && process.getuid() === 0) {
        return;
      }
      
      const content = 'test';
      const destPath = '/root/impossible/path.plist';

      assert.throws(
        () => writePlistAtomic(content, destPath),
        /EACCES|ENOENT|EPERM/
      );
    });
  });

  describe('normalizeServiceConfig()', () => {
    it('converts healthCheckURL to healthCheck', () => {
      const service = {
        identifier: 'com.test.app',
        name: 'Test',
        healthCheckURL: 'http://localhost:3000/health'
      };
      const settings = { identifierPrefix: 'com.test' };

      const normalized = normalizeServiceConfig(service, settings);

      assert.strictEqual(normalized.healthCheck, 'http://localhost:3000/health');
      assert.ok(!('healthCheckURL' in normalized));
    });

    it('does not overwrite existing healthCheck', () => {
      const service = {
        identifier: 'com.test.app',
        healthCheck: 'http://localhost:3000/health',
        healthCheckURL: 'http://localhost:3000/old'
      };
      const settings = { identifierPrefix: 'com.test' };

      const normalized = normalizeServiceConfig(service, settings);

      assert.strictEqual(normalized.healthCheck, 'http://localhost:3000/health');
    });

    it('generates identifier from name if missing', () => {
      const service = {
        name: 'My Test App',
        command: ['npm', 'start']
      };
      const settings = { identifierPrefix: 'com.mycompany' };

      const normalized = normalizeServiceConfig(service, settings);

      assert.strictEqual(normalized.identifier, 'com.mycompany.my-test-app');
    });

    it('handles special characters in name for identifier generation', () => {
      const service = {
        name: 'Test App (v2.0) - Beta!',
        command: ['npm', 'start']
      };
      const settings = { identifierPrefix: 'com.test' };

      const normalized = normalizeServiceConfig(service, settings);

      // Should only contain lowercase letters, numbers, and hyphens
      assert.ok(/^com\.test\.[a-z0-9-]+$/.test(normalized.identifier));
      assert.ok(!normalized.identifier.includes('('));
      assert.ok(!normalized.identifier.includes(')'));
      assert.ok(!normalized.identifier.includes('!'));
    });

    it('removes leading/trailing hyphens from generated slug', () => {
      const service = {
        name: '---Test---',
        command: ['npm', 'start']
      };
      const settings = { identifierPrefix: 'com.test' };

      const normalized = normalizeServiceConfig(service, settings);

      assert.ok(!normalized.identifier.endsWith('-'));
      assert.ok(!normalized.identifier.split('.').pop().startsWith('-'));
    });

    it('preserves existing identifier', () => {
      const service = {
        identifier: 'com.custom.identifier',
        name: 'Test App',
        command: ['npm', 'start']
      };
      const settings = { identifierPrefix: 'com.test' };

      const normalized = normalizeServiceConfig(service, settings);

      assert.strictEqual(normalized.identifier, 'com.custom.identifier');
    });

    it('returns copy of service (no mutation)', () => {
      const service = {
        identifier: 'com.test.app',
        name: 'Test'
      };
      const settings = { identifierPrefix: 'com.test' };

      const normalized = normalizeServiceConfig(service, settings);

      assert.notStrictEqual(normalized, service);
      service.name = 'Modified';
      assert.strictEqual(normalized.name, 'Test');
    });
  });

  describe('extractUnknownKeys()', () => {
    let tempDir;
    
    beforeEach(() => {
      tempDir = join(tmpdir(), `plist-test-${randomBytes(8).toString('hex')}`);
      mkdirSync(tempDir, { recursive: true });
    });
    
    afterEach(() => {
      if (existsSync(tempDir)) {
        rmSync(tempDir, { recursive: true, force: true });
      }
    });

    it('returns empty object for non-existent file', () => {
      const result = extractUnknownKeys('/nonexistent/path.plist');
      assert.deepStrictEqual(result, {});
    });

    it('ignores known keys', () => {
      const plistContent = `<?xml version="1.0"?>
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>test</string>
    <key>ProgramArguments</key>
    <array><string>test</string></array>
    <key>WorkingDirectory</key>
    <string>/test</string>
    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>`;
      const plistPath = join(tempDir, 'known.plist');
      writeFileSync(plistPath, plistContent);

      const result = extractUnknownKeys(plistPath);

      assert.deepStrictEqual(result, {});
    });

    it('extracts unknown keys', () => {
      const plistContent = `<?xml version="1.0"?>
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>test</string>
    <key>CustomKey</key>
    <string>value</string>
    <key>AnotherUnknown</key>
    <integer>42</integer>
</dict>
</plist>`;
      const plistPath = join(tempDir, 'unknown.plist');
      writeFileSync(plistPath, plistContent);

      const result = extractUnknownKeys(plistPath);

      assert.ok('CustomKey' in result);
      assert.ok('AnotherUnknown' in result);
      assert.ok(!('Label' in result));
    });

    it('handles malformed plist gracefully', () => {
      const plistPath = join(tempDir, 'bad.plist');
      writeFileSync(plistPath, 'not valid xml');

      const result = extractUnknownKeys(plistPath);

      assert.deepStrictEqual(result, {});
    });
  });

  describe('golden fixture validation', () => {
    it('generates plist matching expected fixture', () => {
      // Load golden fixture
      const fixtureJson = readFileSync(
        join(process.cwd(), 'test/fixtures/sample-service.json'), 
        'utf-8'
      );
      const fixture = JSON.parse(fixtureJson);
      
      const expectedPlist = readFileSync(
        join(process.cwd(), 'test/fixtures/expected-plist.xml'),
        'utf-8'
      );

      // Generate plist using the library
      const generatedPlist = generatePlistFromService(fixture.service, fixture.settings);

      // Normalize whitespace for comparison
      const normalize = (s) => s.replace(/\s+/g, ' ').trim();
      assert.strictEqual(normalize(generatedPlist), normalize(expectedPlist));
    });
  });
});
