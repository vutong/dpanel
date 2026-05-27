import { readFile, writeFile, mkdir, unlink, access } from 'node:fs/promises'
import { join } from 'node:path'
import { domainSlug, stackRoot } from './stack'

const DOMAIN_RE = /^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$/

export type SiteRoutingConfig = {
  wildcardBase: string
  extraDomains: string[]
}

export function routingConfigPath(domain: string): string {
  return join(stackRoot(), 'data', 'panel', 'site-routing', `${domainSlug(domain)}.json`)
}

export function normalizeHostname(raw: string): string {
  const host = String(raw || '')
    .trim()
    .toLowerCase()
    .split(':')[0]!
    .replace(/[^a-z0-9.-]/g, '')
    .replace(/\.{2,}/g, '.')
    .replace(/^[.-]+|[.-]+$/g, '')
  if (!host || host.length > 253 || !DOMAIN_RE.test(host)) return ''
  return host
}

export function routingConfigEmpty(cfg: SiteRoutingConfig): boolean {
  return !cfg.wildcardBase && cfg.extraDomains.length === 0
}

export async function readSiteRouting(domain: string): Promise<SiteRoutingConfig> {
  const path = routingConfigPath(domain)
  try {
    const raw = JSON.parse(await readFile(path, 'utf8')) as {
      wildcardBase?: string
      extraDomains?: string[]
    }
    const wildcardBase = normalizeHostname(raw.wildcardBase || '')
    const extraDomains = Array.from(
      new Set(
        (raw.extraDomains || [])
          .map((d) => normalizeHostname(String(d)))
          .filter(Boolean)
      )
    )
    return { wildcardBase, extraDomains }
  } catch {
    return { wildcardBase: '', extraDomains: [] }
  }
}

export async function writeSiteRouting(domain: string, input: SiteRoutingConfig) {
  const siteDomain = normalizeHostname(domain)
  if (!siteDomain) {
    throw createError({ statusCode: 400, statusMessage: 'Invalid site domain' })
  }

  const wildcardBase = normalizeHostname(input.wildcardBase || '')
  const extraDomains = Array.from(
    new Set(
      (input.extraDomains || [])
        .map((d) => normalizeHostname(String(d)))
        .filter(Boolean)
    )
  )

  if (wildcardBase && wildcardBase === siteDomain) {
    throw createError({
      statusCode: 400,
      statusMessage: 'Wildcard base must differ from the site primary domain'
    })
  }

  for (const extra of extraDomains) {
    if (extra === siteDomain) {
      throw createError({
        statusCode: 400,
        statusMessage: 'Extra domain cannot be the same as the site domain'
      })
    }
  }

  const cfg: SiteRoutingConfig = { wildcardBase, extraDomains }
  const path = routingConfigPath(siteDomain)

  if (routingConfigEmpty(cfg)) {
    try {
      await unlink(path)
    } catch {
      /* no file yet */
    }
    return { ok: true as const, domain: siteDomain, routing: cfg, removed: true }
  }

  await mkdir(join(stackRoot(), 'data', 'panel', 'site-routing'), { recursive: true })
  await writeFile(
    path,
    JSON.stringify(
      {
        domain: siteDomain,
        wildcardBase,
        extraDomains,
        updatedAt: new Date().toISOString()
      },
      null,
      2
    ),
    'utf8'
  )

  return { ok: true as const, domain: siteDomain, routing: cfg, removed: false }
}

/** Hostnames nginx will accept for this Node site (for UI preview). */
export function computeServerNames(siteDomain: string, cfg: SiteRoutingConfig): string[] {
  const names = new Set<string>()
  const primary = normalizeHostname(siteDomain)
  if (primary) names.add(primary)
  if (cfg.wildcardBase) {
    names.add(cfg.wildcardBase)
    names.add(`www.${cfg.wildcardBase}`)
    names.add(`*.${cfg.wildcardBase}`)
  }
  for (const d of cfg.extraDomains) names.add(d)
  return [...names]
}

export async function routingConfigExists(domain: string): Promise<boolean> {
  try {
    await access(routingConfigPath(domain))
    return true
  } catch {
    return false
  }
}
