import chalk from 'chalk';
import Table from 'cli-table3';
import { loadConfig } from '../lib/config.js';
import { getServiceStatus } from '../lib/launchd.js';

export async function listCommand(options) {
  const config = loadConfig();
  
  if (config.services.length === 0) {
    console.log(chalk.yellow('\nNo services configured.'));
    console.log(chalk.dim("Run 'sm add' to add a service.\n"));
    return;
  }
  
  // Gather status for all services
  const services = config.services.map(service => {
    const status = getServiceStatus(service.identifier);
    return { ...service, ...status };
  });
  
  if (options.json) {
    console.log(JSON.stringify(services, null, 2));
    return;
  }
  
  // Pretty table output
  console.log('');
  
  const table = new Table({
    head: [
      chalk.cyan('Service'),
      chalk.cyan('Port'),
      chalk.cyan('Status'),
      chalk.cyan('PID'),
      chalk.cyan('Identifier')
    ],
    style: {
      head: [],
      border: ['dim']
    }
  });
  
  for (const service of services) {
    let statusText;
    if (!service.loaded) {
      statusText = chalk.gray('○ Not installed');
    } else if (service.running) {
      statusText = chalk.green('● Running');
    } else {
      statusText = chalk.red('○ Stopped');
    }
    
    table.push([
      chalk.bold(service.name),
      service.port || chalk.dim('-'),
      statusText,
      service.pid || chalk.dim('-'),
      chalk.dim(service.identifier)
    ]);
  }
  
  console.log(table.toString());
  
  // Summary
  const running = services.filter(s => s.running).length;
  const total = services.length;
  
  console.log('');
  if (running === total) {
    console.log(chalk.green(`✓ All ${total} services running`));
  } else {
    console.log(chalk.yellow(`${running}/${total} services running`));
  }
  console.log('');
}
