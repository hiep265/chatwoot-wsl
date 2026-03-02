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
  'ai_control_simple',
  'ai_control_simple_conversation',
];
const HANDOFF_LABEL = 'ai_handoff';
const LABEL_ALIASES = {
  fai_handoff: HANDOFF_LABEL,
  // Legacy ASCII -> diacritics
  khach_moi: 'khách_mới',
  khach_quay_lai: 'khách_quay_lại',
  can_theo_doi: 'cần_theo_dõi',
  off_topic: 'ngoài_chủ_đề',
  y_dinh_dat_lich_xac_nhan: 'ý_định_đặt_lịch_xác_nhận',
  cam_xuc_tieu_cuc: 'cảm_xúc_tiêu_cực',
  uu_tien_gap: 'ưu_tiên_gấp',
  ai_upset: 'cảm_xúc_tiêu_cực',
  ai_urgent: 'ưu_tiên_gấp',
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
  const key = String(label || '').replace(/^handover_/, '').replace(/^lý_do_handoff_/, '').toLowerCase();
  const map = {
    'khách_yêu_cầu': 'Khách yêu cầu gặp người',
    'khach_yeu_cau': 'Khách yêu cầu gặp người',
    'ngoài_phạm_vi': 'Ngoài phạm vi AI',
    'ngoai_pham_vi': 'Ngoài phạm vi AI',
    'cơ_hội_chốt_đơn': 'Cơ hội chốt đơn',
    'sales_opportunity': 'Cơ hội chốt đơn',
    'khách_tiêu_cực': 'Khách tiêu cực',
    'negative_sentiment': 'Khách tiêu cực',
    'xác_nhận_thanh_toán': 'Xác nhận thanh toán',
  };
  return map[key] || (key ? key.replace(/_/g, ' ') : '');
};

const aiLabelDisplayName = rawLabel => {
  const label = normalizeLabelKey(rawLabel);
  const map = {
    'ý_định_đặt_lịch_xác_nhận': 'AI chốt lịch thành công',
    'intent_booking_confirmed': 'AI chốt lịch thành công',
    'ai_handoff': 'Chuyển nhân viên',
    'cảm_xúc_tiêu_cực': 'Khách bực / tiêu cực',
    'ưu_tiên_gấp': 'Ưu tiên gấp',
    'khách_tiềm_năng': 'Khách tiềm năng',
    'khách_tiềm_năng_cao': 'Khách tiềm năng (tốt)',
    'khách_tiềm_năng_trung_bình': 'Khách tiềm năng (trung bình)',
    'khách_tiềm_năng_thấp': 'Khách tiềm năng (kém)',
    'thu_thập_thanh_toán': 'Thu thập thanh toán',
    'khách_mới': 'Khách mới',
    'khách_quay_lại': 'Khách quay lại',
    'cần_theo_dõi': 'Cần theo dõi',
    'ngoài_chủ_đề': 'Ngoài chủ đề',
    'chờ_xét_thanh_toán': 'Chờ xét thanh toán',
  };

  if (map[label]) return map[label];
  if (label.startsWith('handover_') || label.startsWith('lý_do_handoff_')) return handoverReasonDisplay(label);

  return toTitleCase(
    label
      .replace(/^ai_/, '')
      .replace(/^intent_/, '')
      .replace(/^ý_định_/, '')
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
