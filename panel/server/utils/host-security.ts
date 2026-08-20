import { parseScriptJson, runScript } from './stack'
import {
  appendSecurityEvent,
  readFail2banKnownIps,
  syncFail2banBanEvents,
  writeFail2banKnownIps
} from './security-events'

export type HostSecurityStatus = {
  ok: boolean
  fail2ban: {
    installed: boolean
    active: boolean
    jails: { name: string; bannedIps: string[] }[]
    bannedIps: string[]
  }
  clamav: {
    installed: boolean
    daemonActive: boolean
    freshclamActive: boolean
    signatureDate: string | null
  }
  error?: string
}

export async function fetchHostSecurityStatus(): Promise<HostSecurityStatus> {
  const raw = await runScript('host-security-status.sh', [], 90_000)
  const status = parseScriptJson<HostSecurityStatus>(raw)
  if (status.fail2ban?.installed && status.fail2ban.bannedIps?.length) {
    const known = readFail2banKnownIps()
    syncFail2banBanEvents(status.fail2ban.bannedIps, known)
    writeFail2banKnownIps(known)
  }
  return status
}

export async function installFail2ban(): Promise<HostSecurityStatus> {
  const raw = await runScript('host-fail2ban-install.sh', [], 300_000)
  const status = parseScriptJson<HostSecurityStatus>(raw)
  appendSecurityEvent({
    kind: 'security_install',
    source: 'panel',
    action: 'installed',
    detail: 'Fail2ban installed from panel'
  })
  return status
}

export async function installClamAv(): Promise<HostSecurityStatus> {
  const raw = await runScript('host-clamav-install.sh', [], 600_000)
  const status = parseScriptJson<HostSecurityStatus>(raw)
  appendSecurityEvent({
    kind: 'security_install',
    source: 'panel',
    action: 'installed',
    detail: 'ClamAV installed from panel'
  })
  return status
}

/** @deprecated Use installFail2ban + installClamAv separately from panel UI */
export async function installHostSecurity(): Promise<HostSecurityStatus> {
  const raw = await runScript('host-security-install.sh', [], 900_000)
  const status = parseScriptJson<HostSecurityStatus>(raw)
  appendSecurityEvent({
    kind: 'security_install',
    source: 'panel',
    action: 'installed',
    detail: 'Fail2ban and ClamAV packages installed from panel'
  })
  return status
}

export type ClamScanResult = {
  ok: boolean
  target: string
  scanPath: string
  infectedCount: number
  infected: { path: string; domain: string | null; relPath: string; line: string }[]
  logTail?: string
  error?: string
}

export async function runClamScan(domain?: string): Promise<ClamScanResult> {
  const args = domain ? [domain] : []
  const raw = await runScript('host-clamav-scan.sh', args, 1_800_000)
  const result = parseScriptJson<ClamScanResult>(raw)
  for (const hit of result.infected || []) {
    appendSecurityEvent({
      kind: 'malware_found',
      source: 'clamav',
      domain: hit.domain,
      path: hit.relPath || hit.path,
      action: 'scan_infected',
      detail: hit.line
    })
  }
  return result
}
