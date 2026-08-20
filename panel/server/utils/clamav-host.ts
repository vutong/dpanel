import { parseScriptJson, runScript } from './stack'

export type ClamavQueryMode = 'summary' | 'detail'

export type ClamavQueryResult = {
  ok: boolean
  mode?: string
  installed: boolean
  daemonActive: boolean
  freshclamActive: boolean
  signatureDate: string | null
  version: string | null
  clamscanPath?: string | null
  clamdscanPath?: string | null
  logPaths?: string[]
  error?: string
}

export async function queryClamav(mode: ClamavQueryMode = 'summary'): Promise<ClamavQueryResult> {
  const raw = await runScript('host-clamav-query.sh', [mode], 90_000)
  const parsed = parseScriptJson<ClamavQueryResult>(raw)
  if (parsed.ok === false && parsed.error) {
    throw new Error(String(parsed.error))
  }
  return {
    ...parsed,
    signatureDate: parsed.signatureDate ?? null,
    version: parsed.version ?? null,
    logPaths: parsed.logPaths ?? []
  }
}
