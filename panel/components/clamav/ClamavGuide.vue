<template>
  <div class="guide">
    <details open class="guide-section">
      <summary>What ClamAV does on this VPS</summary>
      <p>
        ClamAV runs on the <strong>Ubuntu host</strong> (outside Docker). It scans website files under
        <code>/opt/stack/apps/</code> for known malware signatures. Use per-site scans on small VPS;
        full <code>apps/</code> scans can use significant CPU and RAM.
      </p>
    </details>

    <details class="guide-section">
      <summary>Services</summary>
      <table class="table guide-table">
        <thead>
          <tr>
            <th>Service</th>
            <th>Role</th>
          </tr>
        </thead>
        <tbody>
          <tr>
            <td><code>clamav-daemon</code></td>
            <td>Background scanner — enables faster <code>clamdscan</code></td>
          </tr>
          <tr>
            <td><code>clamav-freshclam</code></td>
            <td>Downloads signature updates (first run may take several minutes)</td>
          </tr>
        </tbody>
      </table>
      <p>
        If services show <strong>Inactive</strong> after install, use <strong>Start services</strong> on
        the Overview tab, then check the Logs tab.
      </p>
    </details>

    <details class="guide-section">
      <summary>Scan from panel</summary>
      <ul class="guide-list">
        <li><strong>Settings → ClamAV → Scan</strong> — all apps or pick one website</li>
        <li><strong>Websites → [domain] → Scan Virus</strong> — scan that site only</li>
        <li>Only one scan runs at a time (global lock)</li>
        <li>Results appear under <strong>Results</strong> when infected</li>
      </ul>
    </details>

    <details class="guide-section">
      <summary>Background scans</summary>
      <p>
        Scans run in the background so the panel stays responsive. After starting a scan, the modal or
        page polls until completion — do not expect instant results. Scan logs are under
        <code>logs/panel/clamav-scan-*.log</code>.
      </p>
    </details>

    <details class="guide-section">
      <summary>Not included yet</summary>
      <p>
        On-access scanning (clamonacc), automatic quarantine, and scheduled scans are planned — see
        <code>next-step-security.md</code>.
      </p>
    </details>

    <details class="guide-section">
      <summary>CLI fallback (SSH to VPS)</summary>
      <pre class="cli"><code># Status JSON
sudo bash /opt/stack/infra/scripts/host-security-status.sh

# Scan one site
sudo bash /opt/stack/infra/scripts/host-clamav-scan.sh example.com

# Scan all apps
sudo bash /opt/stack/infra/scripts/host-clamav-scan.sh

# Update signatures
sudo bash /opt/stack/infra/scripts/host-clamav-update.sh</code></pre>
    </details>

    <p class="muted foot">
      Scan history is stored in <code>data/panel/clamav-scans/</code> on the VPS.
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

.guide-list {
  margin: 0.75rem 0 0;
  padding-left: 1.25rem;
  font-size: 0.875rem;
  line-height: 1.55;
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

.muted {
  color: var(--muted);
}
</style>
