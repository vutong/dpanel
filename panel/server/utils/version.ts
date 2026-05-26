import { readFile } from 'node:fs/promises'
import { join } from 'node:path'
import { stackRoot } from './stack'

export async function getStackVersion(): Promise<string> {
  const root = stackRoot()

  try {
    const raw = await readFile(join(root, 'data/panel/version.json'), 'utf8')
    const data = JSON.parse(raw) as { version?: string }
    if (data.version) {
      return data.version
    }
  } catch {
    /* missing or invalid version.json */
  }

  try {
    const env = await readFile(join(root, '.env'), 'utf8')
    const match = env.match(/^DPANEL_VERSION=(.+)$/m)
    if (match?.[1]) {
      return match[1].trim()
    }
    const inst = env.match(/^INSTALLER_VERSION=(.+)$/m)
    if (inst?.[1]) {
      return inst[1].trim()
    }
  } catch {
    /* no .env */
  }

  return process.env.DPANEL_VERSION || process.env.INSTALLER_VERSION || 'unknown'
}
