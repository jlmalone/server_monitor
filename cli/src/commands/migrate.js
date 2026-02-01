/**
 * migrate.js
 * 
 * Converts existing launchd plist files to the expanded services.json format.
 * Parses all backed-up plists and extracts complete service configuration.
 * 
 * Usage:
 *   node src/commands/migrate.js --source ~/launchd_bak_todo
 *   node src/commands/migrate.js --source ~/launchd_bak_todo --dry-run
 */

import { readFileSync, writeFileSync, renameSync, readdirSync, existsSync, mkdirSync } from 'fs';
import { join, dirname, basename } from 'path';
import { homedir, tmpdir } from 'os';
import { randomBytes } from 'crypto';
import { parseArgs } from 'util';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// Parse command line arguments
const { values: args } = parseArgs({
  options: {
    source: { type: 'string', short: 's' },
    output: { type: 'string', short: 'o' },
    'existing-config': { type: 'string', short: 'e' },
    'dry-run': { type: 'boolean', short: 'd' },
    help: { type: 'boolean', short: 'h' }
  }
});

if (args.help) {
  console.log(`
migrate.js - Convert plist files to services.json format

Usage:
  node src/commands/migrate.js --source <plist-dir> [options]

Options:
  -s, --source <dir>           Directory containing plist files (required)
  -o, --output <path>          Output path for services.json
                               (default: ~/Library/Application Support/ServerMonitor/services.json)
  -e, --existing-config <path> Existing services.json to merge port/healthCheck data from
                               (default: auto-detect from project root)
  -d, --dry-run                Print output without writing to file
  -h, --help                   Show this help message
`);
  process.exit(0);
}

/**
 * Simple plist XML parser
 * Extracts values from Apple plist XML format
 */
class PlistParser {
  constructor(xml) {
    this.xml = xml;
    this.pos = 0;
  }

  parse() {
    // Skip to <dict> inside <plist>
    const dictStart = this.xml.indexOf('<dict>', this.xml.indexOf('<plist'));
    if (dictStart === -1) throw new Error('No <dict> found in plist');
    this.pos = dictStart;
    return this.parseDict();
  }

  parseDict() {
    const result = {};
    this.expect('<dict>');
    this.skipWhitespace();
    
    while (!this.lookAhead('</dict>')) {
      // Parse key
      this.expect('<key>');
      const keyEnd = this.xml.indexOf('</key>', this.pos);
      const key = this.xml.substring(this.pos, keyEnd);
      this.pos = keyEnd + 6; // '</key>'.length
      this.skipWhitespace();
      
      // Parse value
      result[key] = this.parseValue();
      this.skipWhitespace();
    }
    
    this.expect('</dict>');
    return result;
  }

  parseValue() {
    this.skipWhitespace();
    
    if (this.lookAhead('<string>')) {
      return this.parseString();
    } else if (this.lookAhead('<integer>')) {
      return this.parseInteger();
    } else if (this.lookAhead('<real>')) {
      return this.parseReal();
    } else if (this.lookAhead('<true/>')) {
      this.pos += 7;
      return true;
    } else if (this.lookAhead('<false/>')) {
      this.pos += 8;
      return false;
    } else if (this.lookAhead('<array>')) {
      return this.parseArray();
    } else if (this.lookAhead('<dict>')) {
      return this.parseDict();
    } else if (this.lookAhead('<data>')) {
      return this.parseData();
    } else if (this.lookAhead('<date>')) {
      return this.parseDate();
    } else {
      throw new Error(`Unknown value type at position ${this.pos}: ${this.xml.substring(this.pos, this.pos + 50)}`);
    }
  }

  parseString() {
    this.expect('<string>');
    // Handle empty strings
    if (this.lookAhead('</string>')) {
      this.expect('</string>');
      return '';
    }
    const endIdx = this.xml.indexOf('</string>', this.pos);
    const value = this.decodeXmlEntities(this.xml.substring(this.pos, endIdx));
    this.pos = endIdx + 9;
    return value;
  }

  parseInteger() {
    this.expect('<integer>');
    const endIdx = this.xml.indexOf('</integer>', this.pos);
    const value = parseInt(this.xml.substring(this.pos, endIdx), 10);
    this.pos = endIdx + 10;
    return value;
  }

  parseReal() {
    this.expect('<real>');
    const endIdx = this.xml.indexOf('</real>', this.pos);
    const value = parseFloat(this.xml.substring(this.pos, endIdx));
    this.pos = endIdx + 7;
    return value;
  }

  parseArray() {
    const result = [];
    this.expect('<array>');
    this.skipWhitespace();
    
    while (!this.lookAhead('</array>')) {
      result.push(this.parseValue());
      this.skipWhitespace();
    }
    
    this.expect('</array>');
    return result;
  }

  parseData() {
    this.expect('<data>');
    const endIdx = this.xml.indexOf('</data>', this.pos);
    const value = this.xml.substring(this.pos, endIdx).trim();
    this.pos = endIdx + 7;
    return { _type: 'data', value };
  }

  parseDate() {
    this.expect('<date>');
    const endIdx = this.xml.indexOf('</date>', this.pos);
    const value = this.xml.substring(this.pos, endIdx);
    this.pos = endIdx + 7;
    return new Date(value);
  }

  decodeXmlEntities(str) {
    return str
      .replace(/&amp;/g, '&')
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>')
      .replace(/&quot;/g, '"')
      .replace(/&apos;/g, "'");
  }

  skipWhitespace() {
    while (this.pos < this.xml.length && /\s/.test(this.xml[this.pos])) {
      this.pos++;
    }
  }

  lookAhead(str) {
    return this.xml.substring(this.pos, this.pos + str.length) === str;
  }

  expect(str) {
    if (!this.lookAhead(str)) {
      throw new Error(`Expected '${str}' at position ${this.pos}, got '${this.xml.substring(this.pos, this.pos + str.length)}'`);
    }
    this.pos += str.length;
  }
}

/**
 * Parse plist XML content
 * @param {string} xml - Plist XML content
 * @returns {Object} - Parsed plist as JS object
 */
function parsePlist(xml) {
  const parser = new PlistParser(xml);
  return parser.parse();
}

/**
 * Derive friendly name from identifier
 * e.g., "vision.salient.redo-https" → "Redo HTTPS"
 * @param {string} identifier - Service identifier
 * @returns {string} - Human-friendly name
 */
function deriveNameFromIdentifier(identifier) {
  // Get the last part of the identifier
  const shortName = identifier.split('.').pop();
  
  // Split by hyphens and capitalize each word
  return shortName
    .split('-')
    .map(word => {
      // Handle common abbreviations
      const upper = word.toUpperCase();
      if (['https', 'http', 'api', 'ui', 'db', 'tcp', 'udp'].includes(upper.toLowerCase())) {
        return upper;
      }
      return word.charAt(0).toUpperCase() + word.slice(1);
    })
    .join(' ');
}

/**
 * Try to extract port from command arguments
 * Looks for --port N or -p N patterns
 * @param {string[]} command - Command arguments array
 * @returns {number|null} - Port number or null
 */
function extractPortFromCommand(command) {
  for (let i = 0; i < command.length; i++) {
    if (command[i] === '--port' || command[i] === '-p') {
      const portStr = command[i + 1];
      if (portStr && /^\d+$/.test(portStr)) {
        return parseInt(portStr, 10);
      }
    }
  }
  return null;
}

/**
 * Convert plist data to service configuration
 * @param {Object} plistData - Parsed plist object
 * @param {Object} existingData - Existing service data (port, healthCheck)
 * @returns {Object} - Service configuration
 */
function plistToService(plistData, existingData = {}) {
  const identifier = plistData.Label;
  const command = plistData.ProgramArguments || [];
  
  // Try to get port from command args first, then existing data
  let port = extractPortFromCommand(command);
  if (!port && existingData.port) {
    port = existingData.port;
  }
  
  // Get healthCheck from existing data (healthCheckURL -> healthCheck)
  const healthCheck = existingData.healthCheck || existingData.healthCheckURL || null;
  
  // Parse KeepAlive - preserve actual value
  let keepAlive = true;
  if (plistData.KeepAlive !== undefined) {
    keepAlive = plistData.KeepAlive;
  }
  
  // Build service object
  const service = {
    name: existingData.name || deriveNameFromIdentifier(identifier),
    identifier,
    path: plistData.WorkingDirectory || null,
    command,
    port,
    healthCheck,
    enabled: plistData.RunAtLoad !== false,
    keepAlive
  };
  
  // Add environment variables if present (exclude PATH as it's derived)
  if (plistData.EnvironmentVariables) {
    const envVars = { ...plistData.EnvironmentVariables };
    // Keep all env vars including PATH for completeness
    if (Object.keys(envVars).length > 0) {
      service.environmentVariables = envVars;
    }
  }
  
  // Add throttleInterval if present
  if (plistData.ThrottleInterval !== undefined) {
    service.throttleInterval = plistData.ThrottleInterval;
  }
  
  return service;
}

/**
 * Write file atomically (write temp, then rename)
 * @param {string} content - File content
 * @param {string} destPath - Destination path
 */
function writeAtomic(content, destPath) {
  const tempName = `.services-${randomBytes(8).toString('hex')}.tmp`;
  const tempPath = join(dirname(destPath), tempName);
  
  try {
    // Ensure directory exists
    const dir = dirname(destPath);
    if (!existsSync(dir)) {
      mkdirSync(dir, { recursive: true });
    }
    
    writeFileSync(tempPath, content, { mode: 0o644 });
    renameSync(tempPath, destPath);
  } catch (err) {
    // Clean up temp file
    try {
      if (existsSync(tempPath)) {
        require('fs').unlinkSync(tempPath);
      }
    } catch (e) {}
    throw err;
  }
}

/**
 * Main migration function
 */
async function migrate() {
  const sourceDir = args.source;
  if (!sourceDir) {
    console.error('Error: --source directory is required');
    console.error('Run with --help for usage');
    process.exit(1);
  }
  
  // Resolve paths
  const resolvedSource = sourceDir.replace(/^~/, homedir());
  const outputPath = args.output?.replace(/^~/, homedir()) 
    || join(homedir(), 'Library/Application Support/ServerMonitor/services.json');
  
  // Check source directory
  if (!existsSync(resolvedSource)) {
    console.error(`Error: Source directory not found: ${resolvedSource}`);
    process.exit(1);
  }
  
  // Load existing config for port/healthCheck data
  let existingServices = {};
  const existingConfigPath = args['existing-config']?.replace(/^~/, homedir())
    || join(dirname(dirname(dirname(__dirname))), 'services.json');
  
  if (existsSync(existingConfigPath)) {
    try {
      const existingConfig = JSON.parse(readFileSync(existingConfigPath, 'utf-8'));
      if (existingConfig.services) {
        for (const svc of existingConfig.services) {
          if (svc.identifier) {
            existingServices[svc.identifier] = svc;
          }
        }
      }
      console.log(`✓ Loaded existing config from ${existingConfigPath}`);
      console.log(`  Found ${Object.keys(existingServices).length} existing service definitions`);
    } catch (e) {
      console.warn(`Warning: Could not parse existing config: ${e.message}`);
    }
  }
  
  // Find all plist files
  const plistFiles = readdirSync(resolvedSource)
    .filter(f => f.endsWith('.plist'))
    .map(f => join(resolvedSource, f));
  
  if (plistFiles.length === 0) {
    console.error(`Error: No .plist files found in ${resolvedSource}`);
    process.exit(1);
  }
  
  console.log(`\nFound ${plistFiles.length} plist files to migrate:\n`);
  
  // Parse all plists
  const services = [];
  let logDir = null;
  const errors = [];
  
  for (const plistPath of plistFiles) {
    const filename = basename(plistPath);
    try {
      const xml = readFileSync(plistPath, 'utf-8');
      const plistData = parsePlist(xml);
      
      // Infer logDir from StandardOutPath
      if (!logDir && plistData.StandardOutPath) {
        logDir = dirname(plistData.StandardOutPath);
      }
      
      // Get existing data for this service
      const existingData = existingServices[plistData.Label] || {};
      
      // Convert to service config
      const service = plistToService(plistData, existingData);
      services.push(service);
      
      console.log(`  ✓ ${filename}`);
      console.log(`    → ${service.name} (${service.identifier})`);
      console.log(`    → port: ${service.port || 'N/A'}, path: ${service.path}`);
    } catch (err) {
      console.log(`  ✗ ${filename}: ${err.message}`);
      errors.push({ file: filename, error: err.message });
    }
  }
  
  console.log('');
  
  // Build output config
  const config = {
    version: '2.0.0',
    settings: {
      logDir: logDir || '/Users/josephmalone/ios_code/server_monitor/logs',
      identifierPrefix: 'vision.salient'
    },
    services: services.sort((a, b) => a.identifier.localeCompare(b.identifier))
  };
  
  const output = JSON.stringify(config, null, 2);
  
  // Validation
  console.log('Validation:');
  console.log(`  Services found: ${services.length}`);
  
  let valid = true;
  const required = ['identifier', 'path', 'command'];
  for (const svc of services) {
    const missing = required.filter(k => !svc[k] || (Array.isArray(svc[k]) && svc[k].length === 0));
    if (missing.length > 0) {
      console.log(`  ⚠ ${svc.identifier}: missing ${missing.join(', ')}`);
      valid = false;
    }
    if (!svc.port) {
      console.log(`  ⚠ ${svc.identifier}: no port detected`);
    }
  }
  
  if (errors.length > 0) {
    console.log(`  ✗ ${errors.length} files failed to parse`);
    valid = false;
  }
  
  if (services.length !== 8) {
    console.log(`  ⚠ Expected 8 services, found ${services.length}`);
  }
  
  if (valid && services.length === 8) {
    console.log('  ✓ All services validated successfully');
  }
  
  console.log('');
  
  // Write or dry-run
  if (args['dry-run']) {
    console.log('Dry run - output would be:');
    console.log('─'.repeat(60));
    console.log(output);
    console.log('─'.repeat(60));
    console.log(`\nWould write to: ${outputPath}`);
  } else {
    writeAtomic(output, outputPath);
    console.log(`✓ Written to: ${outputPath}`);
  }
  
  // Summary
  console.log('\nMigration summary:');
  console.log(`  Total services: ${services.length}`);
  console.log(`  With ports: ${services.filter(s => s.port).length}`);
  console.log(`  With healthCheck: ${services.filter(s => s.healthCheck).length}`);
  console.log(`  With env vars: ${services.filter(s => s.environmentVariables).length}`);
  
  if (!valid || errors.length > 0) {
    process.exit(1);
  }
}

// Run
migrate().catch(err => {
  console.error('Migration failed:', err);
  process.exit(1);
});
