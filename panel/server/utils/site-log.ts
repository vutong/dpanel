import { execFile } from 'node:child_process'
import { writeFile, readFile } from 'node:fs/promises'
import { promisify } from 'node:util'
import { normalizeSiteDomain, assertNodeSite } from './site-env'
import { domainSlug, siteOpLogPath, stackRoot, type SiteLogKind } from './stack'

const execFileAsync = promisify(execFile)

async function composeProjectName(): Promise<string> {
  try {
    const raw = await readFile(`${stackRoot()}/.env`, 'utf8')
    const m = raw.match(/^COMPOSE_PROJECT_NAME=(.+)$/m)
    if (m?.[1]) return m[1].trim().replace(/^["']|["']$/g, '')
  } catch {
    /* use default */
  }
  return 'dpanel'
}

async function nuxtContainerNameAsync(domain: string): Promise<string> {
  const project = await composeProjectName()
  return `${project}-nuxt-${domainSlug(domain)}`
}

export async function clearSiteLog(domain: string, op: SiteLogKind) {
  const normalized = normalizeSiteDomain(domain)
  await assertNodeSite(normalized)

  if (op === 'container') {
    const cname = await nuxtContainerNameAsync(normalized)
    let logpath = ''
    try {
      const { stdout } = await execFileAsync('docker', ['inspect', '--format', '{{.LogPath}}', cname], {
        timeout: 15_000,
        maxBuffer: 1024 * 1024
      })
      logpath = stdout.trim()
    } catch {
      throw createError({
        statusCode: 404,
        statusMessage: `Container ${cname} not found — start the site or Rebuild first`
      })
    }
    if (!logpath) {
      throw createError({ statusCode: 500, statusMessage: `Could not resolve Docker log path for ${cname}` })
    }
    await writeFile(logpath, '', 'utf8')
    return { ok: true as const, domain: normalized, op, cleared: 'docker' as const }
  }

  const path = siteOpLogPath(normalized, op)
  await writeFile(path, '', 'utf8')
  return { ok: true as const, domain: normalized, op, path: path.replace(`${stackRoot()}/`, '') }
}
