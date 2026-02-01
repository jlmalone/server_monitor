import { describe, it, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert';
import { readFileSync, writeFileSync, mkdirSync, rmSync, existsSync } from 'fs';
import { join, dirname } from 'path';
import { tmpdir } from 'os';
import { randomBytes } from 'crypto';
import { execSync } from 'child_process';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

/**
 * Helper to create a valid plist file for testing
 */
function createTestPlist(data = {}) {
  const defaults = {
    Label: 'com.test.service',
    ProgramArguments: ['node', 'index.js'],
    WorkingDirectory: '/test/path',
    RunAtLoad: true,
    KeepAlive: true,
    StandardOutPath: '/var/log/test.log',
    StandardErrorPath: '/var/log/test.error.log'
  };
  
  const merged = { ...defaults, ...data };
  
  let envXml = '';
  if (merged.EnvironmentVariables) {
    const envEntries = Object.entries(merged.EnvironmentVariables)
      .map(([k, v]) => `        <key>${k}</key>\n        <string>${v}</string>`)
      .join('\n');
    envXml = `    <key>EnvironmentVariables</key>
    <dict>
${envEntries}
    </dict>`;
    delete merged.EnvironmentVariables;
  }
  
  // Build ProgramArguments
  const args = merged.ProgramArguments.map(a => `        <string>${a}</string>`).join('\n');
  delete merged.ProgramArguments;
  
  // Build KeepAlive
  let keepAliveXml;
  if (typeof merged.KeepAlive === 'object') {
    const entries = Object.entries(merged.KeepAlive)
      .map(([k, v]) => `        <key>${k}</key>\n        <${v}/>`)
      .join('\n');
    keepAliveXml = `    <key>KeepAlive</key>
    <dict>
${entries}
    </dict>`;
  } else {
    keepAliveXml = `    <key>KeepAlive</key>
    <${merged.KeepAlive}/>`;
  }
  delete merged.KeepAlive;
  
  // Build other keys
  const otherKeys = Object.entries(merged)
    .filter(([k]) => k !== 'Label' && k !== 'WorkingDirectory' && k !== 'RunAtLoad' &&
                     k !== 'StandardOutPath' && k !== 'StandardErrorPath')
    .map(([k, v]) => {
      if (typeof v === 'number') {
        return `    <key>${k}</key>\n    <integer>${v}</integer>`;
      }
      return `    <key>${k}</key>\n    <string>${v}</string>`;
    })
    .join('\n');
  
  return `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${merged.Label}</string>
    <key>ProgramArguments</key>
    <array>
${args}
    </array>
    <key>WorkingDirectory</key>
    <string>${merged.WorkingDirectory}</string>
    <key>RunAtLoad</key>
    <${merged.RunAtLoad}/>
${keepAliveXml}
${otherKeys}
    <key>StandardOutPath</key>
    <string>${merged.StandardOutPath}</string>
    <key>StandardErrorPath</key>
    <string>${merged.StandardErrorPath}</string>
${envXml}
</dict>
</plist>`;
}

describe('Service Migration', () => {
  let tempDir;
  let sourceDir;
  let outputPath;
  
  beforeEach(() => {
    tempDir = join(tmpdir(), `migrate-test-${randomBytes(8).toString('hex')}`);
    sourceDir = join(tempDir, 'plists');
    outputPath = join(tempDir, 'services.json');
    mkdirSync(sourceDir, { recursive: true });
  });
  
  afterEach(() => {
    if (existsSync(tempDir)) {
      rmSync(tempDir, { recursive: true, force: true });
    }
  });

  describe('plist parsing', () => {
    it('parses existing plist correctly', () => {
      // Create a test plist
      const plistContent = createTestPlist({
        Label: 'com.servermonitor.test-app',
        ProgramArguments: ['node', 'server.js', '--port', '3000'],
        WorkingDirectory: '/home/user/app',
        RunAtLoad: true,
        KeepAlive: { SuccessfulExit: false },
        ThrottleInterval: 10
      });
      
      writeFileSync(join(sourceDir, 'com.servermonitor.test-app.plist'), plistContent);
      
      // Run migration
      const result = execSync(
        `node ${join(__dirname, '../src/commands/migrate.js')} --source "${sourceDir}" --output "${outputPath}" --dry-run`,
        { encoding: 'utf-8', cwd: join(__dirname, '..') }
      );
      
      // Check output
      assert.ok(result.includes('test-app.plist'), 'Should process the plist file');
      assert.ok(result.includes('com.servermonitor.test-app'), 'Should extract identifier');
    });

    it('preserves all required fields from plist', () => {
      const plistContent = createTestPlist({
        Label: 'com.test.preserved',
        ProgramArguments: ['npx', 'vite', '--port', '4000'],
        WorkingDirectory: '/projects/vite-app',
        RunAtLoad: true,
        KeepAlive: true,
        ThrottleInterval: 15,
        EnvironmentVariables: {
          NODE_ENV: 'development',
          PATH: '/usr/local/bin:/usr/bin'
        }
      });
      
      writeFileSync(join(sourceDir, 'com.test.preserved.plist'), plistContent);
      
      // Run migration (not dry run to get actual JSON)
      execSync(
        `node ${join(__dirname, '../src/commands/migrate.js')} --source "${sourceDir}" --output "${outputPath}"`,
        { encoding: 'utf-8', cwd: join(__dirname, '..') }
      );
      
      const config = JSON.parse(readFileSync(outputPath, 'utf-8'));
      const service = config.services.find(s => s.identifier === 'com.test.preserved');
      
      assert.ok(service, 'Service should be in output');
      assert.deepStrictEqual(service.command, ['npx', 'vite', '--port', '4000']);
      assert.strictEqual(service.path, '/projects/vite-app');
      assert.strictEqual(service.enabled, true);
      assert.strictEqual(service.keepAlive, true);
      assert.ok(service.environmentVariables, 'Should have env vars');
      assert.strictEqual(service.environmentVariables.NODE_ENV, 'development');
    });

    it('handles missing optional fields gracefully', () => {
      // Minimal plist without optional fields
      const minimalPlist = `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.test.minimal</string>
    <key>ProgramArguments</key>
    <array>
        <string>echo</string>
        <string>hello</string>
    </array>
</dict>
</plist>`;
      
      writeFileSync(join(sourceDir, 'com.test.minimal.plist'), minimalPlist);
      
      // Migration will warn about missing fields but should still write output
      // It exits with status 1 due to validation warnings, so we catch that
      try {
        execSync(
          `node ${join(__dirname, '../src/commands/migrate.js')} --source "${sourceDir}" --output "${outputPath}"`,
          { encoding: 'utf-8', cwd: join(__dirname, '..') }
        );
      } catch (err) {
        // Migration completes but exits with status 1 due to validation warnings
        // This is expected for minimal plists missing required fields
      }
      
      // Output should still be written
      assert.ok(existsSync(outputPath), 'Output file should be created even with warnings');
      
      const config = JSON.parse(readFileSync(outputPath, 'utf-8'));
      const service = config.services.find(s => s.identifier === 'com.test.minimal');
      
      assert.ok(service, 'Should handle minimal plist');
      assert.deepStrictEqual(service.command, ['echo', 'hello']);
    });

    it('extracts environment variables', () => {
      const plistContent = createTestPlist({
        Label: 'com.test.envvars',
        ProgramArguments: ['node', 'app.js'],
        WorkingDirectory: '/test',
        EnvironmentVariables: {
          NODE_ENV: 'production',
          DEBUG: 'app:*',
          PORT: '8080'
        }
      });
      
      writeFileSync(join(sourceDir, 'com.test.envvars.plist'), plistContent);
      
      execSync(
        `node ${join(__dirname, '../src/commands/migrate.js')} --source "${sourceDir}" --output "${outputPath}"`,
        { encoding: 'utf-8', cwd: join(__dirname, '..') }
      );
      
      const config = JSON.parse(readFileSync(outputPath, 'utf-8'));
      const service = config.services.find(s => s.identifier === 'com.test.envvars');
      
      assert.ok(service.environmentVariables);
      assert.strictEqual(service.environmentVariables.NODE_ENV, 'production');
      assert.strictEqual(service.environmentVariables.DEBUG, 'app:*');
      assert.strictEqual(service.environmentVariables.PORT, '8080');
    });

    it('converts ProgramArguments array correctly', () => {
      const plistContent = createTestPlist({
        Label: 'com.test.progargs',
        ProgramArguments: ['/usr/local/bin/node', '/app/server.js', '--config', '/etc/config.json', '-v'],
        WorkingDirectory: '/app'
      });
      
      writeFileSync(join(sourceDir, 'com.test.progargs.plist'), plistContent);
      
      execSync(
        `node ${join(__dirname, '../src/commands/migrate.js')} --source "${sourceDir}" --output "${outputPath}"`,
        { encoding: 'utf-8', cwd: join(__dirname, '..') }
      );
      
      const config = JSON.parse(readFileSync(outputPath, 'utf-8'));
      const service = config.services.find(s => s.identifier === 'com.test.progargs');
      
      assert.deepStrictEqual(service.command, [
        '/usr/local/bin/node',
        '/app/server.js',
        '--config',
        '/etc/config.json',
        '-v'
      ]);
    });

    it('preserves keepAlive dictionary format', () => {
      const plistContent = createTestPlist({
        Label: 'com.test.keepalive-dict',
        ProgramArguments: ['node', 'app.js'],
        WorkingDirectory: '/test',
        KeepAlive: { SuccessfulExit: false }
      });
      
      writeFileSync(join(sourceDir, 'com.test.keepalive-dict.plist'), plistContent);
      
      execSync(
        `node ${join(__dirname, '../src/commands/migrate.js')} --source "${sourceDir}" --output "${outputPath}"`,
        { encoding: 'utf-8', cwd: join(__dirname, '..') }
      );
      
      const config = JSON.parse(readFileSync(outputPath, 'utf-8'));
      const service = config.services.find(s => s.identifier === 'com.test.keepalive-dict');
      
      assert.ok(typeof service.keepAlive === 'object');
      assert.strictEqual(service.keepAlive.SuccessfulExit, false);
    });
  });

  describe('migration functionality', () => {
    it('processes multiple plist files', () => {
      // Create multiple plists
      for (let i = 1; i <= 3; i++) {
        const plistContent = createTestPlist({
          Label: `com.test.service-${i}`,
          ProgramArguments: ['node', `app${i}.js`],
          WorkingDirectory: `/projects/app${i}`,
          StandardOutPath: `/var/log/service${i}.log`,
          StandardErrorPath: `/var/log/service${i}.error.log`
        });
        writeFileSync(join(sourceDir, `com.test.service-${i}.plist`), plistContent);
      }
      
      execSync(
        `node ${join(__dirname, '../src/commands/migrate.js')} --source "${sourceDir}" --output "${outputPath}"`,
        { encoding: 'utf-8', cwd: join(__dirname, '..') }
      );
      
      const config = JSON.parse(readFileSync(outputPath, 'utf-8'));
      
      assert.strictEqual(config.services.length, 3);
      assert.ok(config.services.some(s => s.identifier === 'com.test.service-1'));
      assert.ok(config.services.some(s => s.identifier === 'com.test.service-2'));
      assert.ok(config.services.some(s => s.identifier === 'com.test.service-3'));
    });

    it('extracts port from command arguments', () => {
      const plistContent = createTestPlist({
        Label: 'com.test.port-extract',
        ProgramArguments: ['npx', 'vite', '--port', '4500'],
        WorkingDirectory: '/test'
      });
      
      writeFileSync(join(sourceDir, 'com.test.port-extract.plist'), plistContent);
      
      execSync(
        `node ${join(__dirname, '../src/commands/migrate.js')} --source "${sourceDir}" --output "${outputPath}"`,
        { encoding: 'utf-8', cwd: join(__dirname, '..') }
      );
      
      const config = JSON.parse(readFileSync(outputPath, 'utf-8'));
      const service = config.services.find(s => s.identifier === 'com.test.port-extract');
      
      assert.strictEqual(service.port, 4500);
    });

    it('derives name from identifier', () => {
      const plistContent = createTestPlist({
        Label: 'vision.salient.web-server-https',
        ProgramArguments: ['node', 'server.js'],
        WorkingDirectory: '/app'
      });
      
      writeFileSync(join(sourceDir, 'vision.salient.web-server-https.plist'), plistContent);
      
      execSync(
        `node ${join(__dirname, '../src/commands/migrate.js')} --source "${sourceDir}" --output "${outputPath}"`,
        { encoding: 'utf-8', cwd: join(__dirname, '..') }
      );
      
      const config = JSON.parse(readFileSync(outputPath, 'utf-8'));
      const service = config.services.find(s => s.identifier === 'vision.salient.web-server-https');
      
      // Should derive "Web Server HTTPS" from "web-server-https"
      assert.ok(service.name.toLowerCase().includes('web'));
      assert.ok(service.name.toLowerCase().includes('server'));
      assert.ok(service.name.toUpperCase().includes('HTTPS'));
    });

    it('skips non-plist files', () => {
      // Create a plist and a non-plist file
      const plistContent = createTestPlist({
        Label: 'com.test.valid',
        ProgramArguments: ['node', 'app.js'],
        WorkingDirectory: '/test'
      });
      
      writeFileSync(join(sourceDir, 'com.test.valid.plist'), plistContent);
      writeFileSync(join(sourceDir, 'readme.txt'), 'Not a plist');
      writeFileSync(join(sourceDir, 'config.json'), '{}');
      
      execSync(
        `node ${join(__dirname, '../src/commands/migrate.js')} --source "${sourceDir}" --output "${outputPath}"`,
        { encoding: 'utf-8', cwd: join(__dirname, '..') }
      );
      
      const config = JSON.parse(readFileSync(outputPath, 'utf-8'));
      
      // Should only have the one valid plist
      assert.strictEqual(config.services.length, 1);
      assert.strictEqual(config.services[0].identifier, 'com.test.valid');
    });

    it('creates proper version 2.0.0 config structure', () => {
      const plistContent = createTestPlist({
        Label: 'com.test.version',
        ProgramArguments: ['node', 'app.js'],
        WorkingDirectory: '/test',
        StandardOutPath: '/custom/logs/test.log',
        StandardErrorPath: '/custom/logs/test.error.log'
      });
      
      writeFileSync(join(sourceDir, 'com.test.version.plist'), plistContent);
      
      execSync(
        `node ${join(__dirname, '../src/commands/migrate.js')} --source "${sourceDir}" --output "${outputPath}"`,
        { encoding: 'utf-8', cwd: join(__dirname, '..') }
      );
      
      const config = JSON.parse(readFileSync(outputPath, 'utf-8'));
      
      assert.strictEqual(config.version, '2.0.0');
      assert.ok(config.settings);
      assert.ok(config.settings.logDir);
      assert.ok(config.settings.identifierPrefix);
      assert.ok(Array.isArray(config.services));
    });

    it('reports errors for invalid plist files', () => {
      // Create an invalid plist
      writeFileSync(join(sourceDir, 'invalid.plist'), 'not valid xml');
      
      // Should still run but report error
      const result = execSync(
        `node ${join(__dirname, '../src/commands/migrate.js')} --source "${sourceDir}" --output "${outputPath}" 2>&1 || true`,
        { encoding: 'utf-8', cwd: join(__dirname, '..') }
      );
      
      assert.ok(result.includes('✗') || result.includes('failed') || result.includes('Error'));
    });

    it('dry-run does not write output file', () => {
      const plistContent = createTestPlist({
        Label: 'com.test.dryrun',
        ProgramArguments: ['node', 'app.js'],
        WorkingDirectory: '/test'
      });
      
      writeFileSync(join(sourceDir, 'com.test.dryrun.plist'), plistContent);
      
      execSync(
        `node ${join(__dirname, '../src/commands/migrate.js')} --source "${sourceDir}" --output "${outputPath}" --dry-run`,
        { encoding: 'utf-8', cwd: join(__dirname, '..') }
      );
      
      assert.ok(!existsSync(outputPath), 'Should not create output file in dry-run');
    });
  });

  describe('merging with existing config', () => {
    it('preserves port and healthCheck from existing config', () => {
      // Create existing config with port and healthCheck
      const existingConfig = {
        version: '2.0.0',
        settings: { logDir: '/logs', identifierPrefix: 'com.test' },
        services: [{
          identifier: 'com.test.existing',
          name: 'Existing Service',
          port: 5555,
          healthCheck: 'http://localhost:5555/health'
        }]
      };
      const existingPath = join(tempDir, 'existing.json');
      writeFileSync(existingPath, JSON.stringify(existingConfig));
      
      // Create plist for the same service (without port)
      const plistContent = createTestPlist({
        Label: 'com.test.existing',
        ProgramArguments: ['node', 'app.js'],
        WorkingDirectory: '/app'
      });
      writeFileSync(join(sourceDir, 'com.test.existing.plist'), plistContent);
      
      execSync(
        `node ${join(__dirname, '../src/commands/migrate.js')} --source "${sourceDir}" --output "${outputPath}" --existing-config "${existingPath}"`,
        { encoding: 'utf-8', cwd: join(__dirname, '..') }
      );
      
      const config = JSON.parse(readFileSync(outputPath, 'utf-8'));
      const service = config.services.find(s => s.identifier === 'com.test.existing');
      
      assert.strictEqual(service.port, 5555);
      assert.strictEqual(service.healthCheck, 'http://localhost:5555/health');
    });

    it('normalizes healthCheckURL to healthCheck', () => {
      const existingConfig = {
        version: '2.0.0',
        settings: { logDir: '/logs', identifierPrefix: 'com.test' },
        services: [{
          identifier: 'com.test.oldformat',
          name: 'Old Format Service',
          port: 3000,
          healthCheckURL: 'http://localhost:3000/api/health'
        }]
      };
      const existingPath = join(tempDir, 'existing.json');
      writeFileSync(existingPath, JSON.stringify(existingConfig));
      
      const plistContent = createTestPlist({
        Label: 'com.test.oldformat',
        ProgramArguments: ['node', 'app.js'],
        WorkingDirectory: '/app'
      });
      writeFileSync(join(sourceDir, 'com.test.oldformat.plist'), plistContent);
      
      execSync(
        `node ${join(__dirname, '../src/commands/migrate.js')} --source "${sourceDir}" --output "${outputPath}" --existing-config "${existingPath}"`,
        { encoding: 'utf-8', cwd: join(__dirname, '..') }
      );
      
      const config = JSON.parse(readFileSync(outputPath, 'utf-8'));
      const service = config.services.find(s => s.identifier === 'com.test.oldformat');
      
      // Should use healthCheck (normalized from healthCheckURL)
      assert.strictEqual(service.healthCheck, 'http://localhost:3000/api/health');
    });
  });
});
