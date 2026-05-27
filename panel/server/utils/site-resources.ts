import { readFile, writeFile, mkdir, unlink, access } from 'node:fs/promises'
import { join } from 'node:path'
import { domainSlug, stackRoot } from './stack'

export type SiteResourcesConfig = {
  /** Max CPU cores (0 = no limit) */
  cpuLimit: number
  /** Max RAM in megabytes (0 = no limit) */
  memoryMb: number
  /** Max disk for app volume in GB (0 = no limit; best-effort via Docker storage_opt) */
  diskGb: number
}

const MAX_CPU = 64
const MAX_MEMORY_MB = 1024 * 1024
const MAX_DISK_GB = 10_000

export function resourcesConfigPath(domain: string): string {
  return join(stackRoot(), 'data', 'panel', 'site-resources', `${domainSlug(domain)}.json`)
}

function parseLimit(raw: unknown, max: number): number {
  const n = typeof raw === 'number' ? raw : Number.parseFloat(String(raw ?? ''))
  if (!Number.isFinite(n) || n < 0) return 0
  return Math.min(max, Math.round(n * 100) / 100)
}

export function resourcesConfigEmpty(cfg: SiteResourcesConfig): boolean {
  return cfg.cpuLimit <= 0 && cfg.memoryMb <= 0 && cfg.diskGb <= 0
}

export async function readSiteResources(domain: string): Promise<SiteResourcesConfig> {
  const path = resourcesConfigPath(domain)
  try {
    const raw = JSON.parse(await readFile(path, 'utf8')) as Partial<SiteResourcesConfig>
    return {
      cpuLimit: parseLimit(raw.cpuLimit, MAX_CPU),
      memoryMb: Math.floor(parseLimit(raw.memoryMb, MAX_MEMORY_MB)),
      diskGb: Math.floor(parseLimit(raw.diskGb, MAX_DISK_GB))
    }
  } catch {
    return { cpuLimit: 0, memoryMb: 0, diskGb: 0 }
  }
}

export async function writeSiteResources(domain: string, input: Partial<SiteResourcesConfig>) {
  const cfg: SiteResourcesConfig = {
    cpuLimit: parseLimit(input.cpuLimit, MAX_CPU),
    memoryMb: Math.floor(parseLimit(input.memoryMb, MAX_MEMORY_MB)),
    diskGb: Math.floor(parseLimit(input.diskGb, MAX_DISK_GB))
  }

  const path = resourcesConfigPath(domain)
  await mkdir(join(stackRoot(), 'data', 'panel', 'site-resources'), { recursive: true })

  if (resourcesConfigEmpty(cfg)) {
    try {
      await unlink(path)
    } catch {
      /* no file */
    }
    return cfg
  }

  await writeFile(path, JSON.stringify(cfg, null, 2) + '\n', { mode: 0o600, encoding: 'utf8' })
  return cfg
}

export async function getAppDirSizeBytes(domain: string): Promise<number | null> {
  const { execFile } = await import('node:child_process')
  const { promisify } = await import('node:util')
  const execFileAsync = promisify(execFile)
  const appDir = join(stackRoot(), 'apps', domain)
  try {
    await access(appDir)
  } catch {
    return null
  }
  try {
    const { stdout } = await execFileAsync('du', ['-sb', appDir], { timeout: 60_000 })
    const n = Number.parseInt(String(stdout).trim().split(/\s+/)[0] || '', 10)
    return Number.isFinite(n) ? n : null
  } catch {
    return null
  }
}
