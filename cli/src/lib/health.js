import { execSync } from 'child_process';

/**
 * Check if a port is listening
 */
export function checkPort(port) {
  try {
    // Use full path to lsof since it may not be in PATH
    const output = execSync(`/usr/sbin/lsof -i :${port} -P -n 2>/dev/null | grep LISTEN`, { 
      encoding: 'utf-8',
      timeout: 5000
    });
    
    if (output.trim()) {
      // Extract PID from lsof output
      const parts = output.trim().split(/\s+/);
      const pid = parts[1] ? parseInt(parts[1], 10) : null;
      return { listening: true, pid };
    }
  } catch (err) {
    // Port not in use or command failed
  }
  
  return { listening: false, pid: null };
}

/**
 * Perform an HTTP health check
 */
export async function checkHealth(url, timeoutMs = 3000) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  
  try {
    const response = await fetch(url, {
      signal: controller.signal,
      // For self-signed certs in development
      ...(url.startsWith('https') && {
        headers: { 'Accept': 'text/html,application/json' }
      })
    });
    
    clearTimeout(timeout);
    
    return {
      healthy: response.ok || response.status < 500,
      status: response.status,
      statusText: response.statusText
    };
  } catch (err) {
    clearTimeout(timeout);
    
    // For https with self-signed certs, try curl
    if (url.startsWith('https')) {
      return checkHealthWithCurl(url, timeoutMs);
    }
    
    return {
      healthy: false,
      status: null,
      error: err.code === 'ABORT_ERR' ? 'timeout' : err.message
    };
  }
}

/**
 * Use curl for HTTPS with self-signed certs
 */
function checkHealthWithCurl(url, timeoutMs = 3000) {
  try {
    const output = execSync(
      `curl -sk --max-time ${timeoutMs / 1000} -o /dev/null -w '%{http_code}' "${url}"`,
      { encoding: 'utf-8', timeout: timeoutMs + 1000 }
    );
    
    const status = parseInt(output.trim(), 10);
    return {
      healthy: status > 0 && status < 500,
      status,
      statusText: status === 200 ? 'OK' : `HTTP ${status}`
    };
  } catch (err) {
    return {
      healthy: false,
      status: null,
      error: 'connection failed'
    };
  }
}

/**
 * Get full service health info
 */
export async function getServiceHealth(service, launchdStatus) {
  const health = {
    name: service.name,
    identifier: service.identifier,
    port: service.port,
    launchd: launchdStatus,
    portCheck: null,
    httpCheck: null
  };
  
  // Check port if specified
  if (service.port) {
    health.portCheck = checkPort(service.port);
  }
  
  // HTTP health check if URL specified
  if (service.healthCheck) {
    health.httpCheck = await checkHealth(service.healthCheck);
  }
  
  // Determine overall status
  if (!launchdStatus.loaded) {
    health.status = 'not_installed';
  } else if (!launchdStatus.running) {
    health.status = 'stopped';
  } else if (health.portCheck && !health.portCheck.listening) {
    health.status = 'starting';
  } else if (health.httpCheck && !health.httpCheck.healthy) {
    health.status = 'unhealthy';
  } else {
    health.status = 'healthy';
  }
  
  return health;
}
