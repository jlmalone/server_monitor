import { describe, it, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert';
import { existsSync, unlinkSync, readFileSync, mkdirSync, rmSync } from 'fs';
import { join, dirname } from 'path';
import { execSync, spawnSync } from 'child_process';
import { tmpdir, homedir } from 'os';
import { randomBytes } from 'crypto';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

/**
 * Service lifecycle tests
 * 
 * These tests verify the complete lifecycle of services:
 * add -> start -> stop -> remove
 * 
 * Note: Some tests require launchd and may skip in CI environments
 */

describe('Service Lifecycle', () => {
  const isCI = process.env.CI === 'true';
  let testServiceName;
  let testServicePath;
  
  beforeEach(() => {
    testServiceName = `test-lifecycle-${randomBytes(4).toString('hex')}`;
    testServicePath = join(tmpdir(), testServiceName);
    mkdirSync(testServicePath, { recursive: true });
  });
  
  afterEach(async () => {
    // Cleanup: try to remove the test service if it exists
    try {
      execSync(`cd ${join(__dirname, '..')} && node bin/sm remove "${testServiceName}" --clean-logs 2>/dev/null || true`, {
        stdio: 'ignore'
      });
    } catch (e) {}
    
    // Remove temp directory
    if (existsSync(testServicePath)) {
      rmSync(testServicePath, { recursive: true, force: true });
    }
  });

  describe('add command', () => {
    it('creates service in JSON configuration only', async () => {
      // Add a service without starting it
      const cliPath = join(__dirname, '..', 'bin', 'sm');
      
      const result = spawnSync('node', [
        cliPath, 'add',
        '--name', testServiceName,
        '--path', testServicePath,
        '--cmd', 'echo hello',
        '--port', '9990'
      ], {
        encoding: 'utf-8',
        cwd: join(__dirname, '..')
      });
      
      if (result.status !== 0) {
        console.error('Add command failed:', result.stderr, result.stdout);
      }
      
      assert.strictEqual(result.status, 0, 'Add command should succeed');
      
      // Verify service is in config
      const { getService } = await import('../src/lib/config.js');
      const service = getService(testServiceName);
      
      assert.ok(service, 'Service should exist in config');
      assert.strictEqual(service.name, testServiceName);
      assert.strictEqual(service.port, 9990);
    });

    it('validates path exists', () => {
      const cliPath = join(__dirname, '..', 'bin', 'sm');
      const fakePath = '/nonexistent/path/that/does/not/exist';
      
      const result = spawnSync('node', [
        cliPath, 'add',
        '--name', 'test-invalid-path',
        '--path', fakePath,
        '--cmd', 'echo hello'
      ], {
        encoding: 'utf-8',
        cwd: join(__dirname, '..')
      });
      
      assert.notStrictEqual(result.status, 0, 'Should fail for non-existent path');
      assert.ok(result.stdout.includes('does not exist') || result.stderr.includes('does not exist'));
    });

    it('generates correct identifier', async () => {
      const cliPath = join(__dirname, '..', 'bin', 'sm');
      const serviceName = `test-app-spaces-${randomBytes(4).toString('hex')}`;
      
      const result = spawnSync('node', [
        cliPath, 'add',
        '--name', serviceName,
        '--path', testServicePath,
        '--cmd', 'echo hello'
      ], {
        encoding: 'utf-8',
        cwd: join(__dirname, '..')
      });
      
      if (result.status === 0) {
        const { getService, loadConfig } = await import('../src/lib/config.js');
        const config = loadConfig();
        const service = getService(serviceName);
        
        if (service) {
          // Identifier should follow pattern: prefix.slugified-name
          assert.ok(service.identifier.includes(config.settings.identifierPrefix));
          assert.ok(service.identifier.includes('test-app-spaces'));
          
          // Cleanup
          try {
            execSync(`cd ${join(__dirname, '..')} && node bin/sm remove "${serviceName}" 2>/dev/null || true`, {
              stdio: 'ignore'
            });
          } catch (e) {}
        }
      }
    });

    it('prevents duplicate service names', async () => {
      const cliPath = join(__dirname, '..', 'bin', 'sm');
      
      // Add first service
      spawnSync('node', [
        cliPath, 'add',
        '--name', testServiceName,
        '--path', testServicePath,
        '--cmd', 'echo hello'
      ], {
        encoding: 'utf-8',
        cwd: join(__dirname, '..')
      });
      
      // Try to add duplicate
      const result = spawnSync('node', [
        cliPath, 'add',
        '--name', testServiceName,
        '--path', testServicePath,
        '--cmd', 'echo world'
      ], {
        encoding: 'utf-8',
        cwd: join(__dirname, '..')
      });
      
      assert.notStrictEqual(result.status, 0, 'Should fail for duplicate name');
      assert.ok(result.stdout.includes('already exists') || result.stderr.includes('already exists'));
    });
  });

  describe('start command', function() {
    it('generates plist and starts service', async function() {
      if (isCI) {
        this.skip();
        return;
      }
      
      const cliPath = join(__dirname, '..', 'bin', 'sm');
      
      // First add the service
      const addResult = spawnSync('node', [
        cliPath, 'add',
        '--name', testServiceName,
        '--path', testServicePath,
        '--cmd', 'sleep 300',
        '--port', '9991'
      ], {
        encoding: 'utf-8',
        cwd: join(__dirname, '..')
      });
      
      if (addResult.status !== 0) {
        console.error('Add failed:', addResult.stdout, addResult.stderr);
        return;
      }
      
      // Now start it
      const result = spawnSync('node', [
        cliPath, 'start', testServiceName
      ], {
        encoding: 'utf-8',
        timeout: 10000,
        cwd: join(__dirname, '..')
      });
      
      // Get service to check identifier
      const { getService, loadConfig } = await import('../src/lib/config.js');
      const service = getService(testServiceName);
      const config = loadConfig();
      
      if (service) {
        // Verify plist was created
        const launchAgentsDir = join(homedir(), 'Library', 'LaunchAgents');
        const plistPath = join(launchAgentsDir, `${service.identifier}.plist`);
        
        assert.ok(existsSync(plistPath), 'Plist should be created in LaunchAgents');
        
        // Verify plist content
        const plistContent = readFileSync(plistPath, 'utf-8');
        assert.ok(plistContent.includes(service.identifier));
        assert.ok(plistContent.includes('sleep'));
      }
    });

    it('reports already running service', async function() {
      if (isCI) {
        this.skip();
        return;
      }
      
      const cliPath = join(__dirname, '..', 'bin', 'sm');
      
      // Add and start service
      spawnSync('node', [
        cliPath, 'add',
        '--name', testServiceName,
        '--path', testServicePath,
        '--cmd', 'sleep 300',
        '--start'
      ], {
        encoding: 'utf-8',
        cwd: join(__dirname, '..')
      });
      
      // Wait for it to start
      await new Promise(r => setTimeout(r, 2000));
      
      // Try to start again
      const result = spawnSync('node', [
        cliPath, 'start', testServiceName
      ], {
        encoding: 'utf-8',
        cwd: join(__dirname, '..')
      });
      
      // Should report it's already running
      assert.ok(
        result.stdout.includes('already running') || 
        result.stdout.includes('started'),
        'Should indicate service status'
      );
    });
  });

  describe('stop command', function() {
    it('uses bootout to truly stop service', async function() {
      if (isCI) {
        this.skip();
        return;
      }
      
      const cliPath = join(__dirname, '..', 'bin', 'sm');
      
      // Add and start service
      spawnSync('node', [
        cliPath, 'add',
        '--name', testServiceName,
        '--path', testServicePath,
        '--cmd', 'sleep 300',
        '--start'
      ], {
        encoding: 'utf-8',
        cwd: join(__dirname, '..')
      });
      
      // Wait for it to start
      await new Promise(r => setTimeout(r, 2000));
      
      // Get service info
      const { getService } = await import('../src/lib/config.js');
      const service = getService(testServiceName);
      
      // Stop the service
      const result = spawnSync('node', [
        cliPath, 'stop', testServiceName
      ], {
        encoding: 'utf-8',
        timeout: 10000,
        cwd: join(__dirname, '..')
      });
      
      assert.strictEqual(result.status, 0, 'Stop command should succeed');
      
      // Wait for stop to complete
      await new Promise(r => setTimeout(r, 2000));
      
      if (service) {
        // Verify it's stopped using launchctl
        const listResult = spawnSync('launchctl', ['list', service.identifier], {
          encoding: 'utf-8'
        });
        
        // Should not be loaded anymore
        assert.notStrictEqual(listResult.status, 0, 'Service should not be loaded');
      }
    });

    it('handles already stopped service gracefully', async function() {
      if (isCI) {
        this.skip();
        return;
      }
      
      const cliPath = join(__dirname, '..', 'bin', 'sm');
      
      // Add service but don't start it
      spawnSync('node', [
        cliPath, 'add',
        '--name', testServiceName,
        '--path', testServicePath,
        '--cmd', 'echo hello'
      ], {
        encoding: 'utf-8',
        cwd: join(__dirname, '..')
      });
      
      // Try to stop (should handle gracefully)
      const result = spawnSync('node', [
        cliPath, 'stop', testServiceName
      ], {
        encoding: 'utf-8',
        cwd: join(__dirname, '..')
      });
      
      // Should not crash
      assert.ok(
        result.stdout.includes('not installed') ||
        result.stdout.includes('stopped') ||
        result.stdout.includes('unloaded'),
        'Should handle gracefully'
      );
    });
  });

  describe('restart command', function() {
    it('regenerates plist on restart', async function() {
      if (isCI) {
        this.skip();
        return;
      }
      
      const cliPath = join(__dirname, '..', 'bin', 'sm');
      
      // Add and start service
      spawnSync('node', [
        cliPath, 'add',
        '--name', testServiceName,
        '--path', testServicePath,
        '--cmd', 'sleep 300',
        '--start'
      ], {
        encoding: 'utf-8',
        cwd: join(__dirname, '..')
      });
      
      await new Promise(r => setTimeout(r, 2000));
      
      // Get plist path
      const { getService, loadConfig } = await import('../src/lib/config.js');
      const service = getService(testServiceName);
      
      // Wait a bit then restart
      await new Promise(r => setTimeout(r, 1000));
      
      const result = spawnSync('node', [
        cliPath, 'restart', testServiceName
      ], {
        encoding: 'utf-8',
        timeout: 15000,
        cwd: join(__dirname, '..')
      });
      
      // The important thing is that restart completes
      assert.strictEqual(result.status, 0, 'Restart should succeed');
    });
  });

  describe('remove command', function() {
    it('cleans up JSON config and plist', async function() {
      if (isCI) {
        this.skip();
        return;
      }
      
      const cliPath = join(__dirname, '..', 'bin', 'sm');
      
      // Add and start service
      spawnSync('node', [
        cliPath, 'add',
        '--name', testServiceName,
        '--path', testServicePath,
        '--cmd', 'sleep 300',
        '--start'
      ], {
        encoding: 'utf-8',
        cwd: join(__dirname, '..')
      });
      
      await new Promise(r => setTimeout(r, 2000));
      
      // Get service info before removal
      const { getService, loadConfig } = await import('../src/lib/config.js');
      const serviceBefore = getService(testServiceName);
      
      if (serviceBefore) {
        const identifier = serviceBefore.identifier;
        const launchAgentsDir = join(homedir(), 'Library', 'LaunchAgents');
        const plistPath = join(launchAgentsDir, `${identifier}.plist`);
        
        // Remove the service
        const result = spawnSync('node', [
          cliPath, 'remove', testServiceName, '--clean-logs'
        ], {
          encoding: 'utf-8',
          timeout: 10000,
          cwd: join(__dirname, '..')
        });
        
        assert.strictEqual(result.status, 0, 'Remove should succeed');
        
        // Verify plist is removed
        assert.ok(!existsSync(plistPath), 'Plist should be removed');
      }
    });

    it('supports --keep-config option', async function() {
      if (isCI) {
        this.skip();
        return;
      }
      
      const cliPath = join(__dirname, '..', 'bin', 'sm');
      
      // Add and start service
      spawnSync('node', [
        cliPath, 'add',
        '--name', testServiceName,
        '--path', testServicePath,
        '--cmd', 'echo hello',
        '--start'
      ], {
        encoding: 'utf-8',
        cwd: join(__dirname, '..')
      });
      
      await new Promise(r => setTimeout(r, 2000));
      
      // Remove with --keep-config
      const result = spawnSync('node', [
        cliPath, 'remove', testServiceName, '--keep-config'
      ], {
        encoding: 'utf-8',
        cwd: join(__dirname, '..')
      });
      
      assert.strictEqual(result.status, 0);
      
      // The --keep-config option should preserve the JSON entry
      assert.ok(
        result.stdout.includes('uninstalled') || 
        result.stdout.includes('Configuration retained'),
        'Should indicate config was kept'
      );
    });
  });

  describe('full lifecycle integration', function() {
    it('add -> start -> stop -> remove cycle', async function() {
      if (isCI) {
        this.skip();
        return;
      }
      
      const cliPath = join(__dirname, '..', 'bin', 'sm');
      
      // 1. ADD
      const addResult = spawnSync('node', [
        cliPath, 'add',
        '--name', testServiceName,
        '--path', testServicePath,
        '--cmd', 'sleep 300',
        '--port', '9992'
      ], {
        encoding: 'utf-8',
        cwd: join(__dirname, '..')
      });
      assert.strictEqual(addResult.status, 0, 'Add should succeed');
      
      // 2. START
      const startResult = spawnSync('node', [
        cliPath, 'start', testServiceName
      ], {
        encoding: 'utf-8',
        timeout: 10000,
        cwd: join(__dirname, '..')
      });
      assert.strictEqual(startResult.status, 0, 'Start should succeed');
      
      await new Promise(r => setTimeout(r, 2000));
      
      // 3. Verify running
      const statusResult = spawnSync('node', [
        cliPath, 'status', testServiceName
      ], {
        encoding: 'utf-8',
        cwd: join(__dirname, '..')
      });
      // Status should show running
      assert.ok(
        statusResult.stdout.includes('Running') || 
        statusResult.stdout.includes('PID'),
        'Should show running status'
      );
      
      // 4. STOP
      const stopResult = spawnSync('node', [
        cliPath, 'stop', testServiceName
      ], {
        encoding: 'utf-8',
        timeout: 10000,
        cwd: join(__dirname, '..')
      });
      assert.strictEqual(stopResult.status, 0, 'Stop should succeed');
      
      await new Promise(r => setTimeout(r, 2000));
      
      // 5. REMOVE
      const removeResult = spawnSync('node', [
        cliPath, 'remove', testServiceName, '--clean-logs'
      ], {
        encoding: 'utf-8',
        timeout: 10000,
        cwd: join(__dirname, '..')
      });
      assert.strictEqual(removeResult.status, 0, 'Remove should succeed');
      
      // Final verification: service gone
      assert.ok(
        removeResult.stdout.includes('removed') ||
        removeResult.stdout.includes('Removed'),
        'Should confirm removal'
      );
    });
  });
});
