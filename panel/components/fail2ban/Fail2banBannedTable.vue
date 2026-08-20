<template>
  <div class="banned-wrap">
    <div class="toolbar">
      <input
        v-model="search"
        type="search"
        class="input search"
        placeholder="Filter by IP, country, or jail…"
      />
      <span class="count muted">{{ filtered.length }} IP(s)</span>
    </div>

    <p v-if="!geoip?.ready" class="geo-banner muted">
      Country lookup uses an offline MaxMind database. Click <strong>Sync</strong> in the Country column
      header to download it (requires <code>GEOIP_MAXMIND_LICENSE_KEY</code> in <code>.env</code>).
    </p>

    <div v-if="!rows.length" class="card muted empty">No banned IPs.</div>

    <div v-else-if="!filtered.length" class="card muted empty">No matches for &quot;{{ search }}&quot;.</div>

    <div v-else class="card table-wrap">
      <table class="table">
        <thead>
          <tr>
            <th>IP</th>
            <th class="col-country">
              <span class="th-country">
                Country
                <button
                  type="button"
                  class="btn btn-ghost btn-sm sync-btn"
                  :disabled="syncBusy"
                  :title="syncTitle"
                  @click="emit('sync-geoip')"
                >
                  {{ syncBusy ? 'Syncing…' : 'Sync' }}
                </button>
              </span>
              <span v-if="geoip?.syncedAt" class="geo-meta muted">{{ formatSynced(geoip.syncedAt) }}</span>
            </th>
            <th>Jail(s)</th>
            <th>Banned at</th>
            <th class="col-actions">Action</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="row in filtered" :key="row.ip">
            <td><code>{{ row.ip }}</code></td>
            <td class="col-country">
              <span v-if="geoLabel(row.ip)" class="country-cell">
                <span v-if="geoFor(row.ip)?.flag" class="flag" aria-hidden="true">{{ geoFor(row.ip)?.flag }}</span>
                <span>{{ geoLabel(row.ip) }}</span>
              </span>
              <span v-else class="muted">—</span>
            </td>
            <td>
              <span v-for="j in row.jails" :key="j" class="jail-tag">{{ j }}</span>
            </td>
            <td class="muted">{{ row.bannedAt || '—' }}</td>
            <td class="col-actions">
              <button type="button" class="btn btn-ghost btn-sm" @click="emit('unban', row.ip)">
                Unban
              </button>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>

<script setup lang="ts">
type JailRow = {
  name: string
  bannedIps?: { ip: string; bannedAt: string | null }[]
}

type IpGeoEntry = {
  countryCode: string | null
  countryName: string | null
  flag: string
}

type GeoipStatus = {
  ready: boolean
  syncedAt: string | null
  buildDate?: string | null
  edition?: string | null
}

const props = defineProps<{
  jails: JailRow[]
  bannedIps?: string[]
  ipGeo?: Record<string, IpGeoEntry>
  geoip?: GeoipStatus | null
  syncBusy?: boolean
}>()

const emit = defineEmits<{ unban: [string]; 'sync-geoip': [] }>()

const search = ref('')

const syncTitle = computed(() => {
  if (props.syncBusy) return 'Downloading GeoLite2 database…'
  if (props.geoip?.ready) return 'Update offline country database from MaxMind'
  return 'Download offline country database from MaxMind'
})

const rows = computed(() => {
  const map = new Map<string, { ip: string; jails: string[]; bannedAt: string | null }>()
  for (const jail of props.jails || []) {
    for (const entry of jail.bannedIps || []) {
      const prev = map.get(entry.ip)
      if (prev) {
        if (!prev.jails.includes(jail.name)) prev.jails.push(jail.name)
        if (!prev.bannedAt && entry.bannedAt) prev.bannedAt = entry.bannedAt
      } else {
        map.set(entry.ip, {
          ip: entry.ip,
          jails: [jail.name],
          bannedAt: entry.bannedAt
        })
      }
    }
  }
  for (const ip of props.bannedIps || []) {
    if (!map.has(ip)) {
      map.set(ip, { ip, jails: [], bannedAt: null })
    }
  }
  return [...map.values()].sort((a, b) => a.ip.localeCompare(b.ip))
})

function geoFor(ip: string): IpGeoEntry | undefined {
  return props.ipGeo?.[ip]
}

function geoLabel(ip: string): string | null {
  const geo = geoFor(ip)
  if (!geo) return null
  if (geo.countryName) return geo.countryName
  if (geo.countryCode) return geo.countryCode
  return null
}

function formatSynced(iso: string) {
  try {
    return `DB ${new Date(iso).toLocaleDateString()}`
  } catch {
    return 'DB synced'
  }
}

const filtered = computed(() => {
  const q = search.value.trim().toLowerCase()
  if (!q) return rows.value
  return rows.value.filter((r) => {
    const geo = geoLabel(r.ip)?.toLowerCase() || ''
    const code = geoFor(r.ip)?.countryCode?.toLowerCase() || ''
    return (
      r.ip.toLowerCase().includes(q) ||
      geo.includes(q) ||
      code.includes(q) ||
      r.jails.some((j) => j.toLowerCase().includes(q))
    )
  })
})
</script>

<style scoped>
.toolbar {
  display: flex;
  flex-wrap: wrap;
  gap: 0.75rem;
  align-items: center;
  margin-bottom: 0.75rem;
}

.search {
  min-width: 220px;
  max-width: 320px;
}

.count {
  font-size: 0.8125rem;
}

.geo-banner {
  margin: 0 0 0.75rem;
  font-size: 0.8125rem;
  line-height: 1.45;
}

.empty {
  padding: 1rem;
  font-size: 0.875rem;
}

.jail-tag {
  display: inline-block;
  font-size: 0.75rem;
  padding: 0.1rem 0.4rem;
  margin: 0.1rem 0.25rem 0.1rem 0;
  border-radius: 4px;
  background: var(--surface-2);
  font-family: var(--font-mono, monospace);
}

.col-actions {
  white-space: nowrap;
}

.col-country {
  min-width: 9rem;
}

.th-country {
  display: inline-flex;
  align-items: center;
  gap: 0.35rem;
}

.sync-btn {
  padding: 0.1rem 0.45rem;
  font-size: 0.6875rem;
  line-height: 1.2;
}

.geo-meta {
  display: block;
  font-size: 0.6875rem;
  font-weight: 400;
  margin-top: 0.125rem;
}

.country-cell {
  display: inline-flex;
  align-items: center;
  gap: 0.35rem;
}

.flag {
  font-size: 1rem;
  line-height: 1;
}
</style>
