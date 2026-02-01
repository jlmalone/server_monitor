import chalk from 'chalk';
import { spawn } from 'child_process';
import { loadConfig, getService, expandPath } from '../lib/config.js';
import { existsSync } from 'fs';
import { join } from 'path';

export async function logsCommand(name, options) {
  const config = loadConfig();
  const service = getService(name);
  
  if (!service) {
    console.log(chalk.red(`Service "${name}" not found`));
    console.log(chalk.dim("Run 'sm list' to see available services."));
    process.exit(1);
  }
  
  const logDir = expandPath(config.settings.logDir);
  const shortName = service.identifier.split('.').pop();
  
  const logFile = options.error 
    ? join(logDir, `${shortName}.error.log`)
    : join(logDir, `${shortName}.log`);
  
  if (!existsSync(logFile)) {
    console.log(chalk.yellow(`Log file not found: ${logFile}`));
    console.log(chalk.dim('The service may not have started yet.'));
    process.exit(1);
  }
  
  console.log(chalk.dim(`Tailing ${options.error ? 'error ' : ''}log for ${service.name}...`));
  console.log(chalk.dim(`File: ${logFile}`));
  console.log(chalk.dim('Press Ctrl+C to exit\n'));
  
  // Use tail -f
  const args = options.follow !== false 
    ? ['-f', '-n', options.lines, logFile]
    : ['-n', options.lines, logFile];
  
  const tail = spawn('tail', args, {
    stdio: 'inherit'
  });
  
  tail.on('error', (err) => {
    console.error(chalk.red(`Failed to tail log: ${err.message}`));
    process.exit(1);
  });
  
  // Handle Ctrl+C gracefully
  process.on('SIGINT', () => {
    tail.kill();
    console.log(chalk.dim('\nStopped tailing.'));
    process.exit(0);
  });
}
