#!/usr/bin/env node
import { Command } from 'commander';
import { readFileSync } from 'fs';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';

import { addCommand } from './commands/add.js';
import { removeCommand } from './commands/remove.js';
import { listCommand } from './commands/list.js';
import { startCommand } from './commands/start.js';
import { stopCommand } from './commands/stop.js';
import { restartCommand } from './commands/restart.js';
import { statusCommand } from './commands/status.js';
import { logsCommand } from './commands/logs.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const pkg = JSON.parse(readFileSync(join(__dirname, '..', 'package.json'), 'utf-8'));

const program = new Command();

program
  .name('sm')
  .description('🖥️  Server Monitor - Manage macOS dev servers via launchd')
  .version(pkg.version);

// Add command
program
  .command('add')
  .description('Add a new service')
  .requiredOption('-n, --name <name>', 'Service name')
  .requiredOption('-p, --path <path>', 'Working directory path')
  .option('-P, --port <port>', 'Port number', parseInt)
  .option('-c, --cmd <command>', 'Command to run (default: npm run dev)')
  .option('-h, --health <url>', 'Health check URL')
  .option('--no-install', 'Add to config only, don\'t install to launchd')
  .action(addCommand);

// Remove command
program
  .command('remove <name>')
  .alias('rm')
  .description('Remove a service')
  .option('--keep-config', 'Keep in config, just uninstall from launchd')
  .action(removeCommand);

// List command
program
  .command('list')
  .alias('ls')
  .description('List all services with status')
  .option('-j, --json', 'Output as JSON')
  .action(listCommand);

// Start command
program
  .command('start [name]')
  .description('Start a service (or all services)')
  .option('-a, --all', 'Start all services')
  .action(startCommand);

// Stop command
program
  .command('stop [name]')
  .description('Stop a service (or all services)')
  .option('-a, --all', 'Stop all services')
  .action(stopCommand);

// Restart command
program
  .command('restart [name]')
  .description('Restart a service (or all services)')
  .option('-a, --all', 'Restart all services')
  .action(restartCommand);

// Status command
program
  .command('status [name]')
  .description('Show detailed status and health info')
  .option('-j, --json', 'Output as JSON')
  .action(statusCommand);

// Logs command
program
  .command('logs <name>')
  .description('Tail logs for a service')
  .option('-f, --follow', 'Follow log output', true)
  .option('-F, --no-follow', 'Don\'t follow, just print')
  .option('-n, --lines <n>', 'Number of lines to show', '50')
  .option('-e, --error', 'Show error log instead of stdout')
  .action(logsCommand);

program.parse();
