<script setup>
import { ref, computed, watch, onMounted, nextTick, useSlots } from 'vue';
import { useRoute } from 'vue-router';
import { useMapGetter } from 'dashboard/composables/store';

const props = defineProps({
  conversationLabels: {
    type: Array,
    required: true,
  },
});

const slots = useSlots();
const route = useRoute();
const accountLabels = useMapGetter('labels/getLabels');
const AI_CONTROL_ROUTE_NAMES = [
  'ai_control_panel',
  'ai_control_panel_conversation',
];
const HANDOFF_LABEL = 'ai_handoff';
const LABEL_ALIASES = {
  fai_handoff: HANDOFF_LABEL,
};

const isAiControlMode = computed(() => {
  return AI_CONTROL_ROUTE_NAMES.includes(String(route.name || ''));
});

const normalizeLabelKey = label => {
  const key = String(label || '').toLowerCase();
  return LABEL_ALIASES[key] || key;
};

const toTitleCase = text => {
  const value = String(text || '').trim();
  if (!value) return '';
  return value.charAt(0).toUpperCase() + value.slice(1);
};

const handoverReasonDisplay = label => {
  const key = String(label || '').replace(/^handover_/, '').toLowerCase();
  const map = {
    khach_yeu_cau: 'Khách yêu cầu gặp người',
    ngoai_pham_vi: 'Ngoài phạm vi AI',
    sales_opportunity: 'Cơ hội chốt đơn',
    negative_sentiment: 'Khách tiêu cực',
  };
  return map[key] || (key ? key.replace(/_/g, ' ') : '');
};

const aiLabelDisplayName = rawLabel => {
  const label = normalizeLabelKey(rawLabel);
  const map = {
    intent_booking_confirmed: 'AI chốt lịch thành công',
    ai_handoff: 'Chuyển nhân viên',
    ai_upset: 'Khách bực / tiêu cực',
    ai_urgent: 'Ưu tiên gấp',
    ai_lead: 'Khách tiềm năng',
    ai_lead_high: 'Khách tiềm năng (tốt)',
    ai_lead_medium: 'Khách tiềm năng (trung bình)',
    ai_lead_low: 'Khách tiềm năng (kém)',
    payment_collection: 'Thu thập thanh toán',
  };

  if (map[label]) return map[label];
  if (label.startsWith('handover_')) return handoverReasonDisplay(label);

  return toTitleCase(
    label
      .replace(/^ai_/, '')
      .replace(/^intent_/, '')
      .replace(/_/g, ' ')
  );
};

const normalizedConversationLabels = computed(() => {
  const labels = Array.isArray(props.conversationLabels)
    ? props.conversationLabels
    : [];
  const normalized = labels.map(label => normalizeLabelKey(label)).filter(Boolean);
  return [...new Set(normalized)];
});

const activeLabels = computed(() => {
  if (!isAiControlMode.value) {
    return accountLabels.value.filter(({ title }) =>
      props.conversationLabels.includes(title)
    );
  }

  const labelMap = new Map(
    accountLabels.value.map(label => [normalizeLabelKey(label.title), label])
  );

  return normalizedConversationLabels.value.map(labelKey => {
    const existing = labelMap.get(labelKey);
    if (existing) {
      return {
        ...existing,
        title: aiLabelDisplayName(labelKey),
      };
    }

    return {
      id: `ai-fallback-${labelKey}`,
      title: aiLabelDisplayName(labelKey),
      description: '',
      color: '#64748b',
    };
  });
});

const showAllLabels = ref(false);
const showExpandLabelButton = ref(false);
const labelPosition = ref(-1);
const labelContainer = ref(null);

const computeVisibleLabelPosition = () => {
  const beforeSlot = slots.before ? 100 : 0;
  if (!labelContainer.value) {
    return;
  }

  const labels = Array.from(labelContainer.value.querySelectorAll('.label'));
  let labelOffset = 0;
  showExpandLabelButton.value = false;
  labels.forEach((label, index) => {
    labelOffset += label.offsetWidth + 8;

    if (labelOffset < labelContainer.value.clientWidth - beforeSlot) {
      labelPosition.value = index;
    } else {
      showExpandLabelButton.value = labels.length > 1;
    }
  });
};

watch(activeLabels, () => {
  nextTick(() => computeVisibleLabelPosition());
});

onMounted(() => {
  computeVisibleLabelPosition();
});

const onShowLabels = e => {
  e.stopPropagation();
  showAllLabels.value = !showAllLabels.value;
  nextTick(() => computeVisibleLabelPosition());
};
</script>

<template>
  <div ref="labelContainer" v-resize="computeVisibleLabelPosition">
    <div
      v-if="activeLabels.length || $slots.before"
      class="flex items-end flex-shrink min-w-0 gap-y-1"
      :class="{ 'h-auto overflow-visible flex-row flex-wrap': showAllLabels }"
    >
      <slot name="before" />
      <woot-label
        v-for="(label, index) in activeLabels"
        :key="label ? label.id : index"
        :title="label.title"
        :description="label.description"
        :color="label.color"
        variant="smooth"
        class="!mb-0 max-w-[calc(100%-0.5rem)]"
        small
        :class="{
          'invisible absolute': !showAllLabels && index > labelPosition,
        }"
      />
      <button
        v-if="showExpandLabelButton"
        :title="
          showAllLabels
            ? $t('CONVERSATION.CARD.HIDE_LABELS')
            : $t('CONVERSATION.CARD.SHOW_LABELS')
        "
        class="h-5 py-0 px-1 flex-shrink-0 mr-6 ml-0 rtl:ml-6 rtl:mr-0 rtl:rotate-180 text-n-slate-11 border-n-strong dark:border-n-strong"
        @click="onShowLabels"
      >
        <fluent-icon
          :icon="showAllLabels ? 'chevron-left' : 'chevron-right'"
          size="12"
        />
      </button>
    </div>
  </div>
</template>
