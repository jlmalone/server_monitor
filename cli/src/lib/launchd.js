import { execSync, spawn } from 'child_process';
import { writeFileSync, unlinkSync, existsSync, mkdirSync } from 'fs';
import { join, dirname } from 'path';
import { loadConfig, expandPath } from './config.js';

/**
 * Generate a plist XML for a service
 */
export function generatePlist(service, settings) {
  const logDir = expandPath(settings.logDir);
  const workingDir = expandPath(service.path);
  
  // Ensure log directory exists
  if (!existsSync(logDir)) {
    mkdirSync(logDir, { recursive: true });
  }
  
  // Parse command - can be string or array
  const command = Array.isArray(service.command) 
    ? service.command 
    : service.command.split(/\s+/);
  
  // Build ProgramArguments XML
  const programArgs = command.map(arg => 
    `        <string>${escapeXml(arg)}</string>`
  ).join('\n');
  
  const shortName = service.identifier.split('.').pop();
  
  return `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${service.identifier}</string>
    <key>ProgramArguments</key>
    <array>
${programArgs}
    </array>
    <key>WorkingDirectory</key>
    <string>${workingDir}</string>
    <key>RunAtLoad</key>
    <${service.enabled !== false ? 'true' : 'false'}/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>${logDir}/${shortName}.log</string>
    <key>StandardErrorPath</key>
    <string>${logDir}/${shortName}.error.log</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>${dirname(settings.nodePath)}:/usr/local/bin:/usr/bin:/bin</string>
    </dict>
</dict>
</plist>`;
}

function escapeXml(str) {
  return str
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&apos;');
}

/**
 * Install a service to launchd
 */
export function installService(service) {
  const config = loadConfig();
  const { settings } = config;
  
  // Generate plist content
  const plistContent = generatePlist(service, settings);
  
  // Write to plist directory (source)
  const plistDir = expandPath(settings.plistDir);
  if (!existsSync(plistDir)) {
    mkdirSync(plistDir, { recursive: true });
  }
  const sourcePath = join(plistDir, `${service.identifier}.plist`);
  writeFileSync(sourcePath, plistContent);
  
  // Copy to LaunchAgents
  const launchAgentsDir = expandPath(settings.launchAgentsDir);
  const destPath = join(launchAgentsDir, `${service.identifier}.plist`);
  writeFileSync(destPath, plistContent);
  
  // Load into launchd
  try {
    // First try to unload if exists
    execSync(`launchctl unload "${destPath}" 2>/dev/null || true`, { stdio: 'ignore' });
    execSync(`launchctl load "${destPath}"`, { stdio: 'pipe' });
  } catch (err) {
    throw new Error(`Failed to load service: ${err.message}`);
  }
  
  return { sourcePath, destPath };
}

/**
 * Uninstall a service from launchd
 */
export function uninstallService(service) {
  const config = loadConfig();
  const { settings } = config;
  
  const launchAgentsDir = expandPath(settings.launchAgentsDir);
  const destPath = join(launchAgentsDir, `${service.identifier}.plist`);
  
  // Stop and unload
  try {
    execSync(`launchctl stop "${service.identifier}" 2>/dev/null || true`, { stdio: 'ignore' });
    execSync(`launchctl unload "${destPath}" 2>/dev/null || true`, { stdio: 'ignore' });
  } catch (err) {
    // Ignore errors during unload
  }
  
  // Remove plist from LaunchAgents
  if (existsSync(destPath)) {
    unlinkSync(destPath);
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
 */
export function startService(identifier) {
  try {
    execSync(`launchctl start "${identifier}"`, { stdio: 'pipe' });
    return true;
  } catch (err) {
    throw new Error(`Failed to start service: ${err.message}`);
  }
}

/**
 * Stop a service
 */
export function stopService(identifier) {
  try {
    execSync(`launchctl stop "${identifier}"`, { stdio: 'pipe' });
    return true;
  } catch (err) {
    throw new Error(`Failed to stop service: ${err.message}`);
  }
}

/**
 * Restart a service
 */
export function restartService(identifier) {
  stopService(identifier);
  // Small delay before starting
  execSync('sleep 1');
  startService(identifier);
  return true;
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
