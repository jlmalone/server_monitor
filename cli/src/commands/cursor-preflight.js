import chalk from 'chalk';
import { cursorPreflight } from '../lib/cursor-preflight.js';

export function cursorPreflightCommand(options) {
  const result = cursorPreflight({ repair: options.repair });

  if (options.json) {
    console.log(JSON.stringify(result, null, 2));
  } else if (result.ready) {
    const repair = result.repaired.length > 0
      ? ` Repaired: ${result.repaired.join('; ')}.`
      : '';
    console.log(chalk.green(`Cursor preflight ready: file-backed credentials are private and usable.${repair}`));
  } else {
    console.log(chalk.red(`Cursor preflight needs login: ${result.issue}`));
  }

  if (!result.ready) {
    process.exitCode = 1;
  }
}
