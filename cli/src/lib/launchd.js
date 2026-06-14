import { execSync, spawn } from 'child_process';
import { unlinkSync, existsSync, mkdirSync } from 'fs';
import { join } from 'path';
import { loadConfig, expandPath } from './config.js';
import {
  generatePlistFromService,
  writePlistAtomic,
  normalizeServiceConfig
} from './plist-from-json.js';

/**
 * Get the current user's UID for launchctl commands
 */
function getUid() {
  return process.getuid();
}

/**
 * Generate and write plist for a service
 * @param {Object} service - Service configuration
 * @param {Object} settings - Global settings
 * @returns {Object} - { sourcePath, destPath }
 */
export function generateAndWritePlist(service, settings) {
  const plistDir = expandPath(settings.plistDir);
  const logDir = expandPath(settings.logDir);
  const launchAgentsDir = expandPath(settings.launchAgentsDir);

  // Ensure directories exist
  if (!existsSync(plistDir)) {
    mkdirSync(plistDir, { recursive: true });
  }
  if (!existsSync(logDir)) {
    mkdirSync(logDir, { recursive: true });
  }

  // Normalize service config and expand paths
  const normalizedService = normalizeServiceConfig({
    ...service,
    path: expandPath(service.path)
  }, settings);

  // Generate plist XML using the library
  const plistContent = generatePlistFromService(normalizedService, {
    logDir: expandPath(settings.logDir),
    nodePath: settings.nodePath
  });

  // Write to both locations atomically
  const sourcePath = join(plistDir, `${service.identifier}.plist`);
  const destPath = join(launchAgentsDir, `${service.identifier}.plist`);

  writePlistAtomic(plistContent, sourcePath);
  writePlistAtomic(plistContent, destPath);

  return { sourcePath, destPath, plistContent };
}

/**
 * Install a service to launchd using modern bootstrap
 * Generates plist and loads into launchd
 */
export function installService(service) {
  const config = loadConfig();
  const { settings } = config;

  // Generate and write plist
  const { sourcePath, destPath } = generateAndWritePlist(service, settings);

  // Use modern launchctl bootstrap
  const uid = getUid();

  try {
    // First try to bootout if already loaded (ignore errors)
    try {
      execSync(`launchctl bootout gui/${uid}/${service.identifier} 2>/dev/null`, { stdio: 'ignore' });
    } catch (err) {
      // Ignore - service might not be loaded
    }

    // Bootstrap the service
    execSync(`launchctl bootstrap gui/${uid} "${destPath}"`, { stdio: 'pipe' });
  } catch (err) {
    // Fallback to deprecated load if bootstrap fails (older macOS)
    try {
      execSync(`launchctl unload "${destPath}" 2>/dev/null || true`, { stdio: 'ignore' });
      execSync(`launchctl load "${destPath}"`, { stdio: 'pipe' });
    } catch (fallbackErr) {
      throw new Error(`Failed to load service: ${fallbackErr.message}`);
    }
  }

  return { sourcePath, destPath };
}

/**
 * Uninstall a service from launchd using modern bootout
 */
export function uninstallService(service) {
  const config = loadConfig();
  const { settings } = config;
  const uid = getUid();

  const launchAgentsDir = expandPath(settings.launchAgentsDir);
  const plistDir = expandPath(settings.plistDir);
  const destPath = join(launchAgentsDir, `${service.identifier}.plist`);
  const sourcePath = join(plistDir, `${service.identifier}.plist`);

  // Stop and bootout using modern command
  try {
    execSync(`launchctl bootout gui/${uid}/${service.identifier} 2>/dev/null`, { stdio: 'ignore' });
  } catch (err) {
    // Fallback to deprecated unload
    try {
      execSync(`launchctl stop "${service.identifier}" 2>/dev/null || true`, { stdio: 'ignore' });
      execSync(`launchctl unload "${destPath}" 2>/dev/null || true`, { stdio: 'ignore' });
    } catch (fallbackErr) {
      // Ignore errors during unload
    }
  }

  // Remove plist from LaunchAgents
  if (existsSync(destPath)) {
    unlinkSync(destPath);
  }

  // Also remove from plistDir if it exists
  if (existsSync(sourcePath)) {
    unlinkSync(sourcePath);
  }

  return true;
}

/**
 * Get the status of a service
 */
export function getServiceStatus(identifier) {
  try {
    const output = execSync(`launchctl list "${identifier}" 2>&1`, { encoding: 'utf-8' });

    // Parse PID
    const pidMatch = output.match(/"PID"\s*=\s*(\d+)/);
    const pid = pidMatch ? parseInt(pidMatch[1], 10) : null;

    // Parse exit status
    const exitMatch = output.match(/"LastExitStatus"\s*=\s*(\d+)/);
    const exitStatus = exitMatch ? parseInt(exitMatch[1], 10) : null;

    return {
      loaded: true,
      running: pid !== null,
      pid,
      exitStatus
    };
  } catch (err) {
    // Service not found
    return {
      loaded: false,
      running: false,
      pid: null,
      exitStatus: null
    };
  }
}

/**
 * Start a service
 * Generates plist if needed, then loads into launchd
 */
export function startService(identifier, service = null) {
  const uid = getUid();
  const config = loadConfig();
  const { settings } = config;

  try {
    const status = getServiceStatus(identifier);

    // If we have a service object, regenerate plist (ensures latest config)
    if (service) {
      const { destPath } = generateAndWritePlist(service, settings);

      if (!status.loaded) {
        // Bootstrap the service
        try {
          execSync(`launchctl bootstrap gui/${uid} "${destPath}"`, { stdio: 'pipe' });
        } catch (err) {
          // Fallback to load
          execSync(`launchctl load "${destPath}"`, { stdio: 'pipe' });
        }
      } else {
        // Already loaded, kickstart to apply changes
        try {
          execSync(`launchctl kickstart -k gui/${uid}/${identifier}`, { stdio: 'pipe' });
        } catch (err) {
          // Fallback to stop/start
          execSync(`launchctl stop "${identifier}"`, { stdio: 'ignore' });
          execSync(`launchctl start "${identifier}"`, { stdio: 'pipe' });
        }
      }
    } else {
      // No service object - just start using existing plist
      const launchAgentsDir = expandPath(settings.launchAgentsDir);
      const plistPath = join(launchAgentsDir, `${identifier}.plist`);

      if (!status.loaded) {
        if (existsSync(plistPath)) {
          try {
            execSync(`launchctl bootstrap gui/${uid} "${plistPath}"`, { stdio: 'pipe' });
          } catch (err) {
            execSync(`launchctl load "${plistPath}"`, { stdio: 'pipe' });
          }
        } else {
          throw new Error(`Plist not found: ${plistPath}. Use 'sm start <name>' with a configured service.`);
        }
      } else {
        execSync(`launchctl start "${identifier}"`, { stdio: 'pipe' });
      }
    }

    return true;
  } catch (err) {
    throw new Error(`Failed to start service: ${err.message}`);
  }
}

/**
 * Stop a service using modern bootout
 * Uses bootout to truly stop (prevents KeepAlive from restarting)
 */
export function stopService(identifier, removePlist = false) {
  const uid = getUid();

  try {
    // Get PID before stopping
    const status = getServiceStatus(identifier);
    const pid = status.pid;

    // Use modern bootout (this unloads and prevents KeepAlive restart)
    try {
      execSync(`launchctl bootout gui/${uid}/${identifier}`, { stdio: 'pipe' });
    } catch (err) {
      // Fallback: try stop then unload
      const config = loadConfig();
      const { settings } = config;
      const launchAgentsDir = expandPath(settings.launchAgentsDir);
      const plistPath = join(launchAgentsDir, `${identifier}.plist`);

      try {
        execSync(`launchctl stop "${identifier}"`, { stdio: 'ignore' });
        execSync(`launchctl unload "${plistPath}"`, { stdio: 'ignore' });
      } catch (fallbackErr) {
        // Continue even if these fail
      }
    }

    // Kill PID directly as backup if still running
    if (pid) {
      try {
        execSync(`kill ${pid}`, { stdio: 'ignore' });
      } catch (err) {
        // Process might already be dead, ignore
      }
    }

    // Optionally remove plist (will be regenerated on next start)
    if (removePlist) {
      const config = loadConfig();
      const { settings } = config;
      const launchAgentsDir = expandPath(settings.launchAgentsDir);
      const plistPath = join(launchAgentsDir, `${identifier}.plist`);

      if (existsSync(plistPath)) {
        unlinkSync(plistPath);
      }
    }

    return true;
  } catch (err) {
    throw new Error(`Failed to stop service: ${err.message}`);
  }
}

/**
 * Restart a service using kickstart
 */
export function restartService(identifier, service = null) {
  const uid = getUid();

  // If we have a service object, regenerate plist and kickstart
  if (service) {
    const config = loadConfig();
    const { settings } = config;
    generateAndWritePlist(service, settings);
  }

  // Try modern kickstart first
  try {
    execSync(`launchctl kickstart -k gui/${uid}/${identifier}`, { stdio: 'pipe' });
    return true;
  } catch (err) {
    // Fallback: stop then start
    const status = getServiceStatus(identifier);
    const pid = status.pid;

    try {
      execSync(`launchctl stop "${identifier}"`, { stdio: 'ignore' });
    } catch (stopErr) {
      // Continue even if stop fails
    }

    if (pid) {
      try {
        execSync(`kill ${pid}`, { stdio: 'ignore' });
      } catch (killErr) {
        // Process might already be dead
      }
    }

    // Small delay before starting
    execSync('sleep 1');
    startService(identifier, service);
    return true;
  }
}

/**
 * Get all launchd services matching our prefix
 */
export function getAllManagedServices() {
  const config = loadConfig();
  const prefix = config.settings.identifierPrefix;

  try {
    const output = execSync('launchctl list', { encoding: 'utf-8' });
    const services = [];

    for (const line of output.split('\n')) {
      if (line.includes(prefix)) {
        const parts = line.trim().split(/\s+/);
        if (parts.length >= 3) {
          const [pid, exitStatus, identifier] = parts;
          services.push({
            identifier,
            pid: pid === '-' ? null : parseInt(pid, 10),
            exitStatus: parseInt(exitStatus, 10),
            running: pid !== '-' && pid !== '0'
          });
        }
      }
    }

    return services;
  } catch (err) {
    return [];
  }
}

// Re-export plist generation for testing (doesn't write to disk)
export { generatePlistFromService as generatePlistXml } from './plist-from-json.js';

/**
 * Generate plist XML without writing to disk (for backward compatibility and testing)
 * @param {Object} service - Service configuration
 * @param {Object} settings - Global settings with logDir and nodePath
 * @returns {string} - Plist XML string
 */
export function generatePlist(service, settings) {
  // Use the library function directly (no file writing)
  return generatePlistFromService(service, {
    logDir: settings.logDir,
    nodePath: settings.nodePath
  });
}
