import chalk from 'chalk';
import ora from 'ora';
import { loadConfig, addService, generateIdentifier, expandPath } from '../lib/config.js';
import { installService } from '../lib/launchd.js';
import { existsSync } from 'fs';

export async function addCommand(options) {
  const spinner = ora('Adding service...').start();
  
  try {
    const config = loadConfig();
    const { settings } = config;
    
    // Expand and validate path
    const servicePath = expandPath(options.path);
    if (!existsSync(servicePath)) {
      spinner.fail(`Path does not exist: ${servicePath}`);
      process.exit(1);
    }
    
    // Generate identifier
    const identifier = generateIdentifier(options.name, settings.identifierPrefix);
    
    // Build command array
    let command;
    if (options.cmd) {
      // Parse command string
      command = options.cmd.split(/\s+/);
    } else if (options.port) {
      // Default: npx vite with port
      command = ['npx', 'vite', '--port', String(options.port), '--host'];
    } else {
      command = ['npm', 'run', 'dev'];
    }
    
    // Build health check URL
    const healthCheck = options.health || 
      (options.port ? `http://localhost:${options.port}` : null);
    
    // Create service object
    const service = {
      name: options.name,
      identifier,
      path: servicePath,
      command,
      port: options.port || null,
      healthCheck,
      enabled: true,
      createdAt: new Date().toISOString()
    };
    
    spinner.text = 'Saving configuration...';
    
    // Add to config
    addService(service);
    
    // Install to launchd unless --no-install
    if (options.install !== false) {
      spinner.text = 'Installing to launchd...';
      const { destPath } = installService(service);
      
      spinner.succeed(chalk.green(`Service "${options.name}" added and installed!`));
      console.log('');
      console.log(chalk.dim('  Identifier:'), identifier);
      console.log(chalk.dim('  Path:'), servicePath);
      console.log(chalk.dim('  Command:'), command.join(' '));
      if (options.port) {
        console.log(chalk.dim('  Port:'), options.port);
      }
      console.log(chalk.dim('  Plist:'), destPath);
      console.log('');
      console.log(chalk.cyan('The service should start automatically.'));
      console.log(chalk.dim(`Run 'sm status ${options.name}' to check.`));
    } else {
      spinner.succeed(chalk.green(`Service "${options.name}" added to config`));
      console.log(chalk.yellow('Run `sm start ' + options.name + '` to install and start.'));
    }
    
  } catch (err) {
    spinner.fail(chalk.red(err.message));
    process.exit(1);
  }
}
