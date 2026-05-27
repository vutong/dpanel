import { readFile } from 'node:fs/promises'
import { join } from 'node:path'
import { stackRoot } from './stack'

export type SiteRecord = {
  domain: string
  runtime: string
  githubUrl?: string
  createdAt?: string
}

const DOMAIN_RE = /^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$/

export function normalizeSiteDomain(raw: string): string {
  const domain = raw.trim().toLowerCase()
  if (!domain || !DOMAIN_RE.test(domain)) {
    throw createError({ statusCode: 400, statusMessage: 'Invalid domain' })
  }
  return domain
}

export async function readSitesRegistry(): Promise<SiteRecord[]> {
  const sitesPath = join(stackRoot(), 'data/panel', 'sites.json')
  try {
    const sites = JSON.parse(await readFile(sitesPath, 'utf8')) as SiteRecord[]
    return Array.isArray(sites) ? sites : []
  } catch {
    throw createError({ statusCode: 500, statusMessage: 'sites.json not found' })
  }
}

export async function getSite(domain: string): Promise<SiteRecord> {
  const normalized = normalizeSiteDomain(domain)
  const site = (await readSitesRegistry()).find((s) => (s.domain || '').toLowerCase() === normalized)
  if (!site?.domain) {
    throw createError({ statusCode: 404, statusMessage: 'Site not found' })
  }
  return site
}

export async function assertNodeSite(domain: string): Promise<SiteRecord> {
  const site = await getSite(domain)
  if (site.runtime !== 'node') {
    throw createError({ statusCode: 400, statusMessage: 'This action is only available for Node sites' })
  }
  return site
}
