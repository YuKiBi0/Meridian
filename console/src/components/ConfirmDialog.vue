<script setup lang="ts">
import { t } from '../i18n'

defineProps<{ message: string; danger?: boolean; confirmText?: string }>()
const emit = defineEmits<{ confirm: []; cancel: [] }>()
</script>

<template>
  <div class="overlay" @click.self="emit('cancel')" @keydown.esc="emit('cancel')">
    <div class="dialog small" role="alertdialog" aria-modal="true">
      <p>{{ message }}</p>
      <div class="actions">
        <button @click="emit('cancel')">{{ t.cancel }}</button>
        <button :class="danger ? 'danger' : 'primary'" autofocus @click="emit('confirm')">
          {{ confirmText ?? t.confirm }}
        </button>
      </div>
    </div>
  </div>
</template>

<style scoped>
.small {
  max-width: 380px;
}
p {
  margin: 0;
}
</style>
