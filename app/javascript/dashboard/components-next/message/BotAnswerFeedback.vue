<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';

import { useAlert } from 'dashboard/composables';
import { useMapGetter, useStore } from 'dashboard/composables/store';

import Button from 'dashboard/components-next/button/Button.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';

import { useMessageContext } from './provider.js';
import {
  MESSAGE_TYPES,
} from './constants.js';

const { t } = useI18n();
const store = useStore();
const currentChat = useMapGetter('getSelectedChat');
const captainAssistants = useMapGetter('captainAssistants/getRecords');

const {
  id,
  content,
  contentAttributes,
  sender,
  messageType,
  conversationId,
} = useMessageContext();

const dialogRef = ref(null);
const note = ref('');
const isSubmitting = ref(false);
const isAssistantsLoading = ref(false);
const selectedAssistantId = ref('');

const isBotGeneratedMessage = computed(() => {
  if (Number(messageType.value) !== MESSAGE_TYPES.OUTGOING) return false;

  const attrs = contentAttributes.value || {};
  const rawFlag = attrs.isBotGenerated ?? attrs.is_bot_generated;
  if (typeof rawFlag === 'boolean') return rawFlag;

  return String(rawFlag || '').toLowerCase() === 'true';
});

const selectedConversationMessages = computed(() => {
  const messages = currentChat.value?.messages;
  return Array.isArray(messages) ? messages : [];
});

const orderedConversationMessages = computed(() => {
  const messages = [...selectedConversationMessages.value];
  return messages.sort((left, right) => {
    const leftCreatedAt = Number(left?.created_at ?? left?.createdAt ?? 0);
    const rightCreatedAt = Number(right?.created_at ?? right?.createdAt ?? 0);

    if (leftCreatedAt !== rightCreatedAt) {
      return leftCreatedAt - rightCreatedAt;
    }

    return Number(left?.id || 0) - Number(right?.id || 0);
  });
});

const assistantOptions = computed(() => {
  const assistants = Array.isArray(captainAssistants.value)
    ? captainAssistants.value
    : [];
  return assistants.map(assistant => ({
    label: assistant.name,
    value: String(assistant.id),
  }));
});

const isAssistantMissing = computed(() => !selectedAssistantId.value);

const assistantMessage = computed(() => {
  if (isAssistantsLoading.value) {
    return t('CONVERSATION.BOT_FEEDBACK.DIALOG.ASSISTANT_LOADING');
  }

  if (!assistantOptions.value.length) {
    return t('CONVERSATION.BOT_FEEDBACK.DIALOG.ASSISTANT_EMPTY');
  }

  if (isAssistantMissing.value) {
    return t('CONVERSATION.BOT_FEEDBACK.DIALOG.ASSISTANT_REQUIRED');
  }

  return '';
});

const isSubmitDisabled = computed(() => {
  return (
    isSubmitting.value ||
    isAssistantMissing.value ||
    !String(note.value || '').trim()
  );
});

const findConversationQuestion = messageId => {
  const messages = orderedConversationMessages.value;
  if (!messages.length) return '';

  const currentIndex = messages.findIndex(message => {
    return Number(message?.id) === Number(messageId);
  });

  if (currentIndex <= 0) return '';

  for (let index = currentIndex - 1; index >= 0; index -= 1) {
    const candidate = messages[index];
    const candidateContent = String(candidate?.content || '').trim();
    if (!candidateContent) continue;

    const candidateMessageType = Number(
      candidate?.message_type ?? candidate?.messageType
    );
    if (candidateMessageType === MESSAGE_TYPES.INCOMING) {
      return candidateContent;
    }
  }

  return '';
};

const buildScanMetadata = () => {
  const metadata = {
    conversation_id: conversationId.value,
    message_id: id.value,
  };

  return `[[scan_meta]]${JSON.stringify(metadata)}[[/scan_meta]]`;
};

const buildPendingAnswer = customerQuestion => {
  const botAnswer = String(content.value || '').trim();
  const noteText = String(note.value || '').trim();
  const questionText = String(customerQuestion || '').trim();
  const lines = [];

  if (questionText) {
    lines.push(
      t('CONVERSATION.BOT_FEEDBACK.PENDING_ANSWER.CUSTOMER_QUESTION_TITLE')
    );
    lines.push(questionText);
  }

  if (botAnswer) {
    if (lines.length) lines.push('');
    lines.push(t('CONVERSATION.BOT_FEEDBACK.PENDING_ANSWER.BOT_ANSWER_TITLE'));
    lines.push(botAnswer);
  }

  if (noteText) {
    if (lines.length) lines.push('');
    lines.push(t('CONVERSATION.BOT_FEEDBACK.PENDING_ANSWER.NOTE_TITLE'));
    lines.push(noteText);
  }

  return `${buildScanMetadata()}\n${lines.join('\n')}`;
};

const syncSelectedAssistant = () => {
  if (!assistantOptions.value.length) {
    selectedAssistantId.value = '';
    return;
  }

  const senderAssistantId = String(sender.value?.id || '');
  const hasSenderAssistant = assistantOptions.value.some(
    option => option.value === senderAssistantId
  );
  if (hasSenderAssistant) {
    selectedAssistantId.value = senderAssistantId;
    return;
  }

  const hasCurrentSelection = assistantOptions.value.some(
    option => option.value === selectedAssistantId.value
  );
  if (hasCurrentSelection) return;

  selectedAssistantId.value = assistantOptions.value[0].value;
};

const loadAssistants = async () => {
  if (assistantOptions.value.length) {
    syncSelectedAssistant();
    return;
  }

  isAssistantsLoading.value = true;
  try {
    await store.dispatch('captainAssistants/get', { page: 1 });
    syncSelectedAssistant();
  } catch (error) {
    useAlert(t('CONVERSATION.BOT_FEEDBACK.ALERTS.ASSISTANT_FETCH_ERROR'));
  } finally {
    isAssistantsLoading.value = false;
  }
};

const openDialog = async () => {
  await loadAssistants();
  dialogRef.value?.open();
};

const handleDialogClose = () => {
  note.value = '';
};

const handleSubmit = async () => {
  if (isSubmitDisabled.value) return;

  const assistantId = Number(selectedAssistantId.value || 0);

  const fallbackQuestion = String(content.value || '').trim();
  const question =
    findConversationQuestion(id.value) ||
    fallbackQuestion ||
    t('CONVERSATION.BOT_FEEDBACK.FALLBACK_QUESTION');

  isSubmitting.value = true;
  try {
    const payload = {
      conversation_id: conversationId.value,
      question,
      answer: buildPendingAnswer(question),
      status: 'pending',
    };
    if (assistantId) payload.assistant_id = assistantId;

    await store.dispatch('captainResponses/create', payload);
    useAlert(t('CONVERSATION.BOT_FEEDBACK.ALERTS.SUCCESS'));
    dialogRef.value?.close();
  } catch (error) {
    const errorMessage =
      error?.response?.data?.error ||
      error?.message ||
      t('CONVERSATION.BOT_FEEDBACK.ALERTS.ERROR');
    useAlert(errorMessage);
  } finally {
    isSubmitting.value = false;
  }
};

</script>

<template>
  <template v-if="isBotGeneratedMessage">
    <Button
      link
      slate
      size="xs"
      icon="i-lucide-triangle-alert"
      :label="$t('CONVERSATION.BOT_FEEDBACK.ACTION')"
      class="text-[11px] !no-underline hover:!underline"
      @click="openDialog"
    />
    <Dialog
      ref="dialogRef"
      width="md"
      :title="$t('CONVERSATION.BOT_FEEDBACK.DIALOG.TITLE')"
      :description="$t('CONVERSATION.BOT_FEEDBACK.DIALOG.DESCRIPTION')"
      :confirm-button-label="$t('CONVERSATION.BOT_FEEDBACK.DIALOG.CONFIRM')"
      :disable-confirm-button="isSubmitDisabled"
      :is-loading="isSubmitting"
      @confirm="handleSubmit"
      @close="handleDialogClose"
    >
      <ComboBox
        v-model="selectedAssistantId"
        :options="assistantOptions"
        :placeholder="$t('CONVERSATION.BOT_FEEDBACK.DIALOG.ASSISTANT_PLACEHOLDER')"
        :search-placeholder="$t('CONVERSATION.BOT_FEEDBACK.DIALOG.ASSISTANT_SEARCH_PLACEHOLDER')"
        :empty-state="$t('CONVERSATION.BOT_FEEDBACK.DIALOG.ASSISTANT_EMPTY')"
        :message="assistantMessage"
        :disabled="isAssistantsLoading || !assistantOptions.length"
        :has-error="isAssistantMissing && !isAssistantsLoading"
      />
      <TextArea
        v-model="note"
        auto-height
        show-character-count
        :max-length="500"
        :label="$t('CONVERSATION.BOT_FEEDBACK.DIALOG.NOTE_LABEL')"
        :placeholder="$t('CONVERSATION.BOT_FEEDBACK.DIALOG.NOTE_PLACEHOLDER')"
      />
    </Dialog>
  </template>
</template>
