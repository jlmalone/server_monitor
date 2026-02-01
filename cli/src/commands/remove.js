import chalk from 'chalk';
import ora from 'ora';
import { getService, removeService } from '../lib/config.js';
import { uninstallService } from '../lib/launchd.js';

export async function removeCommand(name, options) {
  const spinner = ora(`Removing service "${name}"...`).start();
  
  try {
    // Find the service
    const service = getService(name);
    
    if (!service) {
      spinner.fail(chalk.red(`Service "${name}" not found`));
      console.log(chalk.dim("Run 'sm list' to see available services."));
      process.exit(1);
    }
    
    // Uninstall from launchd
    spinner.text = 'Stopping and unloading from launchd...';
    uninstallService(service);
    
    // Remove from config (unless --keep-config)
    if (!options.keepConfig) {
      spinner.text = 'Removing from configuration...';
      removeService(name);
      spinner.succeed(chalk.green(`Service "${service.name}" removed completely`));
    } else {
      spinner.succeed(chalk.green(`Service "${service.name}" uninstalled from launchd`));
      console.log(chalk.dim('Configuration retained. Run `sm start ' + name + '` to reinstall.'));
    }
    
  } catch (err) {
    spinner.fail(chalk.red(err.message));
    process.exit(1);
  }
}
