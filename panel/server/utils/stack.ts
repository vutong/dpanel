import { execFile } from 'node:child_process'
import { promisify } from 'node:util'
import { readFile } from 'node:fs/promises'
import { join } from 'node:path'

const execFileAsync = promisify(execFile)

export function stackRoot(): string {
  return process.env.STACK_ROOT || '/opt/stack'
}

export function scriptPath(name: string): string {
  return join(stackRoot(), 'infra', 'scripts', name)
}

export async function runScript(
  script: string,
  args: string[] = [],
  timeoutMs = 120_000,
  extraEnv: Record<string, string> = {}
): Promise<string> {
  const { stdout, stderr } = await execFileAsync(
    'bash',
    [scriptPath(script), ...args],
    {
      env: { ...process.env, STACK_ROOT: stackRoot(), ...extraEnv },
      timeout: timeoutMs,
      maxBuffer: 4 * 1024 * 1024
    }
  )
  if (stderr && !stdout) {
    throw new Error(stderr.trim())
  }
  return (stdout || stderr).trim()
}

/** Parse last JSON object line from bash script stdout (ignores log lines). */
export function parseScriptJson<T extends Record<string, unknown>>(stdout: string): T {
  const lines = stdout.trim().split('\n').map((l) => l.trim()).filter((l) => l.startsWith('{'))
  const last = lines[lines.length - 1]
  if (!last) {
    throw new Error('Script did not return JSON')
  }
  return JSON.parse(last) as T
}

export async function readAuth() {
  const raw = await readFile(join(stackRoot(), 'data', 'panel', 'auth.json'), 'utf8')
  return JSON.parse(raw) as { email: string; passwordHash: string }
}
