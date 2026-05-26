import { readFile, writeFile, mkdir, access } from 'node:fs/promises'
import { join } from 'node:path'
import { stackRoot } from './stack'

const DOMAIN_RE = /^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$/
export const MAX_SITE_ENV_BYTES = 64 * 1024

export function normalizeSiteDomain(raw: string): string {
  const domain = raw.trim().toLowerCase()
  if (!domain || !DOMAIN_RE.test(domain)) {
    throw createError({ statusCode: 400, statusMessage: 'Invalid domain' })
  }
  return domain
}

export async function assertNodeSite(domain: string) {
  const sitesPath = join(stackRoot(), 'data/panel', 'sites.json')
  let sites: { domain?: string; runtime?: string }[]
  try {
    sites = JSON.parse(await readFile(sitesPath, 'utf8')) as { domain?: string; runtime?: string }[]
  } catch {
    throw createError({ statusCode: 500, statusMessage: 'sites.json not found' })
  }
  const site = sites.find((s) => (s.domain || '').toLowerCase() === domain)
  if (!site) {
    throw createError({ statusCode: 404, statusMessage: 'Site not found' })
  }
  if (site.runtime !== 'node') {
    throw createError({ statusCode: 400, statusMessage: '.env editor is only available for Node sites' })
  }
}

export function siteAppDir(domain: string): string {
  return join(stackRoot(), 'apps', domain)
}

export function siteEnvFilePath(domain: string): string {
  return join(siteAppDir(domain), '.env')
}

export async function readSiteEnv(domain: string) {
  await assertNodeSite(domain)
  const appDir = siteAppDir(domain)
  const envPath = siteEnvFilePath(domain)
  try {
    await access(appDir)
  } catch {
    throw createError({ statusCode: 404, statusMessage: `App directory not found: apps/${domain}/` })
  }

  let exists = false
  let content = ''
  try {
    const buf = await readFile(envPath)
    exists = true
    content = buf.toString('utf8')
  } catch {
    exists = false
  }

  return {
    ok: true as const,
    domain,
    path: `apps/${domain}/.env`,
    exists,
    content
  }
}

export async function writeSiteEnv(domain: string, content: string) {
  await assertNodeSite(domain)
  const appDir = siteAppDir(domain)
  const envPath = siteEnvFilePath(domain)

  if (typeof content !== 'string') {
    throw createError({ statusCode: 400, statusMessage: 'content must be a string' })
  }
  if (Buffer.byteLength(content, 'utf8') > MAX_SITE_ENV_BYTES) {
    throw createError({
      statusCode: 400,
      statusMessage: `.env too large (max ${MAX_SITE_ENV_BYTES / 1024} KB)`
    })
  }
  if (content.includes('\0')) {
    throw createError({ statusCode: 400, statusMessage: 'Invalid .env content' })
  }

  try {
    await access(appDir)
  } catch {
    throw createError({ statusCode: 404, statusMessage: `App directory not found: apps/${domain}/` })
  }

  await mkdir(appDir, { recursive: true })
  const normalized = content.endsWith('\n') || content.length === 0 ? content : `${content}\n`
  await writeFile(envPath, normalized, { mode: 0o600, encoding: 'utf8' })

  return {
    ok: true as const,
    domain,
    path: `apps/${domain}/.env`,
    bytes: Buffer.byteLength(normalized, 'utf8')
  }
}
