/**
 * plist-from-json.js
 * 
 * Generates launchd plist XML from JSON service configurations.
 * Designed for cross-platform validation - the Swift implementation
 * should produce identical output for the same inputs.
 * 
 * Modern launchctl usage (macOS 10.10+):
 *   Load:   launchctl bootstrap gui/$(id -u) /path/to/plist
 *   Unload: launchctl bootout gui/$(id -u)/service.identifier
 *   Start:  launchctl kickstart -k gui/$(id -u)/service.identifier
 *   Stop:   launchctl kill SIGTERM gui/$(id -u)/service.identifier
 * 
 * The deprecated commands (load/unload) still work but print warnings.
 */

import { writeFileSync, renameSync, existsSync, readFileSync } from 'fs';
import { dirname, join } from 'path';
import { tmpdir } from 'os';
import { randomBytes } from 'crypto';

/**
 * Escape special XML characters in a string
 * @param {string} str - String to escape
 * @returns {string} - XML-safe string
 */
export function escapeXml(str) {
  if (str === null || str === undefined) return '';
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&apos;');
}

/**
 * Generate XML for a plist value based on its type
 * @param {any} value - Value to convert
 * @param {number} indent - Indentation level
 * @returns {string} - XML representation
 */
function valueToXml(value, indent = 2) {
  const spaces = '    '.repeat(indent);
  
  if (value === true) {
    return `${spaces}<true/>`;
  }
  if (value === false) {
    return `${spaces}<false/>`;
  }
  if (typeof value === 'number') {
    if (Number.isInteger(value)) {
      return `${spaces}<integer>${value}</integer>`;
    }
    return `${spaces}<real>${value}</real>`;
  }
  if (typeof value === 'string') {
    return `${spaces}<string>${escapeXml(value)}</string>`;
  }
  if (Array.isArray(value)) {
    const items = value.map(v => valueToXml(v, indent + 1)).join('\n');
    return `${spaces}<array>\n${items}\n${spaces}</array>`;
  }
  if (typeof value === 'object' && value !== null) {
    const entries = Object.entries(value).map(([k, v]) => 
      `${spaces}    <key>${escapeXml(k)}</key>\n${valueToXml(v, indent + 1)}`
    ).join('\n');
    return `${spaces}<dict>\n${entries}\n${spaces}</dict>`;
  }
  return `${spaces}<string></string>`;
}

/**
 * Extract short name from identifier
 * e.g., "com.servermonitor.my-app" -> "my-app"
 * @param {string} identifier - Full service identifier
 * @returns {string} - Short name for log files
 */
export function extractShortName(identifier) {
  return identifier.split('.').pop();
}

/**
 * Generate launchd plist XML from service configuration
 * 
 * @param {Object} service - Service config from services.json
 * @param {string} service.identifier - Unique launchd label (e.g., "com.servermonitor.myapp")
 * @param {string|string[]} service.command - Command to run (string or array)
 * @param {string} service.path - Working directory
 * @param {boolean} [service.enabled=true] - Whether to run at load
 * @param {Object|boolean} [service.keepAlive=true] - KeepAlive configuration
 * @param {Object} [service.environmentVariables] - Environment variables
 * @param {number} [service.throttleInterval] - Seconds between restart attempts
 * @param {Object} [service.extraKeys] - Additional plist keys to include
 * 
 * @param {Object} settings - Global settings
 * @param {string} settings.logDir - Directory for log files
 * @param {string} [settings.nodePath] - Path to node binary (for PATH env)
 * 
 * @returns {string} - Valid plist XML string
 */
export function generatePlistFromService(service, settings) {
  // Validate required fields
  if (!service.identifier) {
    throw new Error('Service must have an identifier');
  }
  if (!service.command) {
    throw new Error('Service must have a command');
  }
  
  const shortName = extractShortName(service.identifier);
  const logDir = settings.logDir || '/var/log';
  
  // Parse command - can be string or array
  const commandArray = Array.isArray(service.command)
    ? service.command
    : service.command.split(/\s+/).filter(Boolean);
  
  // Build ProgramArguments
  const programArgsXml = commandArray
    .map(arg => `        <string>${escapeXml(arg)}</string>`)
    .join('\n');
  
  // Build KeepAlive section
  let keepAliveXml;
  const keepAlive = service.keepAlive !== undefined ? service.keepAlive : true;
  if (typeof keepAlive === 'boolean') {
    keepAliveXml = keepAlive ? '    <true/>' : '    <false/>';
  } else if (typeof keepAlive === 'object') {
    // Complex KeepAlive (e.g., { SuccessfulExit: false })
    const entries = Object.entries(keepAlive)
      .map(([k, v]) => `        <key>${escapeXml(k)}</key>\n        <${v}/>`)
      .join('\n');
    keepAliveXml = `    <dict>\n${entries}\n    </dict>`;
  } else {
    keepAliveXml = '    <true/>';
  }
  
  // Build EnvironmentVariables section
  let envVarsXml = '';
  const envVars = service.environmentVariables || {};
  
  // Add PATH if nodePath is provided and PATH not already set
  if (settings.nodePath && !envVars.PATH) {
    envVars.PATH = `${dirname(settings.nodePath)}:/usr/local/bin:/usr/bin:/bin`;
  }
  
  if (Object.keys(envVars).length > 0) {
    const envEntries = Object.entries(envVars)
      .map(([k, v]) => `        <key>${escapeXml(k)}</key>\n        <string>${escapeXml(v)}</string>`)
      .join('\n');
    envVarsXml = `    <key>EnvironmentVariables</key>
    <dict>
${envEntries}
    </dict>`;
  }
  
  // Build ThrottleInterval if present
  let throttleXml = '';
  if (service.throttleInterval !== undefined) {
    throttleXml = `    <key>ThrottleInterval</key>
    <integer>${service.throttleInterval}</integer>`;
  }
  
  // Build extra keys if present
  let extraKeysXml = '';
  if (service.extraKeys && typeof service.extraKeys === 'object') {
    extraKeysXml = Object.entries(service.extraKeys)
      .map(([k, v]) => `    <key>${escapeXml(k)}</key>\n${valueToXml(v, 1)}`)
      .join('\n');
  }
  
  // Assemble the plist
  const sections = [
    `    <key>Label</key>
    <string>${escapeXml(service.identifier)}</string>`,
    `    <key>ProgramArguments</key>
    <array>
${programArgsXml}
    </array>`,
    service.path ? `    <key>WorkingDirectory</key>
    <string>${escapeXml(service.path)}</string>` : '',
    `    <key>RunAtLoad</key>
    <${service.enabled !== false ? 'true' : 'false'}/>`,
    `    <key>KeepAlive</key>
${keepAliveXml}`,
    throttleXml,
    `    <key>StandardOutPath</key>
    <string>${escapeXml(logDir)}/${escapeXml(shortName)}.log</string>`,
    `    <key>StandardErrorPath</key>
    <string>${escapeXml(logDir)}/${escapeXml(shortName)}.error.log</string>`,
    envVarsXml,
    extraKeysXml
  ].filter(Boolean).join('\n');
  
  return `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
${sections}
</dict>
</plist>`;
}

/**
 * Write plist to file atomically (write to temp, then rename)
 * This prevents partial writes if process is interrupted
 * 
 * @param {string} content - Plist XML content
 * @param {string} destPath - Final destination path
 * @returns {boolean} - True if successful
 */
export function writePlistAtomic(content, destPath) {
  const tempName = `.plist-${randomBytes(8).toString('hex')}.tmp`;
  const tempPath = join(dirname(destPath), tempName);
  
  try {
    writeFileSync(tempPath, content, { mode: 0o644 });
    renameSync(tempPath, destPath);
    return true;
  } catch (err) {
    // Clean up temp file if it exists
    try {
      if (existsSync(tempPath)) {
        require('fs').unlinkSync(tempPath);
      }
    } catch (cleanupErr) {
      // Ignore cleanup errors
    }
    throw err;
  }
}

/**
 * Parse an existing plist and extract unknown keys
 * (Keys we don't manage but should preserve)
 * 
 * @param {string} plistPath - Path to existing plist
 * @returns {Object} - Object with unknown keys and their values
 */
export function extractUnknownKeys(plistPath) {
  // Keys we manage and understand
  const knownKeys = new Set([
    'Label',
    'ProgramArguments',
    'WorkingDirectory',
    'RunAtLoad',
    'KeepAlive',
    'StandardOutPath',
    'StandardErrorPath',
    'EnvironmentVariables',
    'ThrottleInterval'
  ]);
  
  if (!existsSync(plistPath)) {
    return {};
  }
  
  try {
    const content = readFileSync(plistPath, 'utf-8');
    const unknownKeys = {};
    
    // Simple regex-based extraction for unknown keys
    // This is a basic implementation - a full plist parser would be better
    // but we want to keep dependencies minimal
    const keyRegex = /<key>([^<]+)<\/key>/g;
    let match;
    
    while ((match = keyRegex.exec(content)) !== null) {
      const key = match[1];
      if (!knownKeys.has(key)) {
        // Found an unknown key - mark it for preservation
        // The actual value extraction would need more parsing
        unknownKeys[key] = true;
      }
    }
    
    return unknownKeys;
  } catch (err) {
    return {};
  }
}

/**
 * Convert a service.json entry to the format expected by generatePlistFromService
 * Handles field name normalization (healthCheckURL -> healthCheck)
 * 
 * @param {Object} jsonService - Service from services.json
 * @param {Object} settings - Global settings
 * @returns {Object} - Normalized service object
 */
export function normalizeServiceConfig(jsonService, settings) {
  const normalized = { ...jsonService };
  
  // Normalize healthCheck key (healthCheckURL -> healthCheck)
  if (normalized.healthCheckURL && !normalized.healthCheck) {
    normalized.healthCheck = normalized.healthCheckURL;
    delete normalized.healthCheckURL;
  }
  
  // Generate identifier if missing
  if (!normalized.identifier && normalized.name && settings.identifierPrefix) {
    const slug = normalized.name.toLowerCase()
      .replace(/[^a-z0-9]+/g, '-')
      .replace(/(^-|-$)/g, '');
    normalized.identifier = `${settings.identifierPrefix}.${slug}`;
  }
  
  return normalized;
}

// Default export for convenience
export default {
  generatePlistFromService,
  escapeXml,
  extractShortName,
  writePlistAtomic,
  extractUnknownKeys,
  normalizeServiceConfig
};
