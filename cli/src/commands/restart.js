import chalk from 'chalk';
import ora from 'ora';
import { loadConfig, getService } from '../lib/config.js';
import { restartService, getServiceStatus, installService } from '../lib/launchd.js';

export async function restartCommand(name, options) {
  const config = loadConfig();
  
  // Determine which services to restart
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
    const spinner = ora(`Restarting ${service.name}...`).start();
    
    try {
      const status = getServiceStatus(service.identifier);
      
      if (!status.loaded) {
        // Not installed - install it
        spinner.text = `Installing ${service.name}...`;
        installService(service);
      } else {
        // Restart it
        restartService(service.identifier);
      }
      
      // Wait and check
      await new Promise(r => setTimeout(r, 2000));
      const newStatus = getServiceStatus(service.identifier);
      
      if (newStatus.running) {
        spinner.succeed(chalk.green(`${service.name} restarted (PID: ${newStatus.pid})`));
      } else {
        spinner.warn(chalk.yellow(`${service.name} restarting... (check 'sm status ${service.name}')`));
      }
      
    } catch (err) {
      spinner.fail(chalk.red(`Failed to restart ${service.name}: ${err.message}`));
    }
  }
  
  console.log('');
}
