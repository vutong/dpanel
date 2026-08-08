import { readFile, writeFile } from 'node:fs/promises'
import { join } from 'node:path'
import { stackRoot } from './stack'

export type SiteRecord = {
  domain: string
  runtime: string
  githubUrl?: string
  createdAt?: string
  /** ISO UTC — set when soft-deleted; purge after 24h */
  pendingDeleteAt?: string | null
}

export const SITE_PENDING_DELETE_HOURS = Math.max(
  1,
  Number(process.env.SITE_PENDING_DELETE_HOURS) || 24
)

export function pendingDeleteExpiresAt(pendingDeleteAt: string): string {
  const t = Date.parse(pendingDeleteAt)
  if (Number.isNaN(t)) return pendingDeleteAt
  return new Date(t + SITE_PENDING_DELETE_HOURS * 60 * 60 * 1000).toISOString()
}

export function isSitePendingDelete(site: SiteRecord): boolean {
  return !!(site.pendingDeleteAt || '').trim()
}

export function assertSiteNotPending(site: SiteRecord): void {
  if (isSitePendingDelete(site)) {
    throw createError({
      statusCode: 409,
      statusMessage: 'Site is pending delete — Restore it first, or wait for permanent removal'
    })
  }
}

export function withPendingMeta<T extends SiteRecord>(site: T) {
  const pending = (site.pendingDeleteAt || '').trim() || null
  return {
    ...site,
    pendingDeleteAt: pending,
    pendingDeleteExpiresAt: pending ? pendingDeleteExpiresAt(pending) : null
  }
}

const DOMAIN_RE = /^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$/
const GITHUB_URL_RE = /^https:\/\/github\.com\/[^/\s]+\/[^/\s]+?(?:\.git)?\/?$/i

export function normalizeSiteDomain(raw: string): string {
  const domain = raw.trim().toLowerCase()
  if (!domain || !DOMAIN_RE.test(domain)) {
    throw createError({ statusCode: 400, statusMessage: 'Invalid domain' })
  }
  return domain
}

export function normalizeGithubUrl(raw: string): string {
  const url = raw.trim().replace(/\/+$/, '')
  if (!url || !GITHUB_URL_RE.test(url)) {
    throw createError({
      statusCode: 400,
      statusMessage: 'Repository URL must be https://github.com/owner/repo'
    })
  }
  return url.endsWith('.git') ? url : `${url}.git`
}

function sitesPath() {
  return join(stackRoot(), 'data/panel', 'sites.json')
}

export async function readSitesRegistry(): Promise<SiteRecord[]> {
  try {
    const sites = JSON.parse(await readFile(sitesPath(), 'utf8')) as SiteRecord[]
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

export async function updateSiteGithubUrl(domain: string, githubUrl: string): Promise<SiteRecord> {
  const normalized = normalizeSiteDomain(domain)
  const url = normalizeGithubUrl(githubUrl)
  const sites = await readSitesRegistry()
  const idx = sites.findIndex((s) => (s.domain || '').toLowerCase() === normalized)
  if (idx < 0) {
    throw createError({ statusCode: 404, statusMessage: 'Site not found' })
  }
  sites[idx] = { ...sites[idx], githubUrl: url }
  await writeFile(sitesPath(), `${JSON.stringify(sites, null, 2)}\n`, 'utf8')
  return sites[idx]
}

export async function assertNodeSite(domain: string): Promise<SiteRecord> {
  const site = await getSite(domain)
  if (site.runtime !== 'node') {
    throw createError({ statusCode: 400, statusMessage: 'This action is only available for Node sites' })
  }
  return site
}
