<script setup>
import { reactive, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useVuelidate } from '@vuelidate/core';
import { minLength } from '@vuelidate/validators';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { useAccount } from 'dashboard/composables/useAccount';
import CaptainAssistant from 'dashboard/api/captain/assistant';

import Button from 'dashboard/components-next/button/Button.vue';
import Editor from 'dashboard/components-next/Editor/Editor.vue';

const props = defineProps({
  assistant: {
    type: Object,
    default: () => ({}),
  },
});

const emit = defineEmits(['submit']);

const { t } = useI18n();
const { isCloudFeatureEnabled } = useAccount();

const isCaptainV2Enabled = computed(() =>
  isCloudFeatureEnabled(FEATURE_FLAGS.CAPTAIN_V2)
);

const initialState = {
  handoffMessage: '',
  resolutionMessage: '',
  instructions: '',
  temperature: 1,
  systemPrompt: '',
  enableSystemPromptOverride: false,
};

const state = reactive({ ...initialState });

const validationRules = {
  handoffMessage: { minLength: minLength(1) },
  resolutionMessage: { minLength: minLength(1) },
  instructions: { minLength: minLength(1) },
  systemPrompt: { minLength: minLength(1) },
};

const v$ = useVuelidate(validationRules, state);

const getErrorMessage = field => {
  return v$.value[field].$error ? v$.value[field].$errors[0].$message : '';
};

const formErrors = computed(() => ({
  handoffMessage: getErrorMessage('handoffMessage'),
  resolutionMessage: getErrorMessage('resolutionMessage'),
  instructions: getErrorMessage('instructions'),
  systemPrompt: getErrorMessage('systemPrompt'),
}));

const updateStateFromAssistant = assistant => {
  const { config = {} } = assistant;
  state.handoffMessage = config.handoff_message;
  state.resolutionMessage = config.resolution_message;
  state.instructions = config.instructions;
  state.temperature = config.temperature || 1;
  state.systemPrompt = config.system_prompt || '';
  state.enableSystemPromptOverride = !!config.system_prompt;
};

const loadDefaultTemplate = async () => {
  try {
    const { data } = await CaptainAssistant.getSystemPromptTemplate(
      props.assistant.id
    );
    state.systemPrompt = data.template;
  } catch (error) {
    // Ignore error
  }
};

const handleSystemMessagesUpdate = async () => {
  const validations = [
    v$.value.handoffMessage.$validate(),
    v$.value.resolutionMessage.$validate(),
    v$.value.instructions.$validate(),
  ];

  const result = await Promise.all(validations).then(results =>
    results.every(Boolean)
  );
  if (!result) return;

  const payload = {
    config: {
      ...props.assistant.config,
      handoff_message: state.handoffMessage,
      resolution_message: state.resolutionMessage,
      temperature: state.temperature || 1,
      instructions: state.instructions,
      system_prompt: state.enableSystemPromptOverride ? state.systemPrompt : '',
    },
  };

  emit('submit', payload);
};

watch(
  () => props.assistant,
  newAssistant => {
    if (newAssistant) updateStateFromAssistant(newAssistant);
  },
  { immediate: true }
);
</script>

<template>
  <div class="flex flex-col gap-6">
    <Editor
      v-model="state.handoffMessage"
      :label="t('CAPTAIN.ASSISTANTS.FORM.HANDOFF_MESSAGE.LABEL')"
      :placeholder="t('CAPTAIN.ASSISTANTS.FORM.HANDOFF_MESSAGE.PLACEHOLDER')"
      :message="formErrors.handoffMessage"
      :message-type="formErrors.handoffMessage ? 'error' : 'info'"
      class="z-0"
    />

    <Editor
      v-model="state.resolutionMessage"
      :label="t('CAPTAIN.ASSISTANTS.FORM.RESOLUTION_MESSAGE.LABEL')"
      :placeholder="t('CAPTAIN.ASSISTANTS.FORM.RESOLUTION_MESSAGE.PLACEHOLDER')"
      :message="formErrors.resolutionMessage"
      :message-type="formErrors.resolutionMessage ? 'error' : 'info'"
      class="z-0"
    />

    <Editor
      v-model="state.instructions"
      :label="t('CAPTAIN.ASSISTANTS.FORM.INSTRUCTIONS.LABEL')"
      :placeholder="t('CAPTAIN.ASSISTANTS.FORM.INSTRUCTIONS.PLACEHOLDER')"
      :message="formErrors.instructions"
      :max-length="20000"
      :message-type="formErrors.instructions ? 'error' : 'info'"
      class="z-0"
    />

    <div class="flex flex-col gap-2">
      <label class="flex items-center gap-2">
        <input v-model="state.enableSystemPromptOverride" type="checkbox" />
        <span class="text-sm font-medium text-n-slate-12">
          {{ t('CAPTAIN.ASSISTANTS.FORM.SYSTEM_PROMPT.ENABLE_OVERRIDE') }}
        </span>
      </label>
      <p class="text-sm text-n-slate-11">
        {{ t('CAPTAIN.ASSISTANTS.FORM.SYSTEM_PROMPT.OVERRIDE_DESCRIPTION') }}
      </p>
    </div>

    <div v-if="state.enableSystemPromptOverride" class="flex flex-col gap-4">
      <div class="flex justify-end">
        <Button
          :label="t('CAPTAIN.ASSISTANTS.FORM.SYSTEM_PROMPT.LOAD_DEFAULT')"
          size="sm"
          variant="outline"
          @click="loadDefaultTemplate"
        />
      </div>
      <Editor
        v-model="state.systemPrompt"
        :label="t('CAPTAIN.ASSISTANTS.FORM.SYSTEM_PROMPT.LABEL')"
        :placeholder="t('CAPTAIN.ASSISTANTS.FORM.SYSTEM_PROMPT.PLACEHOLDER')"
        :message="formErrors.systemPrompt"
        :max-length="50000"
        :message-type="formErrors.systemPrompt ? 'error' : 'info'"
        class="z-0"
      />
    </div>

    <div class="flex flex-col gap-2">
      <label class="text-sm font-medium text-n-slate-12">
        {{ t('CAPTAIN.ASSISTANTS.FORM.TEMPERATURE.LABEL') }}
      </label>
      <div class="flex items-center gap-4">
        <input
          v-model="state.temperature"
          type="range"
          min="0"
          max="1"
          step="0.1"
          class="w-full"
        />
        <span class="text-sm text-n-slate-12">{{ state.temperature }}</span>
      </div>
      <p class="text-sm text-n-slate-11 italic">
        {{ t('CAPTAIN.ASSISTANTS.FORM.TEMPERATURE.DESCRIPTION') }}
      </p>
    </div>

    <div>
      <Button
        :label="t('CAPTAIN.ASSISTANTS.FORM.UPDATE')"
        @click="handleSystemMessagesUpdate"
      />
    </div>
  </div>
</template>
