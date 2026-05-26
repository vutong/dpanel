<template>
  <div>
    <h1>List databases</h1>
    <p class="muted intro">Create or delete databases from the MariaDB menu in the sidebar.</p>
    <div v-if="pending" class="muted">Loading...</div>
    <div v-else-if="!databases.length" class="card muted">No user databases yet.</div>
    <div v-else class="card">
      <table class="table">
        <thead>
          <tr>
            <th>Name</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="db in databases" :key="db">
            <td><code>{{ db }}</code></td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>

<script setup lang="ts">
const { data, pending } = await useFetch<{ databases: string[] }>('/api/databases')
const databases = computed(() => data.value?.databases ?? [])
</script>

<style scoped>
.intro { margin-bottom: 1rem; }
code { font-size: 0.9rem; }
</style>
