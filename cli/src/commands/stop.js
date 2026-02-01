import chalk from 'chalk';
import ora from 'ora';
import { loadConfig, getService } from '../lib/config.js';
import { stopService, getServiceStatus } from '../lib/launchd.js';

export async function stopCommand(name, options) {
  const config = loadConfig();
  
  // Determine which services to stop
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
    const spinner = ora(`Stopping ${service.name}...`).start();
    
    try {
      // Check current status
      const status = getServiceStatus(service.identifier);
      
      if (!status.loaded) {
        spinner.info(chalk.dim(`${service.name} not installed`));
        continue;
      }
      
      if (!status.running) {
        // Still bootout to fully unload (plist regenerated on next start)
        spinner.text = `Unloading ${service.name}...`;
        stopService(service.identifier, false);
        spinner.info(chalk.dim(`${service.name} was stopped, now unloaded`));
        continue;
      }
      
      // Stop and bootout the service (uses modern launchctl bootout)
      // Plist will be regenerated from services.json on next 'sm start'
      stopService(service.identifier, false);
      
      // Wait and verify
      await new Promise(r => setTimeout(r, 1000));
      const newStatus = getServiceStatus(service.identifier);
      
      if (!newStatus.running && !newStatus.loaded) {
        spinner.succeed(chalk.green(`${service.name} stopped and unloaded`));
      } else if (!newStatus.running) {
        spinner.succeed(chalk.green(`${service.name} stopped`));
      } else {
        spinner.warn(chalk.yellow(`${service.name} may still be stopping...`));
      }
      
    } catch (err) {
      spinner.fail(chalk.red(`Failed to stop ${service.name}: ${err.message}`));
    }
  }
  
  console.log('');
}
