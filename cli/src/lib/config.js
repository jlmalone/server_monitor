import { readFileSync, writeFileSync, existsSync } from 'fs';
import { homedir } from 'os';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const PROJECT_ROOT = join(__dirname, '..', '..', '..');
const CONFIG_PATH = join(PROJECT_ROOT, 'services.json');

const DEFAULT_CONFIG = {
  version: '2.0.0',
  settings: {
    logDir: join(PROJECT_ROOT, 'logs'),
    identifierPrefix: 'com.servermonitor',
    plistDir: join(PROJECT_ROOT, 'launchd'),
    launchAgentsDir: join(homedir(), 'Library', 'LaunchAgents'),
    nodePath: process.execPath
  },
  services: []
};

// Check standard locations
const APP_SUPPORT_CONFIG = join(homedir(), 'Library', 'Application Support', 'ServerMonitor', 'services.json');

/**
 * Load the services configuration
 */
export function loadConfig() {
  // Priority: 1. Current Directory (already set as CONFIG_PATH) 2. Application Support
  let configPath = CONFIG_PATH;

  // If local config doesn't exist but global does, use global
  if (!existsSync(CONFIG_PATH) && existsSync(APP_SUPPORT_CONFIG)) {
    configPath = APP_SUPPORT_CONFIG;
  }

  if (!existsSync(configPath)) {
    saveConfig(DEFAULT_CONFIG);
    return DEFAULT_CONFIG;
  }

  try {
    const content = readFileSync(CONFIG_PATH, 'utf-8');
    const config = JSON.parse(content);
    // Merge with defaults for any missing settings
    return {
      ...DEFAULT_CONFIG,
      ...config,
      settings: { ...DEFAULT_CONFIG.settings, ...config.settings }
    };
  } catch (err) {
    console.error('Error reading config:', err.message);
    return DEFAULT_CONFIG;
  }
}

/**
 * Save the configuration
 */
export function saveConfig(config) {
  writeFileSync(CONFIG_PATH, JSON.stringify(config, null, 2));
}

/**
 * Get a service by name (case-insensitive)
 */
export function getService(name) {
  const config = loadConfig();
  return config.services.find(s =>
    s.name.toLowerCase() === name.toLowerCase() ||
    s.identifier.toLowerCase().includes(name.toLowerCase())
  ) || null;
}

/**
 * Add a new service
 */
export function addService(service) {
  const config = loadConfig();

  // Check for duplicates
  const exists = config.services.find(s =>
    s.name.toLowerCase() === service.name.toLowerCase() ||
    s.identifier === service.identifier
  );

  if (exists) {
    throw new Error(`Service "${service.name}" already exists`);
  }

  config.services.push(service);
  saveConfig(config);
  return config;
}

/**
 * Remove a service by name
 */
export function removeService(name) {
  const config = loadConfig();
  const index = config.services.findIndex(s =>
    s.name.toLowerCase() === name.toLowerCase() ||
    s.identifier.toLowerCase().includes(name.toLowerCase())
  );

  if (index === -1) {
    throw new Error(`Service "${name}" not found`);
  }

  const removed = config.services.splice(index, 1)[0];
  saveConfig(config);
  return removed;
}

/**
 * Update a service
 */
export function updateService(name, updates) {
  const config = loadConfig();
  const service = config.services.find(s =>
    s.name.toLowerCase() === name.toLowerCase()
  );

  if (!service) {
    throw new Error(`Service "${name}" not found`);
  }

  Object.assign(service, updates);
  saveConfig(config);
  return service;
}

/**
 * Generate a launchd identifier from name
 */
export function generateIdentifier(name, prefix) {
  const slug = name.toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/(^-|-$)/g, '');
  return `${prefix}.${slug}`;
}

/**
 * Expand ~ in paths
 */
export function expandPath(path) {
  if (path.startsWith('~')) {
    return join(homedir(), path.slice(1));
  }
  return path;
}

export { CONFIG_PATH, PROJECT_ROOT };
