<script setup lang="ts">
import { computed, ref } from 'vue'
import { t } from '../i18n'

const props = defineProps<{ roomId: string }>()
const emit = defineEmits<{ say: [msg: string] }>()
const input = ref<HTMLInputElement | null>(null)

/** The console's own address with ?r=, which is what the client expects. */
const address = computed(() => {
  const u = new URL(window.location.href)
  u.search = ''
  u.hash = ''
  u.searchParams.set('r', props.roomId)
  return u.toString()
})

async function copy() {
  try {
    await navigator.clipboard.writeText(address.value)
    emit('say', t.value.copied)
  } catch {
    // No clipboard outside a secure context.
    input.value?.select()
    emit('say', t.value.copyManually)
  }
}
</script>

<template>
  <section class="address">
    <h2>{{ t.clientAddress }}</h2>
    <div class="row">
      <input ref="input" class="num" :value="address" readonly :aria-label="t.clientAddress" @focus="input?.select()" />
      <button @click="copy">{{ t.copy }}</button>
    </div>
    <p class="hint">{{ t.clientAddressHint }}</p>
  </section>
</template>

<style scoped>
.address {
  margin-bottom: 32px;
}
h2 {
  font-size: 15px;
  font-weight: 600;
  margin: 0 0 8px;
}
.row {
  display: flex;
  gap: 6px;
}
input {
  flex: 1;
  font-size: 13px;
  color: var(--fg-muted);
}
</style>
