import { randomBytes, timingSafeEqual } from 'node:crypto'
import { mkdir, readFile, writeFile } from 'node:fs/promises'
import { dirname, join } from 'node:path'
import bcrypt from 'bcryptjs'
import { stackRoot } from './stack'

export type ApiKeyPermission = 'read' | 'read_write'

export type ApiKeyRecord = {
  id: string
  key: string
  secretHash: string
  label: string
  permission: ApiKeyPermission
  createdAt: string
  updatedAt: string
}

export type ApiKeyPublic = Omit<ApiKeyRecord, 'secretHash'>

type ApiKeysFile = { keys: ApiKeyRecord[] }

function apiKeysPath(): string {
  return join(stackRoot(), 'data', 'panel', 'api-keys.json')
}

function nowIso(): string {
  return new Date().toISOString()
}

function normalizePermission(raw: unknown): ApiKeyPermission {
  const value = String(raw || '').trim()
  if (value === 'read') return 'read'
  return 'read_write'
}

function permissionRank(permission: ApiKeyPermission): number {
  return permission === 'read_write' ? 2 : 1
}

export function permissionSatisfies(
  actual: ApiKeyPermission,
  required: ApiKeyPermission,
): boolean {
  return permissionRank(actual) >= permissionRank(required)
}

async function readApiKeysFile(): Promise<ApiKeysFile> {
  try {
    const raw = JSON.parse(await readFile(apiKeysPath(), 'utf8')) as ApiKeysFile
    const keys = Array.isArray(raw?.keys) ? raw.keys : []
    return {
      keys: keys
        .filter((k) => k && typeof k.key === 'string' && typeof k.secretHash === 'string')
        .map((k) => ({
          id: String(k.id || ''),
          key: String(k.key),
          secretHash: String(k.secretHash),
          label: String(k.label || ''),
          permission: normalizePermission(k.permission),
          createdAt: String(k.createdAt || nowIso()),
          updatedAt: String(k.updatedAt || k.createdAt || nowIso()),
        }))
        .filter((k) => k.id && k.key),
    }
  } catch {
    return { keys: [] }
  }
}

async function writeApiKeysFile(data: ApiKeysFile): Promise<void> {
  const path = apiKeysPath()
  await mkdir(dirname(path), { recursive: true })
  await writeFile(path, JSON.stringify({ keys: data.keys }, null, 2), 'utf8')
}

function toPublic(record: ApiKeyRecord): ApiKeyPublic {
  return {
    id: record.id,
    key: record.key,
    label: record.label,
    permission: record.permission,
    createdAt: record.createdAt,
    updatedAt: record.updatedAt,
  }
}

function generateApiKey(): string {
  return `dpk_${randomBytes(24).toString('base64url')}`
}

function generateApiSecret(): string {
  return randomBytes(32).toString('base64url')
}

export async function listApiKeys(): Promise<ApiKeyPublic[]> {
  const file = await readApiKeysFile()
  return file.keys
    .map(toPublic)
    .sort((a, b) => String(b.createdAt).localeCompare(String(a.createdAt)))
}

export async function createApiKey(input: {
  label?: string
  permission?: unknown
}): Promise<ApiKeyPublic & { secret: string }> {
  const label = String(input.label || '').trim().slice(0, 120)
  const permission = normalizePermission(input.permission)
  const secret = generateApiSecret()
  const secretHash = await bcrypt.hash(secret, 10)
  const ts = nowIso()
  const record: ApiKeyRecord = {
    id: randomBytes(16).toString('hex'),
    key: generateApiKey(),
    secretHash,
    label: label || 'Untitled',
    permission,
    createdAt: ts,
    updatedAt: ts,
  }

  const file = await readApiKeysFile()
  file.keys.push(record)
  await writeApiKeysFile(file)

  return { ...toPublic(record), secret }
}

export async function updateApiKeyLabel(
  id: string,
  labelRaw: string,
): Promise<ApiKeyPublic> {
  const file = await readApiKeysFile()
  const idx = file.keys.findIndex((k) => k.id === id)
  if (idx < 0) {
    throw createError({ statusCode: 404, statusMessage: 'API key not found' })
  }
  const label = String(labelRaw || '').trim().slice(0, 120)
  if (!label) {
    throw createError({ statusCode: 400, statusMessage: 'Label is required' })
  }
  const current = file.keys[idx]!
  file.keys[idx] = {
    ...current,
    label,
    updatedAt: nowIso(),
  }
  await writeApiKeysFile(file)
  return toPublic(file.keys[idx]!)
}

export async function deleteApiKey(id: string): Promise<void> {
  const file = await readApiKeysFile()
  const next = file.keys.filter((k) => k.id !== id)
  if (next.length === file.keys.length) {
    throw createError({ statusCode: 404, statusMessage: 'API key not found' })
  }
  await writeApiKeysFile({ keys: next })
}

function safeEqualString(a: string, b: string): boolean {
  const left = Buffer.from(a)
  const right = Buffer.from(b)
  if (left.length !== right.length) return false
  return timingSafeEqual(left, right)
}

export async function verifyApiCredentials(
  apiKey: string,
  apiSecret: string,
): Promise<ApiKeyRecord | null> {
  const key = String(apiKey || '').trim()
  const secret = String(apiSecret || '').trim()
  if (!key || !secret) return null

  const file = await readApiKeysFile()
  const record = file.keys.find((k) => safeEqualString(k.key, key))
  if (!record) return null

  const ok = await bcrypt.compare(secret, record.secretHash)
  return ok ? record : null
}
