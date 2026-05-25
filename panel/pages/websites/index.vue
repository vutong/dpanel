<template>
  <div>
    <div class="header">
      <h1>Danh sách website</h1>
      <NuxtLink to="/websites/create" class="btn btn-primary">+ Tạo website</NuxtLink>
    </div>
    <div v-if="pending" class="muted">Đang tải...</div>
    <div v-else-if="!sites.length" class="card muted">Chưa có website. Tạo site đầu tiên.</div>
    <div v-else class="card">
      <table class="table">
        <thead>
          <tr>
            <th>Domain</th>
            <th>Runtime</th>
            <th>GitHub</th>
            <th>Tạo lúc</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="s in sites" :key="s.domain">
            <td><strong>{{ s.domain }}</strong></td>
            <td>
              <span :class="s.runtime === 'node' ? 'badge badge-node' : 'badge badge-php'">
                {{ s.runtime }}
              </span>
            </td>
            <td>{{ s.githubUrl || '—' }}</td>
            <td>{{ formatDate(s.createdAt) }}</td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>

<script setup lang="ts">
type Site = { domain: string; runtime: string; githubUrl?: string; createdAt?: string }
const { data, pending } = await useFetch<{ sites: Site[] }>('/api/websites')
const sites = computed(() => data.value?.sites ?? [])

function formatDate(iso?: string) {
  if (!iso) return '—'
  return new Date(iso).toLocaleString('vi-VN')
}
</script>

<style scoped>
.header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 1.25rem; }
.muted { color: var(--muted); }
</style>
