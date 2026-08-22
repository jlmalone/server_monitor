import chalk from 'chalk';
import { loadSecretsSyncConfig, secretsSyncConfigPath, syncSecrets } from '../lib/secrets-sync.js';

export async function secretsSyncCommand(options) {
  let config;
  try {
    config = loadSecretsSyncConfig();
  } catch (err) {
    console.error(chalk.red(err.message));
    console.error(chalk.dim(`Copy config/secrets-sync.example.json to ${secretsSyncConfigPath()}`));
    process.exitCode = 1;
    return;
  }

  let results;
  try {
    results = syncSecrets(config, { dryRun: Boolean(options.dryRun) });
  } catch (err) {
    console.error(chalk.red(err.message));
    process.exitCode = 1;
    return;
  }

  if (options.json) {
    console.log(JSON.stringify({
      sourceDir: config.sourceDir,
      dryRun: Boolean(options.dryRun),
      results: results.map((r) => ({
        host: r.host,
        ok: r.ok,
        step: r.step || 'rsync',
        error: r.error || null
      }))
    }, null, 2));
  } else {
    for (const result of results) {
      if (result.ok) {
        console.log(`${result.dryRun ? 'dry-run' : 'ok'} ${result.host}`);
      } else {
        console.error(`fail ${result.host} (${result.step}): ${result.error}`);
      }
    }
  }

  if (results.some((r) => !r.ok)) process.exitCode = 1;
}
