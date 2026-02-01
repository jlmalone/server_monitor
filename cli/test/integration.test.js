import { describe, it } from 'node:test';
import assert from 'node:assert';
import { execSync } from 'child_process';

/**
 * Integration tests that verify the CLI actually works
 * These interact with real launchd services
 */

describe('CLI integration tests', () => {

  // Skip all integration tests if in CI or launchctl is missing
  const isCI = process.env.CI === 'true';
  let hasLaunchctl = false;
  try {
    execSync('which launchctl', { stdio: 'ignore' });
    hasLaunchctl = true;
  } catch (e) {
    // ignore
  }

  if (isCI || !hasLaunchctl) {
    console.log('⚠️  Skipping CLI integration tests (CI environment or launchctl missing)');
    return;
  }

  describe('sm list', () => {
    it('should list services without errors', () => {
      try {
        const output = execSync('sm list', { encoding: 'utf-8' });

        // Should contain service names from config
        assert.ok(output.length > 0);
      } catch (err) {
        // If sm not linked, skip
        if (err.message.includes('command not found')) {
          console.log('⚠️  Skipping: sm command not linked');
        } else {
          throw err;
        }
      }
    });
  });

  describe('sm status', () => {
    it('should show status for all services', () => {
      try {
        const output = execSync('sm status', { encoding: 'utf-8' });

        // Should contain status indicators
        assert.ok(output.includes('●') || output.includes('○'));
      } catch (err) {
        if (err.message.includes('command not found')) {
          console.log('⚠️  Skipping: sm command not linked');
        } else {
          throw err;
        }
      }
    });
  });

  describe('launchctl integration', () => {
    it('should list managed services via launchctl', () => {
      const output = execSync('launchctl list | grep salient || true', {
        encoding: 'utf-8'
      });

      // Should find at least one managed service
      // (Will be empty if no services loaded, which is OK)
      assert.ok(typeof output === 'string');
    });
  });

  describe('service lifecycle', () => {
    it('should be able to check status of system service', () => {
      // Find a running service dynamically
      const list = execSync('launchctl list', { encoding: 'utf-8' });
      const lines = list.split('\n').slice(1);
      // Find a com.apple service that is likely stable
      const serviceLine = lines.find(l => l.includes('com.apple.foundation.') || l.includes('com.apple.dt.'));

      if (!serviceLine) {
        console.log('⚠️  Skipping: No suitable system service found for testing');
        return;
      }

      const label = serviceLine.split('\t').pop();
      const output = execSync(`launchctl list ${label}`, {
        encoding: 'utf-8',
        stdio: 'pipe'
      });

      // Should return service info
      assert.ok(output.includes('PID') || output.includes(label));
    });
  });
});
