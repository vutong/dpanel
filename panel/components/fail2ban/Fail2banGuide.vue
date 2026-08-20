<template>
  <div class="guide">
    <details open class="guide-section">
      <summary>What Fail2ban does on this VPS</summary>
      <p>
        Fail2ban runs on the <strong>Ubuntu host</strong> (outside Docker). It watches log files and
        temporarily bans IP addresses that show repeated attack patterns — failed SSH logins, panel
        login brute force, or exploit scans against your websites.
      </p>
    </details>

    <details class="guide-section">
      <summary>Jail reference</summary>
      <table class="table guide-table">
        <thead>
          <tr>
            <th>Jail</th>
            <th>Log source</th>
            <th>Purpose</th>
          </tr>
        </thead>
        <tbody>
          <tr>
            <td><code>sshd</code></td>
            <td><code>/var/log/auth.log</code></td>
            <td>SSH brute-force protection</td>
          </tr>
          <tr>
            <td><code>nginx-dpanel-login</code></td>
            <td><code>/opt/stack/logs/nginx/access.log</code></td>
            <td>Bans IPs after repeated <code>POST /api/auth/login</code> → 401</td>
          </tr>
          <tr>
            <td><code>nginx-php-exploit</code></td>
            <td>Same nginx access log</td>
            <td>Scanners probing <code>.env</code>, <code>.git</code>, <code>wp-config</code>, etc.</td>
          </tr>
        </tbody>
      </table>
    </details>

    <details class="guide-section">
      <summary>Cloudflare and real client IP</summary>
      <p>
        Nginx is configured with Cloudflare <code>real_ip</code> headers so access logs record the
        visitor IP, not a Cloudflare edge IP. Fail2ban reads those logs — bans apply to the attacker,
        not Cloudflare.
      </p>
      <p>
        Panel access via raw IP on port <strong>8443</strong> uses the same nginx log; the
        <code>nginx-dpanel-login</code> jail covers that path too.
      </p>
    </details>

    <details class="guide-section">
      <summary>Whitelist with ignoreip</summary>
      <p>
        Add trusted IPs or CIDR ranges under <strong>Global whitelist (ignoreip)</strong> on the
        Jails &amp; Settings tab. These addresses are never banned by any jail.
      </p>
      <p>
        Recommended: add your office or home IP before tightening <code>sshd</code> limits. Use
        <strong>Add to whitelist</strong> for your current panel IP when unsure.
      </p>
    </details>

    <details class="guide-section">
      <summary>False positives and NAT</summary>
      <p>
        Multiple users behind one public IP (NAT, corporate gateway) share a ban. If legitimate users
        are blocked, unban the IP from the <strong>Banned IPs</strong> tab and add the range to
        <code>ignoreip</code>.
      </p>
      <p>
        For a mistaken SSH ban while you still have shell access, unban immediately and relax
        <code>sshd</code> settings.
      </p>
    </details>

    <details class="guide-section">
      <summary>App login rate limit vs Fail2ban</summary>
      <p>
        The panel also rate-limits login at the app layer: <strong>5 failed attempts per 15 minutes
        per IP</strong> → HTTP 429, stored in <code>data/panel/login-attempts.json</code>.
      </p>
      <p>
        Use <strong>both</strong> layers: rate limit slows attackers early; Fail2ban blocks at the
        firewall after repeated 401s in nginx logs (and protects SSH separately).
      </p>
    </details>

    <details class="guide-section">
      <summary>CLI fallback (SSH to VPS)</summary>
      <pre class="cli"><code># Status JSON
sudo bash /opt/stack/infra/scripts/host-security-status.sh

# Unban an IP from all jails
sudo bash /opt/stack/infra/scripts/host-fail2ban-unban.sh 203.0.113.10

# Unban from one jail
sudo bash /opt/stack/infra/scripts/host-fail2ban-unban.sh 203.0.113.10 sshd

# Reload after manual config edit
sudo fail2ban-client reload</code></pre>
    </details>

    <p class="muted foot">
      Config templates live in <code>infra/security/fail2ban/</code> in the dpanel repo. The panel
      regenerates host files when you save settings.
    </p>
  </div>
</template>

<style scoped>
.guide-section {
  margin-bottom: 0.75rem;
  border: 1px solid var(--border);
  border-radius: 8px;
  padding: 0.75rem 1rem;
  background: var(--surface-1, var(--surface));
}

.guide-section summary {
  cursor: pointer;
  font-weight: 600;
  font-size: 0.9375rem;
}

.guide-section p {
  margin: 0.75rem 0 0;
  font-size: 0.875rem;
  line-height: 1.55;
}

.guide-table {
  margin-top: 0.75rem;
  font-size: 0.8125rem;
}

.cli {
  margin: 0.75rem 0 0;
  padding: 0.75rem 1rem;
  background: var(--surface-2);
  border-radius: 6px;
  overflow-x: auto;
  font-size: 0.75rem;
}

.cli code {
  font-family: var(--font-mono, monospace);
}

.foot {
  font-size: 0.8125rem;
  margin-top: 1rem;
}
</style>
