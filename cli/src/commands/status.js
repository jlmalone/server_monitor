import chalk from 'chalk';
import { loadConfig, getService, expandPath } from '../lib/config.js';
import { getServiceStatus } from '../lib/launchd.js';
import { getServiceHealth } from '../lib/health.js';
import { statSync } from 'fs';
import { join } from 'path';

export async function statusCommand(name, options) {
  const config = loadConfig();
  
  // If name provided, show detailed status for one service
  if (name) {
    const service = getService(name);
    if (!service) {
      console.log(chalk.red(`Service "${name}" not found`));
      process.exit(1);
    }
    
    await showDetailedStatus(service, config.settings, options.json);
    return;
  }
  
  // Show overview of all services
  const services = [];
  
  for (const service of config.services) {
    const launchdStatus = getServiceStatus(service.identifier);
    const health = await getServiceHealth(service, launchdStatus);
    services.push(health);
  }
  
  if (options.json) {
    console.log(JSON.stringify(services, null, 2));
    return;
  }
  
  console.log('');
  console.log(chalk.bold.cyan('╔══════════════════════════════════════════════════════════════╗'));
  console.log(chalk.bold.cyan('║              🖥️  SERVER MONITOR STATUS                        ║'));
  console.log(chalk.bold.cyan('╚══════════════════════════════════════════════════════════════╝'));
  console.log('');
  console.log(chalk.dim(`Timestamp: ${new Date().toLocaleString()}`));
  console.log('');
  
  for (const health of services) {
    printHealthStatus(health);
  }
  
  // Summary
  const healthy = services.filter(s => s.status === 'healthy').length;
  const total = services.length;
  
  console.log(chalk.bold.blue('═══ Summary ═══'));
  console.log(`  Total services: ${total}`);
  console.log(`  Healthy:        ${chalk.green(healthy)}`);
  console.log(`  Issues:         ${chalk[healthy === total ? 'green' : 'yellow'](total - healthy)}`);
  console.log('');
  
  if (healthy === total) {
    console.log(chalk.green('  ✓ All services healthy!'));
  } else {
    console.log(chalk.yellow('  ⚠ Some services need attention'));
  }
  console.log('');
}

async function showDetailedStatus(service, settings, asJson) {
  const launchdStatus = getServiceStatus(service.identifier);
  const health = await getServiceHealth(service, launchdStatus);
  
  if (asJson) {
    console.log(JSON.stringify({ service, health }, null, 2));
    return;
  }
  
  console.log('');
  console.log(chalk.bold.cyan(`═══ ${service.name} ═══`));
  console.log('');
  
  // Basic info
  console.log(chalk.dim('Identifier:    '), service.identifier);
  console.log(chalk.dim('Path:          '), service.path);
  console.log(chalk.dim('Command:       '), Array.isArray(service.command) ? service.command.join(' ') : service.command);
  console.log(chalk.dim('Port:          '), service.port || 'N/A');
  console.log(chalk.dim('Health URL:    '), service.healthCheck || 'N/A');
  console.log('');
  
  // launchd status
  console.log(chalk.bold('LaunchD Status'));
  if (!launchdStatus.loaded) {
    console.log(chalk.red('  ○ Not installed'));
  } else if (launchdStatus.running) {
    console.log(chalk.green('  ● Running'), chalk.dim(`(PID: ${launchdStatus.pid})`));
  } else {
    console.log(chalk.red('  ○ Stopped'), chalk.dim(`(exit: ${launchdStatus.exitStatus})`));
  }
  console.log('');
  
  // Port status
  if (health.portCheck) {
    console.log(chalk.bold('Port Status'));
    if (health.portCheck.listening) {
      console.log(chalk.green(`  ● Port ${service.port} listening`), 
        health.portCheck.pid ? chalk.dim(`(PID: ${health.portCheck.pid})`) : '');
    } else {
      console.log(chalk.yellow(`  ○ Port ${service.port} not listening`));
    }
    console.log('');
  }
  
  // Health check
  if (health.httpCheck) {
    console.log(chalk.bold('Health Check'));
    if (health.httpCheck.healthy) {
      console.log(chalk.green('  ● Responding'), chalk.dim(`(${health.httpCheck.status} ${health.httpCheck.statusText || ''})`));
    } else {
      console.log(chalk.red('  ○ Not responding'), chalk.dim(`(${health.httpCheck.error || 'failed'})`));
    }
    console.log('');
  }
  
  // Log files
  const logDir = expandPath(settings.logDir);
  const shortName = service.identifier.split('.').pop();
  const logFile = join(logDir, `${shortName}.log`);
  const errorFile = join(logDir, `${shortName}.error.log`);
  
  console.log(chalk.bold('Log Files'));
  try {
    const logStat = statSync(logFile);
    console.log(chalk.dim('  stdout:'), logFile);
    console.log(chalk.dim('         '), `${formatBytes(logStat.size)}, modified ${logStat.mtime.toLocaleString()}`);
  } catch {
    console.log(chalk.dim('  stdout:'), 'N/A');
  }
  try {
    const errStat = statSync(errorFile);
    console.log(chalk.dim('  stderr:'), errorFile);
    console.log(chalk.dim('         '), `${formatBytes(errStat.size)}, modified ${errStat.mtime.toLocaleString()}`);
  } catch {
    console.log(chalk.dim('  stderr:'), 'N/A');
  }
  console.log('');
  
  // Overall status
  console.log(chalk.bold('Overall:'), getStatusBadge(health.status));
  console.log('');
}

function printHealthStatus(health) {
  const statusIcon = getStatusIcon(health.status);
  
  console.log(chalk.bold(health.name));
  console.log(chalk.dim(`  Identifier: ${health.identifier}`));
  console.log(`  Status:     ${statusIcon}`);
  
  if (health.launchd.pid) {
    console.log(chalk.dim(`  PID:        ${health.launchd.pid}`));
  }
  if (health.port) {
    const portStatus = health.portCheck?.listening 
      ? chalk.green('● listening') 
      : chalk.yellow('○ not listening');
    console.log(`  Port:       ${health.port} ${portStatus}`);
  }
  if (health.httpCheck) {
    const httpStatus = health.httpCheck.healthy
      ? chalk.green('● responding')
      : chalk.red('○ not responding');
    console.log(`  Health:     ${httpStatus}`);
  }
  console.log('');
}

function getStatusIcon(status) {
  switch (status) {
    case 'healthy': return chalk.green('● Healthy');
    case 'running': return chalk.green('● Running');
    case 'starting': return chalk.yellow('◐ Starting');
    case 'unhealthy': return chalk.red('● Unhealthy');
    case 'stopped': return chalk.red('○ Stopped');
    case 'not_installed': return chalk.gray('○ Not installed');
    default: return chalk.gray('? Unknown');
  }
}

function getStatusBadge(status) {
  switch (status) {
    case 'healthy': return chalk.bgGreen.black(' HEALTHY ');
    case 'running': return chalk.bgGreen.black(' RUNNING ');
    case 'starting': return chalk.bgYellow.black(' STARTING ');
    case 'unhealthy': return chalk.bgRed.white(' UNHEALTHY ');
    case 'stopped': return chalk.bgRed.white(' STOPPED ');
    case 'not_installed': return chalk.bgGray.white(' NOT INSTALLED ');
    default: return chalk.bgGray.white(' UNKNOWN ');
  }
}

function formatBytes(bytes) {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}
