import { existsSync, lstatSync, chmodSync, readFileSync } from 'fs';
import { homedir } from 'os';
import { join } from 'path';

const cursorDirectory = join(homedir(), '.cursor');
const authFile = join(cursorDirectory, 'auth.json');

function privateMode(path) {
  return (lstatSync(path).mode & 0o077) === 0;
}

function hasCredentialShape(path) {
  try {
    const parsed = JSON.parse(readFileSync(path, 'utf8'));
    return ['accessToken', 'refreshToken'].every((key) =>
      typeof parsed[key] === 'string' && parsed[key].length > 0
    );
  } catch {
    return false;
  }
}

/**
 * Inspect or normalize the local file-backed Cursor credential store.
 * No credential values are read into output and no keychain access is needed.
 */
export function cursorPreflight({ repair = false } = {}) {
  const result = {
    store: 'file',
    directory: cursorDirectory,
    authFile,
    repaired: [],
    ready: false,
    issue: null
  };

  if (!existsSync(cursorDirectory)) {
    result.issue = 'Cursor configuration directory is missing. Run cursor-agent login.';
    return result;
  }

  if (!privateMode(cursorDirectory)) {
    if (repair) {
      chmodSync(cursorDirectory, 0o700);
      result.repaired.push('restricted Cursor configuration directory permissions');
    } else {
      result.issue = 'Cursor configuration directory permissions are too broad.';
      return result;
    }
  }

  if (!existsSync(authFile)) {
    result.issue = 'Cursor login file is missing. Run cursor-agent login.';
    return result;
  }

  if (!privateMode(authFile)) {
    if (repair) {
      chmodSync(authFile, 0o600);
      result.repaired.push('restricted Cursor login file permissions');
    } else {
      result.issue = 'Cursor login file permissions are too broad.';
      return result;
    }
  }

  if (!hasCredentialShape(authFile)) {
    result.issue = 'Cursor login file is invalid. Run cursor-agent login.';
    return result;
  }

  result.ready = true;
  return result;
}
