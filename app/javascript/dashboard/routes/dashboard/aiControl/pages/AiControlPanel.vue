<script setup>
import { computed, onMounted, onBeforeUnmount, ref } from 'vue';
import { useRoute } from 'vue-router';

import ReportsAPI from 'dashboard/api/reports';
import SummaryReportsAPI from 'dashboard/api/summaryReports';
import ConversationLabelsAPI from 'dashboard/api/conversations';
import InboxConversationAPI from 'dashboard/api/inbox/conversation';

import ReportHeader from '../../settings/reports/components/ReportHeader.vue';
import ReportFilterSelector from '../../settings/reports/components/FilterSelector.vue';
import ConversationView from '../../conversation/ConversationView.vue';

import Button from 'dashboard/components-next/button/Button.vue';

import { useAlert } from 'dashboard/composables';
import { emitter } from 'shared/helpers/mitt';

const props = defineProps({
  standalone: {
    type: Boolean,
    default: false,
  },
});

const route = useRoute();

const from = ref(0);
const to = ref(0);

const activeKpiTab = ref('traffic');

const trafficConversationCount = ref(0);
const botConversationCount = ref(0);
const botMessageCount = ref('0');

const labelSummary = ref([]);

const liveConversations = ref([]);
const isLiveConversationsLoading = ref(false);

// Chỉ dùng ai_handoff để đánh dấu cả chuyển nhân viên và dừng AI
const HANDOFF_LABEL = 'ai_handoff';
const LABEL_ALIASES = {
  fai_handoff: HANDOFF_LABEL,
};

const normalizeLabelKey = label => {
  const key = String(label || '').toLowerCase();
  return LABEL_ALIASES[key] || key;
};

const isTakeoverAllLoading = ref(false);

const riskConversationIds = ref(new Set());
const isRiskBannerVisible = ref(false);
const isRiskBannerBlinking = ref(false);
const riskBannerText = ref('');
const riskAudio = ref(null);
const aiControlConversationId = computed(() => route.params.conversation_id || 0);
const adminPanelRoute = computed(() => {
  return {
    name: 'ai_control_panel',
    params: { accountId: route.params.accountId },
  };
});

const formatCount = value => {
  return Number(value || 0).toLocaleString();
};

const labelOverviewTotal = computed(() => {
  const trafficTotal = Number(trafficConversationCount.value || 0);
  const botTotal = Number(botConversationCount.value || 0);
  const rows = Array.isArray(labelSummary.value) ? labelSummary.value : [];
  const labelTotal = rows.reduce((total, row) => {
    return total + Number(row?.conversationsCount || row?.conversations_count || 0);
  }, 0);
  const liveTotal = Array.isArray(liveConversations.value)
    ? liveConversations.value.length
    : 0;

  return Math.max(trafficTotal, botTotal, labelTotal, liveTotal);
});

const trafficConversationCountText = computed(() => {
  return formatCount(labelOverviewTotal.value);
});

const trackedLabelCount = labelName => {
  const row = trackedLabelRows.value.find(item => item.name === labelName);
  return Number(row?.conversationsCount || 0);
};

const aiAutomationText = computed(() => {
  const total = Number(labelOverviewTotal.value || 0);
  const resolved = trackedLabelCount('intent_booking_confirmed');
  const rate = total ? Math.round((resolved / total) * 100) : 0;
  return `${formatCount(resolved)} (${rate}%)`;
});

const aiHandoffText = computed(() => {
  const total = Number(labelOverviewTotal.value || 0);
  const handoff = trackedLabelCount('ai_handoff');
  const rate = total ? Math.round((handoff / total) * 100) : 0;
  return `${formatCount(handoff)} (${rate}%)`;
});

const formatDate = timestamp => {
  const value = Number(timestamp || 0);
  if (!value) return '';
  try {
    return new Date(value * 1000).toLocaleDateString('vi-VN');
  } catch (e) {
    return '';
  }
};

const dateRangeText = computed(() => {
  const fromText = formatDate(from.value);
  const toText = formatDate(to.value);
  if (!fromText || !toText) return '';
  return `${fromText} → ${toText}`;
});

const averageBotMessagesPerConversation = computed(() => {
  const conversations = Number(labelOverviewTotal.value || 0);
  const messages = Number(String(botMessageCount.value || '0').replace(/,/g, '') || 0);
  if (!conversations) return 0;
  return Math.round((messages / conversations) * 10) / 10;
});

const topHandoverReasons = computed(() => {
  const rows = Array.isArray(labelSummary.value) ? labelSummary.value : [];
  return rows
    .filter(r => String(r?.name || '').startsWith('handover_'))
    .sort((a, b) => (b.conversationsCount || 0) - (a.conversationsCount || 0))
    .slice(0, 5);
});

const normalizeLabelSummary = summary => {
  if (!Array.isArray(summary)) return [];
  return summary.map(row => {
    const conversationsCount = row.conversationsCount ?? row.conversations_count;
    return {
      name: row.name,
      conversationsCount: Number(conversationsCount || 0),
    };
  });
};

const trackedLabelNames = computed(() => {
  // Chỉ theo dõi các nhãn liên quan (đã bỏ ai_paused và khongtraloibangai)
  return [
    'ai_handoff',          // Chuyển nhân viên (đồng thời là dừng AI)
    'ai_lead',             // Khách tiềm năng
    'ai_lead_high',        // Khách tiềm năng (tốt)
    'ai_lead_medium',      // Khách tiềm năng (trung bình)
    'ai_lead_low',         // Khách tiềm năng (kém)
    'ai_urgent',           // Ưu tiên gấp
    'ai_upset',            // Khách bực / tiêu cực
    'intent_booking_confirmed',  // AI chốt lịch thành công
  ];
});

const liveLabelCountByName = computed(() => {
  const counts = {};
  const conversations = Array.isArray(liveConversations.value)
    ? liveConversations.value
    : [];

  conversations.forEach(conversation => {
    const labels = Array.isArray(conversation?.labels) ? conversation.labels : [];
    labels.forEach(label => {
      const normalizedLabel = normalizeLabelKey(label);
      if (!trackedLabelNames.value.includes(normalizedLabel)) return;
      counts[normalizedLabel] = Number(counts[normalizedLabel] || 0) + 1;
    });
  });

  return counts;
});

const trackedLabelRows = computed(() => {
  const map = new Map(
    labelSummary.value.map(row => [normalizeLabelKey(row?.name), row])
  );
  return trackedLabelNames.value.map(name => {
    const summaryCount = Number(map.get(name)?.conversationsCount || 0);
    const liveCount = Number(liveLabelCountByName.value[name] || 0);
    return {
      name,
      conversationsCount: Math.max(summaryCount, liveCount),
    };
  });
});

const handoverReasonDisplay = label => {
  const raw = String(label || '');
  const key = raw.replace(/^handover_/, '').toLowerCase();
  const map = {
    khach_yeu_cau: 'Khách yêu cầu gặp người',
    ngoai_pham_vi: 'Ngoài phạm vi AI',
    sales_opportunity: 'Cơ hội chốt đơn',
    negative_sentiment: 'Khách tiêu cực',
  };
  if (map[key]) return map[key];
  return key ? key.replace(/_/g, ' ') : raw;
};

const toTitleCase = text => {
  const value = String(text || '').trim();
  if (!value) return '';
  return value.charAt(0).toUpperCase() + value.slice(1);
};

const formatUnknownLabelDisplay = rawLabel => {
  const label = String(rawLabel || '').toLowerCase();
  if (!label) return '';
  if (label.startsWith('handover_')) return handoverReasonDisplay(label);

  const normalized = label
    .replace(/^ai_/, '')
    .replace(/^intent_/, '')
    .replace(/_/g, ' ');

  return toTitleCase(normalized);
};

const labelDisplayName = name => {
  const normalizedName = normalizeLabelKey(name);
  const map = {
    intent_booking_confirmed: 'AI chốt lịch thành công',
    ai_handoff: 'Chuyển nhân viên',           // Đồng thời là dừng AI
    fai_handoff: 'Chuyển nhân viên',
    ai_upset: 'Khách bực / tiêu cực',
    ai_urgent: 'Ưu tiên gấp',
    ai_lead: 'Khách tiềm năng',
    ai_lead_high: 'Khách tiềm năng (tốt)',
    ai_lead_medium: 'Khách tiềm năng (trung bình)',
    ai_lead_low: 'Khách tiềm năng (kém)',
    payment_collection: 'Thu thập thanh toán',
    // Đã bỏ: ai_paused, khongtraloibangai (gộp vào ai_handoff)
  };
  return map[normalizedName] || formatUnknownLabelDisplay(normalizedName);
};

const labelTone = name => {
  const normalizedName = normalizeLabelKey(name);
  if (normalizedName.startsWith('handover_')) return 'amber';

  const map = {
    intent_booking_confirmed: 'teal',
    ai_handoff: 'ruby',
    fai_handoff: 'ruby',
    ai_upset: 'ruby',
    ai_urgent: 'amber',
    ai_lead: 'blue',
    ai_lead_high: 'teal',
    ai_lead_medium: 'amber',
    ai_lead_low: 'ruby',
    payment_collection: 'blue',
    // Đã bỏ: ai_paused, khongtraloibangai (gộp vào ai_handoff)
  };
  return map[normalizedName] || 'slate';
};

const formatPercent = value => {
  if (!value) return 0;
  if (value > 0 && value < 0.1) return 0.1;
  if (value < 1) return Number(value.toFixed(1));
  return Math.round(value);
};

const labelPercent = row => {
  const total = Number(labelOverviewTotal.value || 0);
  const count = Number(row?.conversationsCount || 0);
  if (!total || !count) return 0;
  return Math.min(100, formatPercent((count / total) * 100));
};

const kpiTabClass = key => {
  return activeKpiTab.value === key
    ? 'outline-n-slate-12 ring-2 ring-n-slate-12/10'
    : 'outline-n-container hover:outline-n-slate-10';
};

const labelRoute = label => {
  return {
    name: 'label_conversations',
    params: {
      accountId: route.params.accountId,
      label,
    },
  };
};

const isConversationInHumanMode = conversation => {
  // Chỉ dùng ai_handoff để đánh dấu chế độ human
  const labels = Array.isArray(conversation?.labels) ? conversation.labels : [];
  const normalizedLabels = labels.map(label => normalizeLabelKey(label));
  return normalizedLabels.includes(HANDOFF_LABEL);
};

const isConversationPaused = conversation => {
  return isConversationInHumanMode(conversation);
};

const isAllPaused = computed(() => {
  const conversations = Array.isArray(liveConversations.value)
    ? liveConversations.value
    : [];
  if (!conversations.length) return false;
  return conversations.every(isConversationPaused);
});

const fetchTrafficSummary = async () => {
  if (!to.value || !from.value) return;

  const response = await ReportsAPI.getSummary(
    from.value,
    to.value,
    'account',
    undefined,
    undefined,
    false
  );
  const data = response?.data || {};

  trafficConversationCount.value = Number(
    data.incoming_conversations_count || data.conversations_count || 0
  );
};

const fetchBotMetrics = async () => {
  if (!to.value || !from.value) return;

  try {
    const response = await ReportsAPI.getBotMetrics({ from: from.value, to: to.value });
    const data = response?.data || {};
    botConversationCount.value = Number(data.conversation_count || 0);
    botMessageCount.value = Number(data.message_count || 0).toLocaleString();

    // Debug: hiển thị message_count trong console
    // eslint-disable-next-line no-console
    console.log('[BotMetrics] message_count:', data.message_count);
    // eslint-disable-next-line no-console
    console.log('[BotMetrics] debug info:', data.debug);
  } catch (e) {
    botConversationCount.value = 0;
    botMessageCount.value = '0';
  }
};

const fetchLabelSummary = async () => {
  if (!to.value || !from.value) return;

  const response = await SummaryReportsAPI.getLabelReports({
    since: from.value,
    until: to.value,
    businessHours: false,
  });
  labelSummary.value = normalizeLabelSummary(response?.data);
};

const isRiskConversation = conversation => {
  const labels = Array.isArray(conversation?.labels) ? conversation.labels : [];
  const normalizedLabels = labels.map(label => normalizeLabelKey(label));
  return normalizedLabels.includes('ai_urgent') ||
    normalizedLabels.includes('ai_upset') ||
    normalizedLabels.includes(HANDOFF_LABEL);
};

const playRiskSound = async () => {
  try {
    if (!riskAudio.value) {
      riskAudio.value = new Audio('/audio/dashboard/ding.mp3');
      riskAudio.value.load();
    }
    await riskAudio.value.play();
  } catch (error) {
    useAlert('Trình duyệt đang chặn âm thanh cảnh báo. Hãy cho phép âm thanh để nhận cảnh báo.');
  }
};

const updateRiskBanner = async () => {
  const risky = (liveConversations.value || []).filter(isRiskConversation);
  const nextIds = new Set(risky.map(c => String(c?.id || '')).filter(Boolean));

  const prevIds = riskConversationIds.value;
  const hasNew = Array.from(nextIds).some(id => !prevIds.has(id));
  const hasAny = nextIds.size > 0;

  riskConversationIds.value = nextIds;
  isRiskBannerVisible.value = hasAny;
  if (!hasAny) {
    isRiskBannerBlinking.value = false;
    riskBannerText.value = '';
    return;
  }

  riskBannerText.value = `Cảnh báo rủi ro: ${nextIds.size} hội thoại cần ưu tiên`;
  isRiskBannerBlinking.value = hasNew;
  if (hasNew) {
    useAlert(riskBannerText.value);
    await playRiskSound();
    setTimeout(() => {
      isRiskBannerBlinking.value = false;
    }, 15000);
  }
};

const fetchLiveConversations = async () => {
  isLiveConversationsLoading.value = true;
  try {
    const response = await InboxConversationAPI.get({
      status: 'open',
      assigneeType: 'all',
      sortBy: 'last_activity_at_desc',
      page: 1,
    });

    const payload = response?.data?.data?.payload;
    const conversations = Array.isArray(payload) ? payload : [];

    liveConversations.value = conversations.filter(conversation => {
      return ['open', 'pending', 'snoozed'].includes(conversation?.status);
    });
    await updateRiskBanner();
  } catch (e) {
    liveConversations.value = [];
    useAlert('Không tải được danh sách hội thoại.');
  } finally {
    isLiveConversationsLoading.value = false;
  }
};

const fetchAll = async () => {
  try {
    await Promise.all([
      fetchTrafficSummary(),
      fetchBotMetrics(),
      fetchLabelSummary(),
      fetchLiveConversations(),
    ]);
  } catch (e) {
    useAlert('Không tải được dữ liệu báo cáo.');
  }
};

const onFilterChange = async ({ from: nextFrom, to: nextTo }) => {
  from.value = nextFrom;
  to.value = nextTo;
  await fetchAll();
};

const setConversationPause = async (conversationId, shouldPause) => {
  const id = String(conversationId || '').trim();
  if (!id) return;

  try {
    const response = await ConversationLabelsAPI.getLabels(id);
    const currentLabels = response?.data?.payload || [];

    const next = new Set(Array.isArray(currentLabels) ? currentLabels : []);
    if (shouldPause) {
      // Chỉ dùng ai_handoff để đánh dấu tiếp quản ngay
      next.add(HANDOFF_LABEL);
    } else {
      // Tắt tiếp quản ngay = gỡ ai_handoff
      next.delete(HANDOFF_LABEL);
    }

    await ConversationLabelsAPI.updateLabels(id, Array.from(next));

    liveConversations.value = (liveConversations.value || []).map(c => {
      if (String(c?.id) !== id) return c;
      return { ...c, labels: Array.from(next) };
    });
  } catch (e) {
    useAlert('Không thể cập nhật trạng thái dừng AI cho hội thoại này.');
  }
};

const togglePauseAll = async () => {
  const conversations = Array.isArray(liveConversations.value)
    ? liveConversations.value
    : [];
  if (!conversations.length) return;

  const shouldPause = !isAllPaused.value;
  isTakeoverAllLoading.value = true;
  try {
    for (const c of conversations) {
      const id = String(c?.id || '').trim();
      if (!id) continue;
      await setConversationPause(id, shouldPause);
    }
    if (to.value && from.value) {
      await Promise.all([fetchTrafficSummary(), fetchBotMetrics(), fetchLabelSummary()]);
    }
  } finally {
    isTakeoverAllLoading.value = false;
  }
};

const onRefreshLiveConversations = async () => {
  await fetchLiveConversations();
  if (to.value && from.value) {
    await Promise.all([fetchTrafficSummary(), fetchBotMetrics(), fetchLabelSummary()]);
  }
};

onMounted(() => {
  emitter.on('ai_control_panel:refresh_live_conversations', onRefreshLiveConversations);
  // Fetch happens after the first filter event
});

onBeforeUnmount(() => {
  emitter.off('ai_control_panel:refresh_live_conversations', onRefreshLiveConversations);
});
</script>

<template>
  <div class="overflow-auto bg-n-background w-full px-6">
    <div class="max-w-[80rem] mx-auto pb-12">
      <ReportHeader
        header-title="Bảng điều khiển AI"
        header-description="Theo dõi hiệu suất, rủi ro và vận hành AI theo thời gian thực"
      >
        <router-link v-if="props.standalone" :to="adminPanelRoute">
          <Button
            color="slate"
            size="sm"
            class="h-10"
            label="Vào trang quản trị"
          />
        </router-link>
      </ReportHeader>

      <div class="flex flex-col gap-4 pb-6">
        <div
          v-if="isRiskBannerVisible"
          class="sticky top-0 z-10 rounded-xl outline outline-1 px-4 py-3"
          :class="
            isRiskBannerBlinking
              ? 'bg-n-ruby-3 text-n-ruby-12 outline-n-ruby-4 animate-pulse'
              : 'bg-n-ruby-3 text-n-ruby-12 outline-n-ruby-4'
          "
        >
          <div class="flex items-center justify-between gap-3">
            <div class="text-sm font-medium">
              {{ riskBannerText }}
            </div>
            <Button
              color="slate"
              size="sm"
              class="h-9"
              :is-loading="isLiveConversationsLoading"
              label="Làm mới"
              @click="fetchLiveConversations"
            />
          </div>
        </div>

        <ReportFilterSelector
          :show-agents-filter="false"
          :show-group-by-filter="false"
          :show-business-hours-switch="false"
          @filterChange="onFilterChange"
          @filter-change="onFilterChange"
        />

        <div class="grid gap-4 md:grid-cols-2 lg:grid-cols-4">
          <div
            class="rounded-xl outline outline-1 bg-n-blue-3 px-5 py-4 cursor-pointer"
            :class="kpiTabClass('traffic')"
            @click="activeKpiTab = 'traffic'"
          >
            <div class="text-xs font-medium text-n-blue-12">
              Lưu lượng
            </div>
            <div class="mt-1 text-3xl font-semibold text-n-blue-12">
              {{ trafficConversationCountText }}
            </div>
            <div class="mt-1 text-xs text-n-blue-11">
              Tổng số hội thoại trong khoảng thời gian
            </div>
          </div>

          <div
            class="rounded-xl outline outline-1 bg-n-teal-3 px-5 py-4 cursor-pointer"
            :class="kpiTabClass('ai_resolved')"
            @click="activeKpiTab = 'ai_resolved'"
          >
            <div class="text-xs font-medium text-n-teal-12">
              AI tự xử lý
            </div>
            <div class="mt-1 text-3xl font-semibold text-n-teal-12">
              {{ aiAutomationText }}
            </div>
            <div class="mt-1 text-xs text-n-teal-11">
              Tính theo nhãn: #intent_booking_confirmed
            </div>
          </div>

          <div
            class="rounded-xl outline outline-1 bg-n-ruby-3 px-5 py-4 cursor-pointer"
            :class="kpiTabClass('handoff')"
            @click="activeKpiTab = 'handoff'"
          >
            <div class="text-xs font-medium text-n-ruby-12">
              AI chuyển nhân viên
            </div>
            <div class="mt-1 text-3xl font-semibold text-n-ruby-12">
              {{ aiHandoffText }}
            </div>
            <div class="mt-1 text-xs text-n-ruby-11">
              Số hội thoại chuyển cho nhân viên
            </div>
          </div>

          <div
            class="rounded-xl outline outline-1 bg-n-solid-2 px-5 py-4 cursor-pointer"
            :class="kpiTabClass('bot_messages')"
            @click="activeKpiTab = 'bot_messages'"
          >
            <div class="text-xs font-medium text-n-slate-12">
              Tổng tin nhắn bot
            </div>
            <div class="mt-1 text-3xl font-semibold text-n-slate-12">
              {{ botMessageCount }}
            </div>
            <div class="mt-1 text-xs text-n-slate-11">
              Tổng số tin nhắn bot gửi đi
            </div>
          </div>
        </div>

        <div class="shadow outline-1 outline outline-n-container rounded-xl bg-n-solid-2 px-6 py-5">
          <div class="flex items-center justify-between gap-3">
            <div class="flex flex-col gap-1">
              <div class="text-base font-medium text-n-slate-12">
                Chi tiết
              </div>
              <div v-if="dateRangeText" class="text-sm text-n-slate-11">
                Khoảng thời gian: {{ dateRangeText }}
              </div>
            </div>
          </div>

          <div v-if="activeKpiTab === 'traffic'" class="mt-4 grid gap-3">
            <div class="text-sm text-n-slate-12">
              Lưu lượng là tổng số hội thoại trong khoảng thời gian đã chọn.
            </div>
            <div class="grid gap-2 md:grid-cols-2">
              <div class="rounded-lg outline outline-1 outline-n-weak px-4 py-3">
                <div class="text-xs text-n-slate-11">Tổng hội thoại</div>
                <div class="text-2xl font-semibold text-n-slate-12">{{ trafficConversationCountText }}</div>
              </div>
              <div class="rounded-lg outline outline-1 outline-n-weak px-4 py-3">
                <div class="text-xs text-n-slate-11">Hội thoại đang mở</div>
                <div class="text-2xl font-semibold text-n-slate-12">{{ (liveConversations || []).length.toLocaleString() }}</div>
              </div>
            </div>
          </div>

          <div v-else-if="activeKpiTab === 'ai_resolved'" class="mt-4 grid gap-3">
            <div class="text-sm text-n-slate-12">
              AI tự xử lý được tính khi hội thoại có nhãn <span class="font-medium">#intent_booking_confirmed</span>.
            </div>
            <div class="grid gap-2 md:grid-cols-2">
              <div class="rounded-lg outline outline-1 outline-n-weak px-4 py-3">
                <div class="text-xs text-n-slate-11">Số hội thoại AI chốt lịch</div>
                <div class="text-2xl font-semibold text-n-slate-12">{{ aiAutomationText }}</div>
              </div>
              <router-link
                class="rounded-lg outline outline-1 outline-n-weak px-4 py-3 hover:underline"
                :to="labelRoute('intent_booking_confirmed')"
              >
                <div class="text-xs text-n-slate-11">Xem danh sách</div>
                <div class="text-sm font-medium text-n-slate-12">Danh sách hội thoại #intent_booking_confirmed</div>
              </router-link>
            </div>
          </div>

          <div v-else-if="activeKpiTab === 'handoff'" class="mt-4 grid gap-3">
            <div class="text-sm text-n-slate-12">
              AI chuyển nhân viên là các hội thoại AI chuyển cho nhân viên xử lý (nhãn <span class="font-medium">#ai_handoff</span>).
            </div>

            <div class="grid gap-2 md:grid-cols-2">
              <div class="rounded-lg outline outline-1 outline-n-weak px-4 py-3">
                <div class="text-xs text-n-slate-11">Tổng chuyển nhân viên</div>
                <div class="text-2xl font-semibold text-n-slate-12">{{ aiHandoffText }}</div>
              </div>
              <router-link
                class="rounded-lg outline outline-1 outline-n-weak px-4 py-3 hover:underline"
                :to="labelRoute('ai_handoff')"
              >
                <div class="text-xs text-n-slate-11">Xem danh sách</div>
                <div class="text-sm font-medium text-n-slate-12">Danh sách hội thoại #ai_handoff</div>
              </router-link>
            </div>

            <div v-if="topHandoverReasons.length" class="rounded-lg outline outline-1 outline-n-weak px-4 py-3">
              <div class="text-sm font-medium text-n-slate-12">5 lý do chuyển nhân viên nhiều nhất</div>
              <div class="mt-2 grid gap-2">
                <div
                  v-for="row in topHandoverReasons"
                  :key="row.name"
                  class="flex items-center justify-between"
                >
                  <div class="text-sm text-n-slate-12">{{ handoverReasonDisplay(row.name) }}</div>
                  <div class="text-sm text-n-slate-11">{{ row.conversationsCount.toLocaleString() }}</div>
                </div>
              </div>
            </div>
          </div>

          <div v-else class="mt-4 grid gap-3">
            <div class="text-sm text-n-slate-12">
              Tổng tin nhắn bot là tổng số tin nhắn bot gửi đi trong khoảng thời gian.
            </div>
            <div class="grid gap-2 md:grid-cols-2">
              <div class="rounded-lg outline outline-1 outline-n-weak px-4 py-3">
                <div class="text-xs text-n-slate-11">Tổng tin nhắn bot</div>
                <div class="text-2xl font-semibold text-n-slate-12">{{ botMessageCount }}</div>
              </div>
              <div class="rounded-lg outline outline-1 outline-n-weak px-4 py-3">
                <div class="text-xs text-n-slate-11">Trung bình / hội thoại</div>
                <div class="text-2xl font-semibold text-n-slate-12">{{ averageBotMessagesPerConversation.toLocaleString() }}</div>
              </div>
            </div>
          </div>
        </div>

        <div class="grid gap-4 lg:grid-cols-12 lg:items-start">
          <div class="lg:col-span-9 self-start shadow outline-1 outline outline-n-container rounded-xl bg-n-solid-2 overflow-hidden">
            <div class="h-[52rem]">
              <ConversationView
                :inbox-id="0"
                :conversation-id="aiControlConversationId"
              />
            </div>
          </div>

          <div class="lg:col-span-3 flex flex-col gap-4">
            <div class="shadow outline-1 outline outline-n-container rounded-xl bg-n-solid-2 px-6 py-5">
              <div class="flex items-center justify-between gap-3">
                <div class="flex flex-col gap-1">
                  <div class="text-base font-medium text-n-slate-12">
                    Điều khiển nhanh
                  </div>
                  <div class="text-sm text-n-slate-11">
                    Dừng/Mở AI cho toàn bộ hội thoại đang mở
                  </div>
                </div>
              </div>

              <div class="mt-4 grid gap-3">
                <Button
                  :color="isAllPaused ? 'blue' : 'ruby'"
                  size="sm"
                  class="h-10"
                  :is-loading="isTakeoverAllLoading"
                  :label="isAllPaused ? 'Mở AI tất cả' : 'Dừng AI tất cả'"
                  @click="togglePauseAll"
                />

                <div class="text-xs text-n-slate-11">
                  Trạng thái: <span class="font-medium text-n-slate-12">{{ isAllPaused ? 'Đang dừng' : 'Đang chạy' }}</span>
                  · Áp dụng cho danh sách hội thoại đang mở.
                </div>
              </div>
            </div>

            <div class="shadow outline-1 outline outline-n-container rounded-xl bg-n-solid-2 px-6 py-5">
              <div class="flex items-center justify-between gap-3">
                <div class="flex flex-col gap-1">
                  <div class="text-base font-medium text-n-slate-12">
                    Tổng quan nhãn AI
                  </div>
                  <div class="text-sm text-n-slate-11">
                    Thống kê theo nhãn (label) để theo dõi hiệu suất và rủi ro
                  </div>
                </div>
              </div>

              <div class="grid gap-3 mt-4">
                <div
                  v-for="row in trackedLabelRows"
                  :key="row.name"
                  class="rounded-lg outline outline-1 outline-n-weak px-3 py-3"
                >
                  <div class="flex items-start justify-between gap-3">
                    <router-link
                      class="text-sm font-medium text-n-slate-12 hover:underline"
                      :to="labelRoute(row.name)"
                    >
                      {{ labelDisplayName(row.name) }}
                    </router-link>

                    <div class="text-sm text-n-slate-11">
                      {{ row.conversationsCount.toLocaleString() }}
                      <span class="text-xs">({{ labelPercent(row) }}%)</span>
                    </div>
                  </div>

                  <div class="mt-2 h-2 rounded-full bg-n-alpha-2 overflow-hidden">
                    <div
                      class="h-full rounded-full"
                      :class="
                        labelTone(row.name) === 'teal'
                          ? 'bg-n-teal-9'
                          : labelTone(row.name) === 'ruby'
                            ? 'bg-n-ruby-9'
                            : labelTone(row.name) === 'amber'
                              ? 'bg-n-amber-9'
                              : labelTone(row.name) === 'blue'
                                ? 'bg-n-blue-9'
                                : 'bg-n-slate-9'
                      "
                      :style="{ width: `${labelPercent(row)}%` }"
                    />
                  </div>

                  <div class="mt-2 text-xs text-n-slate-11">
                    <span class="font-medium text-n-slate-12">Nhãn:</span>
                    <span class="ml-1">#{{ row.name }}</span>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
