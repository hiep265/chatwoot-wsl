<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';

import AiControlAPI from 'dashboard/api/aiControl';

const props = defineProps({
  modelValue: {
    type: String,
    default: '',
  },
});

const emit = defineEmits(['update:modelValue']);

const { t } = useI18n();
const agents = ref([]);
const isLoading = ref(false);
const errorMessage = ref('');

const selectedAgent = computed({
  get: () => props.modelValue || '',
  set: value => emit('update:modelValue', value),
});

const compatibleAgents = computed(() =>
  agents.value.filter(agent => agent.chatwoot_message_compatible)
);

const helperText = computed(() => {
  if (!compatibleAgents.value.length && !isLoading.value) {
    return t('INBOX_MGMT.SETTINGS_POPUP.KIMI_AGENT_SELECTOR.EMPTY_TEXT');
  }

  return t('INBOX_MGMT.SETTINGS_POPUP.KIMI_AGENT_SELECTOR.HELP_TEXT');
});

const fetchAgents = async () => {
  try {
    isLoading.value = true;
    errorMessage.value = '';
    const response = await AiControlAPI.getChatwootAgents();
    const responseAgents = response?.data?.agents;
    agents.value = Array.isArray(responseAgents) ? responseAgents : [];
  } catch (error) {
    errorMessage.value = t(
      'INBOX_MGMT.SETTINGS_POPUP.KIMI_AGENT_SELECTOR.ERROR_TEXT'
    );
  } finally {
    isLoading.value = false;
  }
};

onMounted(fetchAgents);
</script>

<template>
  <label class="pb-4">
    {{ t('INBOX_MGMT.SETTINGS_POPUP.KIMI_AGENT_SELECTOR.LABEL') }}
    <select v-model="selectedAgent" :disabled="isLoading">
      <option value="">
        {{
          isLoading
            ? t('INBOX_MGMT.SETTINGS_POPUP.KIMI_AGENT_SELECTOR.LOADING_TEXT')
            : t('INBOX_MGMT.SETTINGS_POPUP.KIMI_AGENT_SELECTOR.DEFAULT_OPTION')
        }}
      </option>
      <option
        v-for="agent in compatibleAgents"
        :key="agent.id"
        :value="agent.id"
      >
        {{ agent.name || agent.id }}
      </option>
    </select>
    <p v-if="errorMessage" class="pb-1 text-sm not-italic text-n-ruby-11">
      {{ errorMessage }}
    </p>
    <p v-else class="pb-1 text-sm not-italic text-n-slate-11">
      {{ helperText }}
    </p>
  </label>
</template>
