import chalk from 'chalk';
import ora from 'ora';
import { loadConfig, getService } from '../lib/config.js';
import { startService, getServiceStatus, installService } from '../lib/launchd.js';

export async function startCommand(name, options) {
  const config = loadConfig();
  
  // Determine which services to start
  let services;
  if (options.all || !name) {
    services = config.services;
    if (services.length === 0) {
      console.log(chalk.yellow('\nNo services configured.'));
      return;
    }
  } else {
    const service = getService(name);
    if (!service) {
      console.log(chalk.red(`Service "${name}" not found`));
      console.log(chalk.dim("Run 'sm list' to see available services."));
      process.exit(1);
    }
    services = [service];
  }
  
  console.log('');
  
  for (const service of services) {
    const spinner = ora(`Starting ${service.name}...`).start();
    
    try {
      // Check if already running
      const status = getServiceStatus(service.identifier);
      
      if (status.running) {
        spinner.info(chalk.dim(`${service.name} already running (PID: ${status.pid})`));
        continue;
      }
      
      // If not loaded, install first
      if (!status.loaded) {
        spinner.text = `Installing ${service.name}...`;
        installService(service);
      } else {
        // Just start it
        startService(service.identifier);
      }
      
      // Wait a moment and check status
      await new Promise(r => setTimeout(r, 1500));
      const newStatus = getServiceStatus(service.identifier);
      
      if (newStatus.running) {
        spinner.succeed(chalk.green(`${service.name} started (PID: ${newStatus.pid})`));
      } else {
        spinner.warn(chalk.yellow(`${service.name} starting... (check 'sm status ${service.name}')`));
      }
      
    } catch (err) {
      spinner.fail(chalk.red(`Failed to start ${service.name}: ${err.message}`));
    }
  }
  
  console.log('');
}
