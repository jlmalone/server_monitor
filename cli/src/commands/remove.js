import chalk from 'chalk';
import ora from 'ora';
import { existsSync, unlinkSync, readdirSync } from 'fs';
import { join } from 'path';
import { loadConfig, getService, removeService, expandPath } from '../lib/config.js';
import { uninstallService, getServiceStatus } from '../lib/launchd.js';
import { extractShortName } from '../lib/plist-from-json.js';

export async function removeCommand(name, options) {
  const spinner = ora(`Removing service "${name}"...`).start();
  
  try {
    const config = loadConfig();
    const { settings } = config;
    
    // Find the service
    const service = getService(name);
    
    if (!service) {
      spinner.fail(chalk.red(`Service "${name}" not found`));
      console.log(chalk.dim("Run 'sm list' to see available services."));
      process.exit(1);
    }
    
    // 1. Stop and uninstall from launchd (uses modern bootout + removes plist)
    const status = getServiceStatus(service.identifier);
    if (status.loaded || status.running) {
      spinner.text = 'Stopping and unloading from launchd...';
      uninstallService(service);
    } else {
      // Even if not loaded, clean up plist files
      spinner.text = 'Cleaning up plist files...';
      const launchAgentsDir = expandPath(settings.launchAgentsDir);
      const plistDir = expandPath(settings.plistDir);
      const launchAgentsPlist = join(launchAgentsDir, `${service.identifier}.plist`);
      const sourcePlist = join(plistDir, `${service.identifier}.plist`);
      
      if (existsSync(launchAgentsPlist)) {
        unlinkSync(launchAgentsPlist);
      }
      if (existsSync(sourcePlist)) {
        unlinkSync(sourcePlist);
      }
    }
    
    // 2. Optionally clean up log files
    if (options.cleanLogs) {
      spinner.text = 'Cleaning up log files...';
      const logDir = expandPath(settings.logDir);
      const shortName = extractShortName(service.identifier);
      const logFiles = [
        join(logDir, `${shortName}.log`),
        join(logDir, `${shortName}.error.log`)
      ];
      
      for (const logFile of logFiles) {
        if (existsSync(logFile)) {
          unlinkSync(logFile);
        }
      }
    }
    
    // 3. Remove from services.json (unless --keep-config)
    if (!options.keepConfig) {
      spinner.text = 'Removing from configuration...';
      removeService(name);
      
      if (options.cleanLogs) {
        spinner.succeed(chalk.green(`Service "${service.name}" removed completely (including logs)`));
      } else {
        spinner.succeed(chalk.green(`Service "${service.name}" removed completely`));
        console.log(chalk.dim(`Tip: Use --clean-logs to also remove log files.`));
      }
    } else {
      spinner.succeed(chalk.green(`Service "${service.name}" uninstalled from launchd`));
      console.log(chalk.dim('Configuration retained. Run `sm start ' + name + '` to reinstall.'));
    }
    
  } catch (err) {
    spinner.fail(chalk.red(err.message));
    process.exit(1);
  }
}
