<script setup>
import { computed, useTemplateRef } from 'vue';
import { useElementSize } from '@vueuse/core';
import { REPLY_EDITOR_MODES } from './constants';

const props = defineProps({
  mode: {
    type: String,
    default: REPLY_EDITOR_MODES.REPLY,
  },
  disabled: {
    type: Boolean,
    default: false,
  },
  isReplyRestricted: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['setMode']);

const wootEditorReplyMode = useTemplateRef('wootEditorReplyMode');
const wootEditorPrivateMode = useTemplateRef('wootEditorPrivateMode');

const replyModeSize = useElementSize(wootEditorReplyMode);
const privateModeSize = useElementSize(wootEditorPrivateMode);

const modeOrder = [REPLY_EDITOR_MODES.REPLY, REPLY_EDITOR_MODES.NOTE];

const selectedMode = computed(() => {
  if (props.isReplyRestricted && props.mode === REPLY_EDITOR_MODES.REPLY) {
    return REPLY_EDITOR_MODES.NOTE;
  }

  return modeOrder.includes(props.mode) ? props.mode : '';
});

const isDisabled = computed(() => props.disabled);

const isModeDisabled = mode => {
  if (props.disabled) return true;
  return props.isReplyRestricted && mode === REPLY_EDITOR_MODES.REPLY;
};

const getModeWidth = mode => {
  if (mode === REPLY_EDITOR_MODES.NOTE) {
    return privateModeSize.width.value;
  }

  return replyModeSize.width.value;
};

const width = computed(() => {
  const widthToUse = getModeWidth(selectedMode.value);

  const widthWithPadding = widthToUse + 16;
  return selectedMode.value ? `${widthWithPadding}px` : '0px';
});

const translateValue = computed(() => {
  const selectedIndex = modeOrder.indexOf(selectedMode.value);
  if (selectedIndex < 0) return '0px';

  const xTranslate = modeOrder
    .slice(0, selectedIndex)
    .reduce((sum, mode) => sum + getModeWidth(mode) + 16, 0);

  return `${xTranslate}px`;
});

const selectMode = mode => {
  if (isModeDisabled(mode)) return;
  emit('setMode', mode);
};
</script>

<template>
  <div
    role="group"
    class="flex items-center w-auto h-8 p-1 transition-all border rounded-full bg-n-alpha-2 group relative duration-300 ease-in-out z-0 active:scale-[0.995] active:duration-75"
    :aria-disabled="isDisabled"
    :class="{
      'cursor-not-allowed': isDisabled,
    }"
  >
    <button
      ref="wootEditorReplyMode"
      type="button"
      class="relative z-20 flex items-center gap-1 px-2 h-6"
      :disabled="isModeDisabled(REPLY_EDITOR_MODES.REPLY)"
      :aria-pressed="selectedMode === REPLY_EDITOR_MODES.REPLY"
      @click="selectMode(REPLY_EDITOR_MODES.REPLY)"
    >
      {{ $t('CONVERSATION.REPLYBOX.REPLY') }}
    </button>
    <button
      ref="wootEditorPrivateMode"
      type="button"
      class="relative z-20 flex items-center gap-1 px-2 h-6"
      :disabled="isModeDisabled(REPLY_EDITOR_MODES.NOTE)"
      :aria-pressed="selectedMode === REPLY_EDITOR_MODES.NOTE"
      @click="selectMode(REPLY_EDITOR_MODES.NOTE)"
    >
      {{ $t('CONVERSATION.REPLYBOX.PRIVATE_NOTE') }}
    </button>
    <div
      class="absolute top-1 ltr:left-1 rtl:right-1 pointer-events-none shadow-sm rounded-full h-6 w-[var(--chip-width)] ease-in-out translate-x-[var(--translate-x)] rtl:translate-x-[var(--rtl-translate-x)] bg-n-solid-1"
      :class="{
        'transition-all duration-300': !isDisabled,
        'opacity-0': !selectedMode,
      }"
      :style="{
        '--chip-width': width,
        '--translate-x': translateValue,
        '--rtl-translate-x': `calc(-1 * var(--translate-x))`,
      }"
    />
  </div>
</template>
