#!/usr/bin/env node
'use strict'
// Print `export KEY='value'` lines for a dotenv file.
// Values are never executed as shell (no $(...), backticks, or bare words).
const fs = require('fs')

const file = process.argv[2]
if (!file || !fs.existsSync(file)) process.exit(0)

const text = fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, '')

function shQuote(s) {
  return "'" + String(s).replace(/'/g, "'\\''") + "'"
}

function unescapeDouble(s) {
  return s
    .replace(/\\n/g, '\n')
    .replace(/\\r/g, '\r')
    .replace(/\\t/g, '\t')
    .replace(/\\"/g, '"')
    .replace(/\\\\/g, '\\')
}

const env = Object.create(null)
for (const key of Object.keys(process.env)) env[key] = process.env[key]

function expand(val) {
  return val
    .replace(/\\\$/g, '\u0000')
    .replace(/\$\{([A-Za-z_][A-Za-z0-9_]*)\}|\$([A-Za-z_][A-Za-z0-9_]*)/g, (_, braced, plain) => {
      const name = braced || plain
      if (Object.prototype.hasOwnProperty.call(env, name) && env[name] != null) return String(env[name])
      return ''
    })
    .replace(/\u0000/g, '$')
}

function commit(key, raw, quote) {
  if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(key)) return
  let val = raw
  if (quote === '"') val = unescapeDouble(val)
  if (quote !== "'") {
    if (!quote) {
      const idx = val.search(/[ \t]#/)
      if (idx !== -1) val = val.slice(0, idx).replace(/[ \t]+$/, '')
    }
    val = expand(val)
  }
  env[key] = val
  process.stdout.write('export ' + key + '=' + shQuote(val) + '\n')
}

// Returns { quote, body, open } when the value starts with a quote.
function parseQuoted(raw) {
  const quote = raw[0]
  if (quote !== '"' && quote !== "'") return null
  let closed = -1
  for (let i = 1; i < raw.length; i++) {
    if (quote === '"' && raw[i] === '\\') {
      i++
      continue
    }
    if (raw[i] === quote) {
      closed = i
      break
    }
  }
  if (closed === -1) return { quote, body: raw.slice(1), open: true }
  const after = raw.slice(closed + 1).trim()
  if (after && !after.startsWith('#')) return null
  return { quote, body: raw.slice(1, closed), open: false }
}

const lines = text.split('\n')
let pending = null

for (const rawLine of lines) {
  const line = rawLine.replace(/\r$/, '')
  if (pending) {
    let closed = -1
    for (let i = 0; i < line.length; i++) {
      if (pending.quote === '"' && line[i] === '\\') {
        i++
        continue
      }
      if (line[i] === pending.quote) {
        closed = i
        break
      }
    }
    if (closed === -1) {
      pending.parts.push(line)
      continue
    }
    const after = line.slice(closed + 1).trim()
    if (after && !after.startsWith('#')) {
      pending.parts.push(line)
      continue
    }
    pending.parts.push(line.slice(0, closed))
    commit(pending.key, pending.parts.join('\n'), pending.quote)
    pending = null
    continue
  }

  if (!line.trim() || /^\s*#/.test(line)) continue
  const body = line.replace(/^\s*export\s+/, '')
  const eq = body.indexOf('=')
  if (eq <= 0) continue
  const key = body.slice(0, eq).trim()
  const raw = body.slice(eq + 1)
  const quoted = parseQuoted(raw)
  if (quoted && quoted.open) {
    pending = { key, quote: quoted.quote, parts: [quoted.body] }
    continue
  }
  if (quoted) {
    commit(key, quoted.body, quoted.quote)
    continue
  }
  commit(key, raw, null)
}

if (pending) commit(pending.key, pending.parts.join('\n'), pending.quote)
