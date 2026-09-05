import { constants, openSync, closeSync, fstatSync, fchmodSync, readFileSync,
  lstatSync, readlinkSync, symlinkSync, renameSync, unlinkSync } from 'fs';
import { execFileSync } from 'child_process';
import { homedir } from 'os';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

const cursorDirectory = join(homedir(), '.cursor');
const authFile = join(cursorDirectory, 'auth.json');
const launcher = fileURLToPath(new URL('../../bin/cursor-file-agent', import.meta.url));

function inspectPrivate(path, directory, repair, repaired) {
  const before = lstatSync(path);
  if (before.isSymbolicLink() || !(directory ? before.isDirectory() : before.isFile())) {
    throw new Error('unsafe-type');
  }
  if (before.uid !== process.getuid() || (!directory && before.nlink !== 1)) {
    throw new Error('unsafe-owner');
  }
  // chmod does not remove macOS ACL grants. Refuse ACLs rather than discarding them.
  if (process.platform === 'darwin') {
    const listing = execFileSync('/bin/ls', ['-lde', path], { encoding: 'utf8' });
    if (/^\s*\d+: /m.test(listing)) throw new Error('acl');
  }
  const fd = openSync(path, constants.O_RDONLY | constants.O_NOFOLLOW |
    constants.O_NONBLOCK | (directory ? constants.O_DIRECTORY : 0));
  try {
    const current = fstatSync(fd);
    if (current.dev !== before.dev || current.ino !== before.ino) throw new Error('changed');
    const mode = directory ? 0o700 : 0o600;
    if ((current.mode & 0o7777) !== mode) {
      if (!repair) throw new Error('permissions');
      fchmodSync(fd, mode);
      repaired.push(directory ? 'restricted Cursor directory permissions' : 'restricted Cursor login permissions');
    }
    if (!directory) {
      if (current.size > 1024 * 1024) throw new Error('invalid');
      const parsed = JSON.parse(readFileSync(fd, 'utf8'));
      if (!parsed || !['accessToken', 'refreshToken'].every(key =>
        typeof parsed[key] === 'string' && parsed[key].trim().length > 0)) {
        throw new Error('invalid');
      }
    }
  } finally {
    closeSync(fd);
  }
}

function installLauncher(repaired) {
  const link = join(homedir(), '.local/bin/cursor-agent');
  const parent = lstatSync(dirname(link));
  if (!parent.isDirectory() || parent.uid !== process.getuid() || (parent.mode & 0o022)) {
    throw new Error('unsafe-launcher');
  }
  try {
    const current = lstatSync(link);
    if (!current.isSymbolicLink()) throw new Error('unsafe-launcher');
    const target = readlinkSync(link);
    if (target === launcher) return;
    if (!target.startsWith(join(homedir(), '.local/share/cursor-agent/versions/'))) {
      throw new Error('unsafe-launcher');
    }
  } catch (error) {
    if (error.code !== 'ENOENT') throw error;
  }
  const temporary = `${link}.repair-${process.pid}`;
  symlinkSync(launcher, temporary);
  try {
    renameSync(temporary, link);
  } catch (error) {
    unlinkSync(temporary);
    throw error;
  }
  repaired.push('installed file-backed Cursor launcher');
}

/** Local validation only. Token acceptance requires a request to Cursor. */
export function cursorPreflight({ repair = false, install = repair } = {}) {
  const result = { store: 'file', directory: cursorDirectory, authFile,
    repaired: [], ready: false, authentication: 'not-checked', issue: null };
  try {
    if (install) installLauncher(result.repaired);
    inspectPrivate(cursorDirectory, true, repair, result.repaired);
    inspectPrivate(authFile, false, repair, result.repaired);
    result.ready = true;
  } catch (error) {
    const issues = {
      ENOENT: 'Cursor login file or directory is missing. Run cursor-agent login.',
      EACCES: 'Cursor files are inaccessible. Check owner access and rerun preflight.',
      EPERM: 'Cursor permission repair was denied. Check ownership and rerun preflight.',
      'unsafe-type': 'Cursor paths must be a real directory and a regular file, without symlinks.',
      'unsafe-owner': 'Cursor files must belong to the current user and the login file must have one link.',
      acl: 'Cursor paths have an ACL. Review and remove unintended ACL grants before continuing.',
      changed: 'Cursor files changed during inspection. Rerun preflight.',
      permissions: 'Cursor permissions must be 0700 for the directory and 0600 for the login file. Run sm cursor-preflight --repair.',
      'unsafe-launcher': 'Refusing to replace an unfamiliar Cursor launcher or use an unsafe bin directory.'
    };
    // Never echo parse errors: they can contain credential bytes.
    result.issue = issues[error.code] || issues[error.message] ||
      'Cursor login file could not be validated. Run cursor-agent login.';
  }
  return result;
}
