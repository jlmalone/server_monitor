#!/usr/bin/env node
/**
 * Test script for plist-from-json.js
 * Validates that generated plist matches expected golden fixture
 */

import { readFileSync } from 'fs';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';
import {
  generatePlistFromService,
  escapeXml,
  extractShortName,
  normalizeServiceConfig
} from '../src/lib/plist-from-json.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const FIXTURES_DIR = join(__dirname, 'fixtures');

function test(name, fn) {
  try {
    fn();
    console.log(`✅ ${name}`);
    return true;
  } catch (err) {
    console.log(`❌ ${name}`);
    console.log(`   ${err.message}`);
    return false;
  }
}

function assertEqual(actual, expected, message = '') {
  if (actual !== expected) {
    throw new Error(`${message}\nExpected:\n${expected}\n\nActual:\n${actual}`);
  }
}

// Run tests
console.log('\n🧪 plist-from-json.js Tests\n');

let passed = 0;
let failed = 0;

// Test escapeXml
if (test('escapeXml handles special characters', () => {
  assertEqual(escapeXml('&'), '&amp;');
  assertEqual(escapeXml('<'), '&lt;');
  assertEqual(escapeXml('>'), '&gt;');
  assertEqual(escapeXml('"'), '&quot;');
  assertEqual(escapeXml("'"), '&apos;');
  assertEqual(escapeXml('Hello & <world>'), 'Hello &amp; &lt;world&gt;');
})) passed++; else failed++;

// Test escapeXml null handling
if (test('escapeXml handles null/undefined', () => {
  assertEqual(escapeXml(null), '');
  assertEqual(escapeXml(undefined), '');
  assertEqual(escapeXml(123), '123');
})) passed++; else failed++;

// Test extractShortName
if (test('extractShortName extracts last segment', () => {
  assertEqual(extractShortName('com.servermonitor.my-service'), 'my-service');
  assertEqual(extractShortName('com.example.myservice'), 'myservice');
  assertEqual(extractShortName('simple'), 'simple');
})) passed++; else failed++;

// Test normalizeServiceConfig
if (test('normalizeServiceConfig normalizes healthCheckURL', () => {
  const service = { name: 'Test', healthCheckURL: 'http://localhost:3000' };
  const normalized = normalizeServiceConfig(service, {});
  assertEqual(normalized.healthCheck, 'http://localhost:3000');
  assertEqual(normalized.healthCheckURL, undefined);
})) passed++; else failed++;

// Test golden fixture generation
if (test('generatePlistFromService matches golden fixture', () => {
  const fixtureData = JSON.parse(readFileSync(join(FIXTURES_DIR, 'sample-service.json'), 'utf-8'));
  const expectedPlist = readFileSync(join(FIXTURES_DIR, 'expected-plist.xml'), 'utf-8');
  
  const generatedPlist = generatePlistFromService(fixtureData.service, fixtureData.settings);
  
  // Normalize line endings for comparison
  const normalizedExpected = expectedPlist.trim();
  const normalizedGenerated = generatedPlist.trim();
  
  assertEqual(normalizedGenerated, normalizedExpected, 'Generated plist does not match expected');
})) passed++; else failed++;

// Test required fields validation
if (test('generatePlistFromService throws on missing identifier', () => {
  try {
    generatePlistFromService({ command: ['echo', 'test'] }, {});
    throw new Error('Should have thrown');
  } catch (err) {
    if (!err.message.includes('identifier')) throw err;
  }
})) passed++; else failed++;

if (test('generatePlistFromService throws on missing command', () => {
  try {
    generatePlistFromService({ identifier: 'test.service' }, {});
    throw new Error('Should have thrown');
  } catch (err) {
    if (!err.message.includes('command')) throw err;
  }
})) passed++; else failed++;

// Test string command parsing
if (test('generatePlistFromService handles string command', () => {
  const plist = generatePlistFromService({
    identifier: 'test.service',
    command: '/usr/bin/node server.js --port 3000'
  }, { logDir: '/var/log' });
  
  if (!plist.includes('<string>/usr/bin/node</string>')) throw new Error('Missing node path');
  if (!plist.includes('<string>server.js</string>')) throw new Error('Missing server.js');
  if (!plist.includes('<string>--port</string>')) throw new Error('Missing --port');
  if (!plist.includes('<string>3000</string>')) throw new Error('Missing 3000');
})) passed++; else failed++;

// Test boolean KeepAlive
if (test('generatePlistFromService handles boolean KeepAlive', () => {
  const plist = generatePlistFromService({
    identifier: 'test.service',
    command: ['echo', 'test'],
    keepAlive: true
  }, { logDir: '/var/log' });
  
  if (!plist.includes('<key>KeepAlive</key>\n    <true/>')) {
    throw new Error('KeepAlive should be simple true');
  }
})) passed++; else failed++;

// Test disabled service
if (test('generatePlistFromService handles enabled=false', () => {
  const plist = generatePlistFromService({
    identifier: 'test.service',
    command: ['echo', 'test'],
    enabled: false
  }, { logDir: '/var/log' });
  
  if (!plist.includes('<key>RunAtLoad</key>\n    <false/>')) {
    throw new Error('RunAtLoad should be false');
  }
})) passed++; else failed++;

// Summary
console.log(`\n📊 Results: ${passed} passed, ${failed} failed\n`);
process.exit(failed > 0 ? 1 : 0);
