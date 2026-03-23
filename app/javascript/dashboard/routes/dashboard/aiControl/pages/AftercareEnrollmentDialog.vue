<script setup>
import { computed, ref, watch } from 'vue';

import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  show: {
    type: Boolean,
    default: false,
  },
  conversationId: {
    type: [String, Number],
    default: '',
  },
  conversationLabel: {
    type: String,
    default: '',
  },
  contactEmail: {
    type: String,
    default: '',
  },
  sequences: {
    type: Array,
    default: () => [],
  },
  eligibility: {
    type: Object,
    default: null,
  },
  isLoading: {
    type: Boolean,
    default: false,
  },
  isSubmitting: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['update:show', 'submit']);

const form = ref({
  sequenceId: null,
  contactEmail: '',
  staffNote: '',
  timezoneName: 'Asia/Bangkok',
  anchorAt: '',
  steps: [],
});

const selectedSequence = computed(() => {
  return (props.sequences || []).find(
    item => String(item?.id || '') === String(form.value.sequenceId || '')
  );
});

const isEligible = computed(() => {
  return Boolean(props.eligibility?.eligible);
});

const isSubmitDisabled = computed(() => {
  return (
    props.isLoading ||
    props.isSubmitting ||
    !props.conversationId ||
    !form.value.sequenceId ||
    !form.value.anchorAt ||
    !isEligible.value
  );
});

const eligibilityText = computed(() => {
  if (!props.eligibility) return 'Đang kiểm tra điều kiện kích hoạt...';
  if (props.eligibility.eligible) {
    return `Hội thoại đủ điều kiện để kích hoạt tư vấn sau mua từ ${props.eligibility.channel_key || 'kênh hiện tại'}. Các mốc ngoài 24 giờ sẽ chuyển sang Gmail nếu khách có email.`;
  }

  switch (props.eligibility.reason_code) {
    case 'unsupported_channel':
      return 'Kênh hiện tại chưa thuộc phạm vi Messenger / Instagram của MVP.';
    case 'channel_capability_disabled':
      return 'Khả năng gửi tư vấn sau mua của kênh này đang bị tắt.';
    case 'outside_messaging_window':
      return 'Hội thoại đã ra ngoài cửa sổ hợp lệ để kích hoạt tư vấn sau mua.';
    default:
      return 'Hội thoại hiện chưa đủ điều kiện kích hoạt tư vấn sau mua.';
  }
});

const formatLocalDateTime = value => {
  if (!value) return '';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return '';
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  const hours = String(date.getHours()).padStart(2, '0');
  const minutes = String(date.getMinutes()).padStart(2, '0');
  return `${year}-${month}-${day}T${hours}:${minutes}`;
};

const buildStepRows = () => {
  const anchor = form.value.anchorAt ? new Date(form.value.anchorAt) : null;
  form.value.steps = (selectedSequence.value?.steps || []).map(step => {
    const scheduledAt = anchor
      ? new Date(
          anchor.getTime() + Number(step?.offset_minutes || 0) * 60 * 1000
        )
      : null;

    return {
      position: Number(step?.position || 0),
      title: step?.title || '',
      instructions: step?.instructions || '',
      enabled: Boolean(step?.enabled ?? true),
      scheduledFor: scheduledAt
        ? formatLocalDateTime(scheduledAt.toISOString())
        : '',
      stepNote: '',
    };
  });
};

const initializeForm = () => {
  const firstSequence = props.sequences?.[0];
  const defaultAnchor = new Date(Date.now() + 24 * 60 * 60 * 1000);

  form.value.sequenceId = firstSequence?.id || null;
  form.value.contactEmail = String(props.contactEmail || '').trim();
  form.value.staffNote = '';
  form.value.timezoneName = firstSequence?.default_timezone || 'Asia/Bangkok';
  form.value.anchorAt = formatLocalDateTime(defaultAnchor.toISOString());
  buildStepRows();
};

watch(
  () => props.contactEmail,
  value => {
    if (!props.show) return;
    form.value.contactEmail = String(value || '').trim();
  }
);

watch(
  () => props.show,
  show => {
    if (show) initializeForm();
  }
);

watch(
  () => props.sequences,
  sequences => {
    if (!props.show || !Array.isArray(sequences) || !sequences.length) return;
    if (!form.value.sequenceId) {
      form.value.sequenceId = sequences[0].id;
      form.value.timezoneName = sequences[0].default_timezone || 'Asia/Bangkok';
    }
    buildStepRows();
  }
);

watch(
  () => form.value.sequenceId,
  () => {
    const timezone = selectedSequence.value?.default_timezone;
    if (timezone) form.value.timezoneName = timezone;
    buildStepRows();
  }
);

watch(
  () => form.value.anchorAt,
  () => {
    if (selectedSequence.value) buildStepRows();
  }
);

const close = () => {
  emit('update:show', false);
};

const submit = () => {
  if (isSubmitDisabled.value) return;

  emit('submit', {
    conversationId: String(props.conversationId || ''),
    sequenceId: Number(form.value.sequenceId),
    contactEmail: String(form.value.contactEmail || '').trim(),
    staffNote: form.value.staffNote,
    timezoneName: form.value.timezoneName,
    anchorAt: new Date(form.value.anchorAt).toISOString(),
    steps: form.value.steps.map(step => ({
      position: step.position,
      title: step.title,
      instructions: step.instructions,
      enabled: step.enabled,
      scheduledFor: step.scheduledFor
        ? new Date(step.scheduledFor).toISOString()
        : null,
      stepNote: step.stepNote,
    })),
  });
};
</script>

<template>
  <woot-modal :show="show" :on-close="close" @update:show="close">
    <div class="p-6 max-w-3xl">
      <div class="flex items-start justify-between gap-4">
        <div>
          <div class="text-lg font-semibold text-n-slate-12">
            Tư vấn sau mua
          </div>
          <div class="mt-1 text-sm text-n-slate-11">
            {{ conversationLabel || `Hội thoại #${conversationId || '--'}` }}
          </div>
        </div>
        <Button label="Đóng" color="slate" variant="smooth" @click="close" />
      </div>

      <div
        class="mt-5 rounded-xl border px-4 py-3 text-sm"
        :class="
          isEligible
            ? 'border-n-teal-4 bg-n-teal-2/50 text-n-teal-12'
            : 'border-n-ruby-4 bg-n-ruby-2 text-n-ruby-11'
        "
      >
        {{ eligibilityText }}
      </div>

      <div v-if="isLoading" class="py-8 text-center text-sm text-n-slate-11">
        Đang tải cấu hình tư vấn sau mua...
      </div>

      <div v-else class="mt-5 flex flex-col gap-5">
        <label class="flex flex-col gap-1.5 text-sm text-n-slate-12">
          <span class="font-medium">Email khách hàng</span>
          <input
            data-test-id="aftercare-contact-email-input"
            v-model="form.contactEmail"
            type="email"
            class="h-10 rounded-xl border border-n-slate-4 bg-n-background px-3"
            placeholder="khach@example.com"
          />
          <span class="text-xs text-n-slate-10">
            Các bước ngoài 24 giờ sẽ gửi tới email này nếu Gmail/SMTP của Chatwoot đã
            sẵn sàng.
          </span>
        </label>

        <div class="grid gap-4 md:grid-cols-2">
          <label class="flex flex-col gap-1.5 text-sm text-n-slate-12">
            <span class="font-medium">Chuỗi chăm sóc</span>
            <select
              v-model="form.sequenceId"
              class="h-10 rounded-xl border border-n-slate-4 bg-n-background px-3"
            >
              <option
                v-for="sequence in sequences"
                :key="sequence.id"
                :value="sequence.id"
              >
                {{ sequence.name }}
              </option>
            </select>
          </label>

          <label class="flex flex-col gap-1.5 text-sm text-n-slate-12">
            <span class="font-medium">Múi giờ</span>
            <input
              v-model="form.timezoneName"
              type="text"
              class="h-10 rounded-xl border border-n-slate-4 bg-n-background px-3"
            />
          </label>
        </div>

        <label class="flex flex-col gap-1.5 text-sm text-n-slate-12">
          <span class="font-medium">Mốc bắt đầu gửi</span>
          <input
            data-test-id="aftercare-anchor-input"
            v-model="form.anchorAt"
            type="datetime-local"
            class="h-10 rounded-xl border border-n-slate-4 bg-n-background px-3"
          />
        </label>

        <label class="flex flex-col gap-1.5 text-sm text-n-slate-12">
          <span class="font-medium">Ghi chú cho AI</span>
          <textarea
            data-test-id="aftercare-note-input"
            v-model="form.staffNote"
            rows="4"
            class="rounded-xl border border-n-slate-4 bg-n-background px-3 py-2"
            placeholder="Ví dụ: khách vừa mua gói cơ bản, cần theo dõi lại nhẹ nhàng và thực tế."
          />
        </label>

        <div class="rounded-2xl border border-n-slate-3 bg-n-solid-2/40 p-4">
          <div class="text-sm font-semibold text-n-slate-12">Lịch gửi từng bước</div>
          <div class="mt-3 flex flex-col gap-3">
            <div
              v-for="step in form.steps"
              :key="`aftercare-step-${step.position}`"
              class="rounded-xl border border-n-slate-3 bg-n-solid-1 p-3"
            >
              <div class="flex items-center justify-between gap-3">
                <div class="min-w-0">
                  <div class="text-sm font-medium text-n-slate-12">
                    Bước {{ step.position }} · {{ step.title }}
                  </div>
                  <div class="mt-1 text-xs text-n-slate-11">
                    {{ step.instructions || 'Chưa có hướng dẫn riêng.' }}
                  </div>
                </div>
                <label class="flex items-center gap-2 text-xs text-n-slate-11">
                  <input v-model="step.enabled" type="checkbox" />
                  Bật bước
                </label>
              </div>

              <div class="mt-3 grid gap-3 md:grid-cols-2">
                <input
                  v-model="step.scheduledFor"
                  type="datetime-local"
                  class="h-10 rounded-xl border border-n-slate-4 bg-n-background px-3 text-sm"
                />
                <input
                  v-model="step.stepNote"
                  type="text"
                  class="h-10 rounded-xl border border-n-slate-4 bg-n-background px-3 text-sm"
                  placeholder="Ghi chú riêng cho bước này"
                />
              </div>
            </div>
          </div>
        </div>

        <div class="flex justify-end gap-3">
          <Button label="Hủy" color="slate" variant="smooth" @click="close" />
          <Button
            data-test-id="aftercare-submit"
            label="Tạo kế hoạch"
            color="blue"
            :is-loading="isSubmitting"
            :disabled="isSubmitDisabled"
            @click="submit"
          />
        </div>
      </div>
    </div>
  </woot-modal>
</template>
