import {
  chmod,
  chown,
  lstat,
  mkdir,
  open,
  readdir,
  realpath,
  rename,
  rm,
  stat
} from 'node:fs/promises'
import { createReadStream } from 'node:fs'
import { execFile } from 'node:child_process'
import { promisify } from 'node:util'
import { basename, dirname, join, sep } from 'node:path'
import { randomBytes } from 'node:crypto'
import { getSite, isSitePendingDelete, type SiteRecord } from './sites'
import { getAppDirSizeBytes, readSiteResources } from './site-resources'
import { siteAppDir } from './site-env'

const execFileAsync = promisify(execFile)

export const MAX_UPLOAD_BYTES = 64 * 1024 * 1024
export const MAX_PREVIEW_TEXT_BYTES = 256 * 1024
export const MAX_PREVIEW_IMAGE_BYTES = 10 * 1024 * 1024
export const MAX_LIST_ENTRIES = 2000
export const MAX_DELETE_BULK = 50
export const HOST_DISK_RESERVE_BYTES = 100 * 1024 * 1024
const PHP_FPM_UID = 82
const PHP_FPM_GID = 82

export const HEAVY_DIR_NAMES = new Set(['node_modules', '.git', '.output', 'vendor'])

export const SENSITIVE_NAMES = new Set([
  '.env',
  '.git',
  '.output',
  'node_modules',
  'package.json',
  'composer.json',
  'wp-config.php',
  'public',
  'vendor'
])

const IMAGE_EXT = new Set(['.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp', '.ico'])

export type JailTarget = {
  domain: string
  rel: string
  abs: string
  root: string
  site: SiteRecord
}

export type FileEntry = {
  name: string
  type: 'file' | 'dir'
  size: number | null
  mtime: string | null
  mode: string
  symlink: boolean
  escaped: boolean
  heavy: boolean
}

function fail(statusCode: number, statusMessage: string): never {
  throw createError({ statusCode, statusMessage })
}

export function panelDomain(): string {
  return String(process.env.PANEL_DOMAIN || '').trim().toLowerCase()
}

export function isPanelSite(domain: string): boolean {
  const p = panelDomain()
  return !!p && domain.toLowerCase() === p
}

/** `.output` / `node_modules` on the panel site — deleting them kills SSR. */
export function isPanelProtectedRel(rel: string): boolean {
  const first = rel.split('/').find((s) => s.length > 0) || ''
  return first === '.output' || first === 'node_modules'
}

export function isSensitiveName(name: string): boolean {
  return SENSITIVE_NAMES.has(name)
}

export function normalizeRelPath(raw: unknown): string {
  const s = String(raw ?? '')
    .replace(/\\/g, '/')
    .replace(/^\//, '')
    .replace(/\/+$/, '')
  if (s.includes('\0')) fail(400, 'Invalid path')
  if (!s || s === '.') return ''
  const parts = s.split('/')
  for (const p of parts) {
    if (!p || p === '.' || p === '..') fail(400, 'Invalid path')
  }
  return parts.join('/')
}

export function safeBasename(raw: unknown): string {
  const s = String(raw ?? '').replace(/\\/g, '/')
  if (s.includes('\0')) fail(400, 'Invalid filename')
  const base = s.split('/').pop()?.trim() || ''
  if (!base || base === '.' || base === '..') fail(400, 'Invalid filename')
  if (base.includes('/') || base.includes('\\')) fail(400, 'Invalid filename')
  return base
}

function isInsideRoot(root: string, target: string): boolean {
  if (target === root) return true
  const prefix = root.endsWith(sep) ? root : root + sep
  return target.startsWith(prefix)
}

async function realRootFor(domain: string): Promise<{ logical: string; root: string }> {
  const logical = siteAppDir(domain)
  try {
    const root = await realpath(logical)
    return { logical, root }
  } catch (e: unknown) {
    const err = e as NodeJS.ErrnoException
    if (err.code === 'ENOENT') fail(404, `App directory not found: apps/${domain}/`)
    fail(500, `Cannot resolve apps/${domain}/: ${err.message || 'unknown error'}`)
  }
}

/** Resolve an existing path (or the deepest existing ancestor) and keep it inside the jail. */
async function resolveExistingInJail(
  root: string,
  abs: string
): Promise<{ real: string; missing: string[] }> {
  let current = abs
  const missing: string[] = []
  for (;;) {
    try {
      const lst = await lstat(current)
      if (lst.isSymbolicLink()) {
        const real = await realpath(current)
        if (!isInsideRoot(root, real)) fail(403, 'Path escapes site directory')
        return { real, missing: missing.reverse() }
      }
      const real = await realpath(current)
      if (!isInsideRoot(root, real)) fail(403, 'Path escapes site directory')
      return { real, missing: missing.reverse() }
    } catch (e: unknown) {
      const err = e as NodeJS.ErrnoException & { statusCode?: number }
      if (err.statusCode) throw e
      if (err.code !== 'ENOENT') {
        if (err.code === 'EACCES' || err.code === 'EPERM') fail(403, 'Permission denied')
        fail(500, err.message || 'Cannot resolve path')
      }
      const parent = dirname(current)
      if (parent === current) fail(404, 'Path not found')
      missing.push(basename(current))
      current = parent
    }
  }
}

export async function resolveJailPath(
  domain: string,
  relRaw: unknown,
  opts: { mustExist?: boolean } = {}
): Promise<JailTarget> {
  const site = await getSite(domain)
  const rel = normalizeRelPath(relRaw)
  const { logical, root } = await realRootFor(domain)
  const abs = rel ? join(logical, ...rel.split('/')) : logical

  const { real, missing } = await resolveExistingInJail(root, abs)
  if (opts.mustExist && missing.length) fail(404, 'Path not found')
  if (missing.length) {
    for (const part of missing) {
      if (!part || part === '.' || part === '..') fail(400, 'Invalid path')
    }
    const next = join(real, ...missing)
    if (!isInsideRoot(root, next)) fail(403, 'Path escapes site directory')
    return { domain: site.domain, rel, abs: next, root, site }
  }
  return { domain: site.domain, rel, abs: real, root, site }
}

export function assertNotRoot(target: JailTarget): void {
  if (!target.rel) fail(400, 'Cannot modify the site root directory')
}

export function assertWritable(site: SiteRecord): void {
  if (isSitePendingDelete(site)) {
    fail(409, 'Site is pending delete — Restore it first, or wait for permanent removal')
  }
}

export function assertPanelSafe(domain: string, rel: string): void {
  if (isPanelSite(domain) && isPanelProtectedRel(rel)) {
    fail(403, 'Cannot modify panel .output or node_modules')
  }
}

async function applyOwnershipForSite(target: JailTarget, kind: 'file' | 'dir'): Promise<void> {
  const parent = target.rel ? dirname(target.abs) : target.root
  const rel = target.rel
  if (rel === '.env' || rel.endsWith('/.env')) {
    try {
      await chmod(target.abs, 0o600)
    } catch {
      /* ignore */
    }
    return
  }
  try {
    const st = await stat(parent)
    await chown(target.abs, st.uid, st.gid)
    if (kind === 'dir') {
      await chmod(target.abs, (st.mode & 0o777) || 0o755)
    } else {
      await chmod(target.abs, st.mode & 0o020 ? 0o664 : 0o644)
    }
    return
  } catch {
    /* fallback below */
  }
  if (target.site.runtime === 'php') {
    try {
      await chown(target.abs, PHP_FPM_UID, PHP_FPM_GID)
      await chmod(target.abs, kind === 'dir' ? 0o775 : 0o664)
    } catch {
      /* Windows / no cap */
    }
  }
}

async function hostAvailBytes(dir: string): Promise<number | null> {
  try {
    const { stdout } = await execFileAsync('df', ['-P', '-k', dir], { timeout: 10_000 })
    const lines = String(stdout)
      .trim()
      .split('\n')
      .filter((l) => l.trim())
    const row = lines[lines.length - 1]
    if (!row) return null
    const parts = row.split(/\s+/)
    const availK = Number.parseInt(parts[3] || '', 10)
    return Number.isFinite(availK) ? availK * 1024 : null
  } catch {
    return null
  }
}

export async function diskInfo(domain: string) {
  const [usedBytes, cfg, freeHostBytes] = await Promise.all([
    getAppDirSizeBytes(domain),
    readSiteResources(domain),
    hostAvailBytes(siteAppDir(domain))
  ])
  const limitBytes = cfg.diskGb > 0 ? cfg.diskGb * 1024 * 1024 * 1024 : 0
  return {
    usedBytes,
    limitBytes,
    freeHostBytes
  }
}

export async function assertUploadFits(domain: string, incomingBytes: number): Promise<void> {
  if (incomingBytes > MAX_UPLOAD_BYTES) {
    fail(413, `File too large (max ${MAX_UPLOAD_BYTES / 1024 / 1024} MB)`)
  }
  const disk = await diskInfo(domain)
  if (disk.limitBytes > 0 && disk.usedBytes != null) {
    if (disk.usedBytes + incomingBytes > disk.limitBytes) {
      fail(413, 'Upload would exceed this site’s disk limit')
    }
  }
  if (disk.freeHostBytes != null && incomingBytes + HOST_DISK_RESERVE_BYTES > disk.freeHostBytes) {
    fail(413, 'Not enough free disk space on the server')
  }
}

function modeString(mode: number): string {
  return (mode & 0o777).toString(8).padStart(3, '0')
}

function extLower(name: string): string {
  const i = name.lastIndexOf('.')
  return i >= 0 ? name.slice(i).toLowerCase() : ''
}

export function isImageName(name: string): boolean {
  return IMAGE_EXT.has(extLower(name))
}

export function imageContentType(name: string): string {
  switch (extLower(name)) {
    case '.jpg':
    case '.jpeg':
      return 'image/jpeg'
    case '.png':
      return 'image/png'
    case '.gif':
      return 'image/gif'
    case '.webp':
      return 'image/webp'
    case '.bmp':
      return 'image/bmp'
    case '.ico':
      return 'image/x-icon'
    default:
      return 'application/octet-stream'
  }
}

export async function hasPublicDir(domain: string): Promise<boolean> {
  try {
    const t = await resolveJailPath(domain, 'public', { mustExist: true })
    const st = await lstat(t.abs)
    if (st.isSymbolicLink()) {
      const real = await realpath(t.abs)
      if (!isInsideRoot(t.root, real)) return false
      return (await stat(t.abs)).isDirectory()
    }
    return st.isDirectory()
  } catch {
    return false
  }
}

export async function listDir(domain: string, relRaw: unknown) {
  const target = await resolveJailPath(domain, relRaw, { mustExist: true })
  let lst
  try {
    lst = await lstat(target.abs)
  } catch (e: unknown) {
    const err = e as NodeJS.ErrnoException
    if (err.code === 'ENOENT') fail(404, 'Path not found')
    fail(500, err.message || 'Cannot stat path')
  }

  if (lst.isSymbolicLink()) {
    const real = await realpath(target.abs)
    if (!isInsideRoot(target.root, real)) fail(403, 'Path escapes site directory')
    const st = await stat(target.abs)
    if (!st.isDirectory()) fail(400, 'Not a directory')
  } else if (!lst.isDirectory()) {
    fail(400, 'Not a directory')
  }

  let names: string[]
  try {
    names = await readdir(target.abs)
  } catch (e: unknown) {
    const err = e as NodeJS.ErrnoException
    if (err.code === 'EACCES' || err.code === 'EPERM') fail(403, 'Permission denied')
    fail(500, err.message || 'Cannot read directory')
  }

  names.sort((a, b) => a.localeCompare(b))
  const truncated = names.length > MAX_LIST_ENTRIES
  if (truncated) names = names.slice(0, MAX_LIST_ENTRIES)

  const entries: FileEntry[] = []
  for (const name of names) {
    const childAbs = join(target.abs, name)
    let info
    try {
      info = await lstat(childAbs)
    } catch {
      continue
    }
    let type: 'file' | 'dir' = info.isDirectory() ? 'dir' : 'file'
    const symlink = info.isSymbolicLink()
    let escaped = false
    let size: number | null = info.isDirectory() ? null : info.size
    let mtime: string | null = info.mtime ? info.mtime.toISOString() : null
    let mode = modeString(info.mode)

    if (symlink) {
      try {
        const real = await realpath(childAbs)
        if (!isInsideRoot(target.root, real)) {
          escaped = true
          type = 'file'
          size = null
        } else {
          const followed = await stat(childAbs)
          type = followed.isDirectory() ? 'dir' : 'file'
          size = followed.isDirectory() ? null : followed.size
          mtime = followed.mtime ? followed.mtime.toISOString() : mtime
          mode = modeString(followed.mode)
        }
      } catch {
        escaped = true
        type = 'file'
        size = null
      }
    }

    entries.push({
      name,
      type,
      size,
      mtime,
      mode,
      symlink,
      escaped,
      heavy: type === 'dir' && HEAVY_DIR_NAMES.has(name)
    })
  }

  entries.sort((a, b) => {
    if (a.type !== b.type) return a.type === 'dir' ? -1 : 1
    return a.name.localeCompare(b.name)
  })

  const [disk, publicDir] = await Promise.all([diskInfo(domain), hasPublicDir(domain)])

  return {
    ok: true as const,
    domain: target.site.domain,
    runtime: target.site.runtime,
    path: target.rel,
    pendingDelete: isSitePendingDelete(target.site),
    isPanel: isPanelSite(target.site.domain),
    hasGithub: !!(target.site.githubUrl || '').trim(),
    hasPublicDir: publicDir,
    truncated,
    entries,
    disk
  }
}

export async function mkdirInSite(domain: string, relRaw: unknown) {
  const target = await resolveJailPath(domain, relRaw, { mustExist: false })
  assertWritable(target.site)
  assertNotRoot(target)
  assertPanelSafe(domain, target.rel)
  try {
    await mkdir(target.abs, { recursive: false })
  } catch (e: unknown) {
    const err = e as NodeJS.ErrnoException
    if (err.code === 'EEXIST') fail(409, 'Already exists')
    if (err.code === 'ENOENT') fail(404, 'Parent directory not found')
    if (err.code === 'EACCES' || err.code === 'EPERM') fail(403, 'Permission denied')
    fail(500, err.message || 'Cannot create directory')
  }
  await applyOwnershipForSite(target, 'dir')
  return { ok: true as const, path: target.rel }
}

export async function renameInSite(domain: string, fromRaw: unknown, toRaw: unknown) {
  const from = await resolveJailPath(domain, fromRaw, { mustExist: true })
  assertWritable(from.site)
  assertNotRoot(from)
  assertPanelSafe(domain, from.rel)

  const to = await resolveJailPath(domain, toRaw, { mustExist: false })
  assertNotRoot(to)
  assertPanelSafe(domain, to.rel)
  if (from.abs === to.abs) return { ok: true as const, from: from.rel, to: to.rel }

  if (isInsideRoot(from.abs, to.abs) && to.abs !== from.abs) {
    fail(400, 'Cannot move a folder into itself')
  }

  try {
    await lstat(to.abs)
    fail(409, 'Destination already exists')
  } catch (e: unknown) {
    const err = e as NodeJS.ErrnoException & { statusCode?: number }
    if (err.statusCode) throw e
    if (err.code !== 'ENOENT') fail(500, err.message || 'Cannot stat destination')
  }

  try {
    await rename(from.abs, to.abs)
  } catch (e: unknown) {
    const err = e as NodeJS.ErrnoException
    if (err.code === 'ENOENT') fail(404, 'Path not found')
    if (err.code === 'EACCES' || err.code === 'EPERM') fail(403, 'Permission denied')
    fail(500, err.message || 'Cannot rename')
  }
  return { ok: true as const, from: from.rel, to: to.rel }
}

export async function deleteInSite(domain: string, pathsRaw: unknown) {
  const site = await getSite(domain)
  assertWritable(site)
  const list = Array.isArray(pathsRaw) ? pathsRaw : [pathsRaw]
  if (!list.length) fail(400, 'paths is required')
  if (list.length > MAX_DELETE_BULK) fail(400, `Too many paths (max ${MAX_DELETE_BULK})`)

  const deleted: string[] = []
  for (const p of list) {
    const target = await resolveJailPath(domain, p, { mustExist: true })
    assertNotRoot(target)
    assertPanelSafe(domain, target.rel)
    try {
      await rm(target.abs, { recursive: true, force: false })
    } catch (e: unknown) {
      const err = e as NodeJS.ErrnoException
      if (err.code === 'ENOENT') fail(404, `Not found: ${target.rel || '/'}`)
      if (err.code === 'EACCES' || err.code === 'EPERM') fail(403, 'Permission denied')
      fail(500, err.message || 'Cannot delete')
    }
    deleted.push(target.rel)
  }
  return { ok: true as const, deleted }
}

export async function openFileForRead(domain: string, relRaw: unknown) {
  const target = await resolveJailPath(domain, relRaw, { mustExist: true })
  let lst
  try {
    lst = await lstat(target.abs)
  } catch {
    fail(404, 'Path not found')
  }
  if (lst.isSymbolicLink()) {
    const real = await realpath(target.abs)
    if (!isInsideRoot(target.root, real)) fail(403, 'Path escapes site directory')
    const st = await stat(target.abs)
    if (!st.isFile()) fail(400, 'Not a file')
    return { target, size: st.size, mtime: st.mtime }
  }
  if (!lst.isFile()) fail(400, 'Not a file')
  return { target, size: lst.size, mtime: lst.mtime }
}

export function fileReadStream(abs: string) {
  return createReadStream(abs)
}

export async function previewText(domain: string, relRaw: unknown) {
  const { target, size } = await openFileForRead(domain, relRaw)
  if (size > MAX_PREVIEW_TEXT_BYTES) {
    fail(413, `File too large to preview (max ${MAX_PREVIEW_TEXT_BYTES / 1024} KB)`)
  }
  const fh = await open(target.abs, 'r')
  try {
    const buf = Buffer.alloc(Math.min(size, MAX_PREVIEW_TEXT_BYTES))
    const { bytesRead } = await fh.read(buf, 0, buf.length, 0)
    const slice = buf.subarray(0, bytesRead)
    if (slice.includes(0)) fail(415, 'Binary file — download instead')
    return {
      ok: true as const,
      kind: 'text' as const,
      path: target.rel,
      name: basename(target.rel || target.domain),
      bytes: bytesRead,
      truncated: size > bytesRead,
      content: slice.toString('utf8')
    }
  } finally {
    await fh.close()
  }
}

export async function uploadToDir(
  domain: string,
  dirRelRaw: unknown,
  filename: string,
  data: Buffer
) {
  const dir = await resolveJailPath(domain, dirRelRaw, { mustExist: true })
  assertWritable(dir.site)
  const name = safeBasename(filename)
  const rel = dir.rel ? `${dir.rel}/${name}` : name
  assertPanelSafe(domain, rel)
  await assertUploadFits(domain, data.byteLength)

  const dest = await resolveJailPath(domain, rel, { mustExist: false })
  try {
    await lstat(dest.abs)
    fail(409, `${name} already exists`)
  } catch (e: unknown) {
    const err = e as NodeJS.ErrnoException & { statusCode?: number }
    if (err.statusCode) throw e
    if (err.code !== 'ENOENT') fail(500, err.message || 'Cannot stat destination')
  }

  const tmpAbs = join(dir.abs, `.${name}.uploading-${randomBytes(8).toString('hex')}`)
  try {
    const fh = await open(tmpAbs, 'w')
    try {
      await fh.write(data)
    } finally {
      await fh.close()
    }
    await applyOwnershipForSite({ ...dest, abs: tmpAbs, rel }, 'file')
    await rename(tmpAbs, dest.abs)
  } catch (e: unknown) {
    try {
      await rm(tmpAbs, { force: true })
    } catch {
      /* ignore */
    }
    const err = e as NodeJS.ErrnoException & { statusCode?: number }
    if (err.statusCode) throw e
    if (err.code === 'EACCES' || err.code === 'EPERM') fail(403, 'Permission denied')
    fail(500, err.message || 'Upload failed')
  }

  return { ok: true as const, path: dest.rel, name, bytes: data.byteLength }
}
