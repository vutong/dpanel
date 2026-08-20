<template>
  <div class="banned-wrap">
    <div class="toolbar">
      <input
        v-model="search"
        type="search"
        class="input search"
        placeholder="Filter by IP or jail…"
      />
      <span class="count muted">{{ filtered.length }} IP(s)</span>
    </div>

    <div v-if="!rows.length" class="card muted empty">No banned IPs.</div>

    <div v-else-if="!filtered.length" class="card muted empty">No matches for &quot;{{ search }}&quot;.</div>

    <div v-else class="card table-wrap">
      <table class="table">
        <thead>
          <tr>
            <th>IP</th>
            <th>Jail(s)</th>
            <th>Banned at</th>
            <th class="col-actions">Action</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="row in filtered" :key="row.ip">
            <td><code>{{ row.ip }}</code></td>
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

const props = defineProps<{
  jails: JailRow[]
  bannedIps?: string[]
}>()

const emit = defineEmits<{ unban: [string] }>()

const search = ref('')

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

const filtered = computed(() => {
  const q = search.value.trim().toLowerCase()
  if (!q) return rows.value
  return rows.value.filter(
    (r) =>
      r.ip.toLowerCase().includes(q) ||
      r.jails.some((j) => j.toLowerCase().includes(q))
  )
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
</style>
