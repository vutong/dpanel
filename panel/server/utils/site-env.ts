import { readFile, writeFile, mkdir, access, stat } from 'node:fs/promises'
import { join } from 'node:path'
import { assertNodeSite, normalizeSiteDomain } from './sites'
import { stackRoot } from './stack'

export { normalizeSiteDomain, assertNodeSite }
export const MAX_SITE_ENV_BYTES = 64 * 1024

export function siteAppDir(domain: string): string {
  return join(stackRoot(), 'apps', domain)
}

export function siteEnvFilePath(domain: string): string {
  return join(siteAppDir(domain), '.env')
}

function envReadError(domain: string, envPath: string, err: NodeJS.ErrnoException): never {
  if (err.code === 'EACCES' || err.code === 'EPERM') {
    throw createError({
      statusCode: 403,
      statusMessage: `Cannot read apps/${domain}/.env (permission denied). On VPS: chmod 640 ${envPath}`
    })
  }
  if (err.code === 'EISDIR') {
    throw createError({
      statusCode: 500,
      statusMessage: `apps/${domain}/.env is a directory, not a file`
    })
  }
  throw createError({
    statusCode: 500,
    statusMessage: `Cannot read apps/${domain}/.env: ${err.message || 'unknown error'}`
  })
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
  let bytes = 0
  try {
    const info = await stat(envPath)
    if (!info.isFile()) {
      throw createError({
        statusCode: 500,
        statusMessage: `apps/${domain}/.env is not a regular file`
      })
    }
    const buf = await readFile(envPath)
    exists = true
    content = buf.toString('utf8')
    bytes = buf.byteLength
  } catch (e: unknown) {
    const err = e as NodeJS.ErrnoException & { statusCode?: number }
    if (err.statusCode) throw e
    if (err.code === 'ENOENT') {
      exists = false
    } else {
      envReadError(domain, envPath, err)
    }
  }

  return {
    ok: true as const,
    domain,
    path: `apps/${domain}/.env`,
    exists,
    bytes,
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
    exists: true,
    bytes: Buffer.byteLength(normalized, 'utf8')
  }
}
