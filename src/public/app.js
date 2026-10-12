// Ephemeral PR Preview Client Script
document.addEventListener('DOMContentLoaded', () => {
  const btnHealth = document.getElementById('btn-health');
  const btnInfo = document.getElementById('btn-info');
  const consoleOutput = document.getElementById('console-output');
  const consoleEndpoint = document.getElementById('console-endpoint');
  const latencyBadge = document.getElementById('latency-badge');

  async function fetchEndpoint(endpoint) {
    consoleEndpoint.textContent = endpoint;
    latencyBadge.textContent = 'Testing...';
    consoleOutput.textContent = '// Querying ' + endpoint + ' ...';

    const startTime = performance.now();
    try {
      // Relative fetch: automatically inherits <base href="...">
      const response = await fetch(endpoint, {
        headers: { 'Accept': 'application/json' }
      });
      const latency = Math.round(performance.now() - startTime);
      const data = await response.json();

      latencyBadge.textContent = `${response.status} ${response.statusText} (${latency}ms)`;
      latencyBadge.style.color = response.ok ? '#10b981' : '#ef4444';
      consoleOutput.textContent = JSON.stringify(data, null, 2);
    } catch (err) {
      const latency = Math.round(performance.now() - startTime);
      latencyBadge.textContent = `Error (${latency}ms)`;
      latencyBadge.style.color = '#ef4444';
      consoleOutput.textContent = JSON.stringify({
        error: 'Network Request Failed',
        message: err.message,
        tip: 'Ensure preview container is running and reverse proxy routes are active.'
      }, null, 2);
    }
  }

  if (btnHealth) {
    btnHealth.addEventListener('click', () => fetchEndpoint('health'));
  }

  if (btnInfo) {
    btnInfo.addEventListener('click', () => fetchEndpoint('api/info'));
  }

  // Initial health check on page load
  fetchEndpoint('health');
});
