<script setup>
import { computed, onMounted, onBeforeUnmount, ref } from 'vue';
import { useRoute } from 'vue-router';

import ReportsAPI from 'dashboard/api/reports';
import SummaryReportsAPI from 'dashboard/api/summaryReports';
import ConversationLabelsAPI from 'dashboard/api/conversations';
import InboxConversationAPI from 'dashboard/api/inbox/conversation';

import ReportHeader from '../../settings/reports/components/ReportHeader.vue';
import ReportFilterSelector from '../../settings/reports/components/FilterSelector.vue';

import Button from 'dashboard/components-next/button/Button.vue';

import { useAlert } from 'dashboard/composables';
import { emitter } from 'shared/helpers/mitt';

const route = useRoute();

const from = ref(0);
const to = ref(0);

const activeKpiTab = ref('traffic');

const trafficConversationCount = ref(0);
const aiResolvedConversationCount = ref(0);
const aiHandoffConversationCount = ref(0);
const botMessageCount = ref('0');

const labelSummary = ref([]);

const liveConversations = ref([]);
const isLiveConversationsLoading = ref(false);

const PAUSE_LABEL = 'ai_paused';
const BOT_BLOCK_LABEL = 'khongtraloibangai';

const takeoverLoadingMap = ref({});
const isTakeoverAllLoading = ref(false);

const riskConversationIds = ref(new Set());
const isRiskBannerVisible = ref(false);
const isRiskBannerBlinking = ref(false);
const riskBannerText = ref('');
const riskAudio = ref(null);

const formatCount = value => {
  return Number(value || 0).toLocaleString();
};

const trafficConversationCountText = computed(() => {
  return formatCount(trafficConversationCount.value);
});

const aiAutomationText = computed(() => {
  const total = Number(trafficConversationCount.value || 0);
  const resolved = Number(aiResolvedConversationCount.value || 0);
  const rate = total ? Math.round((resolved / total) * 100) : 0;
  return `${formatCount(resolved)} (${rate}%)`;
});

const aiHandoffText = computed(() => {
  const total = Number(trafficConversationCount.value || 0);
  const handoff = Number(aiHandoffConversationCount.value || 0);
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
  const conversations = Number(trafficConversationCount.value || 0);
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
  return [
    'ai_handoff',
    'ai_lead',
    'ai_lead_high',
    'ai_lead_medium',
    'ai_lead_low',
    'ai_urgent',
    'ai_upset',
    'ai_paused',
    'khongtraloibangai',
    'intent_booking_confirmed',
  ];
});

const trackedLabelRows = computed(() => {
  const map = new Map(labelSummary.value.map(row => [row.name, row]));
  return trackedLabelNames.value.map(name => {
    return {
      name,
      conversationsCount: map.get(name)?.conversationsCount ?? 0,
    };
  });
});

const labelDisplayName = name => {
  const map = {
    intent_booking_confirmed: 'AI chốt lịch thành công',
    ai_handoff: 'Chuyển nhân viên',
    ai_upset: 'Khách bực / tiêu cực',
    ai_urgent: 'Ưu tiên gấp',
    ai_lead: 'Khách tiềm năng',
    ai_lead_high: 'Khách tiềm năng (tốt)',
    ai_lead_medium: 'Khách tiềm năng (trung bình)',
    ai_lead_low: 'Khách tiềm năng (kém)',
    ai_paused: 'Đang dừng AI',
    khongtraloibangai: 'Không trả lời bằng AI',
  };
  return map[name] || name;
};

const labelTone = name => {
  const map = {
    intent_booking_confirmed: 'teal',
    ai_handoff: 'ruby',
    ai_upset: 'ruby',
    ai_urgent: 'amber',
    ai_lead: 'blue',
    ai_lead_high: 'teal',
    ai_lead_medium: 'amber',
    ai_lead_low: 'ruby',
    ai_paused: 'slate',
    khongtraloibangai: 'slate',
  };
  return map[name] || 'slate';
};

const labelPercent = row => {
  const total = Number(trafficConversationCount.value || 0);
  const count = Number(row?.conversationsCount || 0);
  if (!total) return 0;
  return Math.min(100, Math.round((count / total) * 100));
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

const conversationRoute = conversationId => {
  return {
    name: 'inbox_conversation',
    params: {
      accountId: route.params.accountId,
      conversation_id: conversationId,
    },
  };
};

const isConversationInHumanMode = conversation => {
  const labels = Array.isArray(conversation?.labels) ? conversation.labels : [];
  return labels.includes(PAUSE_LABEL) || labels.includes(BOT_BLOCK_LABEL);
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

const conversationModeText = conversation => {
  return isConversationInHumanMode(conversation)
    ? 'Nhân viên'
    : 'AI';
};

const conversationModeClass = conversation => {
  return isConversationInHumanMode(conversation)
    ? 'bg-n-amber-3 text-n-slate-12 outline-n-amber-6'
    : 'bg-n-teal-3 text-n-teal-11 outline-n-teal-4';
};

const conversationPreview = conversation => {
  const message =
    conversation?.last_non_activity_message || conversation?.messages?.[0] || {};
  const rawText =
    message.processed_message_content ||
    message.content ||
    message?.content_attributes?.text ||
    '';

  return String(rawText || '').replace(/\s+/g, ' ').trim();
};

const conversationAIMetadataLabels = conversation => {
  const labels = Array.isArray(conversation?.labels) ? conversation.labels : [];
  return labels
    .filter(label => trackedLabelNames.value.includes(label))
    .filter(label => ![PAUSE_LABEL, BOT_BLOCK_LABEL].includes(label))
    .slice(0, 5);
};

const conversationHandoverReasonLabels = conversation => {
  const labels = Array.isArray(conversation?.labels) ? conversation.labels : [];
  return labels.filter(label => String(label || '').startsWith('handover_')).slice(0, 3);
};

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

const conversationAIMetadata = conversation => {
  const message =
    conversation?.last_non_activity_message || conversation?.messages?.[0] || {};
  const metadata = message?.content_attributes?.ai_metadata;
  return metadata && typeof metadata === 'object' ? metadata : null;
};

const sentimentVariant = conversation => {
  const labels = Array.isArray(conversation?.labels) ? conversation.labels : [];
  if (labels.includes('ai_upset')) return 'negative';

  const aiMetadata = conversationAIMetadata(conversation);
  const metaSentiment = String(aiMetadata?.sentiment_score || '').toLowerCase();
  if (metaSentiment === 'negative') return 'negative';
  if (metaSentiment === 'positive') return 'positive';
  if (metaSentiment === 'neutral') return 'neutral';

  const message =
    conversation?.last_non_activity_message || conversation?.messages?.[0] || {};
  const sentiment = message?.sentiment;

  if (!sentiment || typeof sentiment !== 'object') return 'unknown';
  if (Object.keys(sentiment).length === 0) return 'unknown';

  const label = String(
    sentiment.label || sentiment.sentiment || sentiment.polarity || ''
  ).toLowerCase();

  if (label.includes('neg')) return 'negative';
  if (label.includes('pos')) return 'positive';
  if (label.includes('neu')) return 'neutral';

  const score = sentiment.score ?? sentiment.compound ?? sentiment.polarity_score;
  if (typeof score === 'number') {
    if (score > 0.2) return 'positive';
    if (score < -0.2) return 'negative';
    return 'neutral';
  }

  return 'unknown';
};

const sentimentEmoji = conversation => {
  const map = {
    positive: '🙂',
    neutral: '😐',
    negative: '🙁',
    unknown: '—',
  };

  return map[sentimentVariant(conversation)] || map.unknown;
};

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

  trafficConversationCount.value = Number(data.conversations_count || 0);
};

const fetchBotSummary = async () => {
  if (!to.value || !from.value) return;

  const response = await ReportsAPI.getBotSummary({
    from: from.value,
    to: to.value,
    businessHours: false,
  });
  const data = response?.data || {};
  aiResolvedConversationCount.value = Number(data.bot_resolutions_count || 0);
  aiHandoffConversationCount.value = Number(data.bot_handoffs_count || 0);
};

const fetchBotMetrics = async () => {
  if (!to.value || !from.value) return;

  const response = await ReportsAPI.getBotMetrics({ from: from.value, to: to.value });
  const data = response?.data || {};

  botMessageCount.value = Number(data.message_count || 0).toLocaleString();
};

const fetchLabelSummary = async () => {
  if (!to.value || !from.value) return;

  const response = await SummaryReportsAPI.getLabelReports({
    since: from.value,
    until: to.value,
    businessHours: false,
  });
  labelSummary.value = normalizeLabelSummary(response?.data);

  const map = new Map(labelSummary.value.map(row => [row.name, row]));
  aiResolvedConversationCount.value = Number(
    map.get('intent_booking_confirmed')?.conversationsCount || 0
  );
  aiHandoffConversationCount.value = Number(
    map.get('ai_handoff')?.conversationsCount || 0
  );
};

const isRiskConversation = conversation => {
  const labels = Array.isArray(conversation?.labels) ? conversation.labels : [];
  return labels.includes('ai_urgent') || labels.includes('ai_upset') || labels.includes('ai_handoff');
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
      fetchBotSummary(),
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

  takeoverLoadingMap.value = { ...takeoverLoadingMap.value, [id]: true };
  try {
    const response = await ConversationLabelsAPI.getLabels(id);
    const currentLabels = response?.data?.payload || [];

    const next = new Set(Array.isArray(currentLabels) ? currentLabels : []);
    if (shouldPause) {
      next.add(PAUSE_LABEL);
      next.add(BOT_BLOCK_LABEL);
    } else {
      next.delete(PAUSE_LABEL);
      next.delete(BOT_BLOCK_LABEL);
    }

    await ConversationLabelsAPI.updateLabels(id, Array.from(next));

    liveConversations.value = (liveConversations.value || []).map(c => {
      if (String(c?.id) !== id) return c;
      return { ...c, labels: Array.from(next) };
    });
  } catch (e) {
    useAlert('Không thể cập nhật trạng thái dừng AI cho hội thoại này.');
  } finally {
    const nextMap = { ...takeoverLoadingMap.value };
    delete nextMap[id];
    takeoverLoadingMap.value = nextMap;
  }
};

const toggleConversationPause = async conversation => {
  const id = String(conversation?.id || '').trim();
  if (!id) return;
  const shouldPause = !isConversationPaused(conversation);
  await setConversationPause(id, shouldPause);
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

onMounted(() => {
  emitter.on('ai_control_panel:refresh_live_conversations', async () => {
    await fetchLiveConversations();
    if (to.value && from.value) {
      await Promise.all([fetchTrafficSummary(), fetchBotMetrics(), fetchLabelSummary()]);
    }
  });
  // Fetch happens after the first filter event
});

onBeforeUnmount(() => {
  emitter.off('ai_control_panel:refresh_live_conversations', fetchLiveConversations);
});
</script>

<template>
  <div class="overflow-auto bg-n-background w-full px-6">
    <div class="max-w-[80rem] mx-auto pb-12">
      <ReportHeader
        header-title="Bảng điều khiển AI"
        header-description="Theo dõi hiệu suất, rủi ro và vận hành AI theo thời gian thực"
      />

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

        <div class="grid gap-4 lg:grid-cols-12">
          <div class="lg:col-span-8 shadow outline-1 outline outline-n-container rounded-xl bg-n-solid-2 px-6 py-5">
            <div class="flex items-center justify-between gap-3">
              <div class="flex flex-col gap-1">
                <div class="text-base font-medium text-n-slate-12">
                  Hội thoại đang diễn ra
                </div>
                <div class="text-sm text-n-slate-11">
                  Danh sách hội thoại đang mở (AI / Nhân viên)
                </div>
              </div>

              <Button
                color="slate"
                size="sm"
                class="h-10"
                :is-loading="isLiveConversationsLoading"
                label="Làm mới"
                @click="fetchLiveConversations"
              />
            </div>

            <div
              v-if="isLiveConversationsLoading && !liveConversations.length"
              class="mt-4 text-sm text-n-slate-11"
            >
              Đang tải...
            </div>

            <div
              v-else-if="!liveConversations.length"
              class="mt-4 text-sm text-n-slate-11"
            >
              Chưa có hội thoại nào.
            </div>

            <div v-else class="mt-4 divide-y divide-n-weak">
              <div
                v-for="conversation in liveConversations"
                :key="conversation.id"
                class="flex items-start justify-between gap-4 py-3"
                :class="
                  isRiskConversation(conversation)
                    ? 'border-l-4 border-l-n-ruby-9 pl-3'
                    : 'border-l-4 border-l-transparent pl-3'
                "
              >
                <div class="min-w-0 flex-1">
                  <router-link
                    class="text-sm font-medium text-n-slate-12 hover:underline"
                    :to="conversationRoute(conversation.id)"
                  >
                    #{{ conversation.id }}
                    <span v-if="conversation?.meta?.sender?.name">
                      · {{ conversation.meta.sender.name }}
                    </span>
                  </router-link>

                  <div class="text-xs text-n-slate-11 truncate mt-0.5">
                    {{ conversationPreview(conversation) || '--' }}
                  </div>

                  <div
                    v-if="conversationHandoverReasonLabels(conversation).length"
                    class="text-xs text-n-slate-11 truncate mt-1"
                  >
                    <span class="font-medium text-n-slate-12">Lý do:</span>
                    <span>
                      {{ conversationHandoverReasonLabels(conversation).map(handoverReasonDisplay).join(', ') }}
                    </span>
                  </div>

                  <div
                    v-if="conversationAIMetadataLabels(conversation).length"
                    class="flex flex-wrap gap-2 mt-2"
                  >
                    <span
                      v-for="label in conversationAIMetadataLabels(conversation)"
                      :key="label"
                      class="text-xs rounded-md outline outline-1 outline-n-weak px-2 py-1 text-n-slate-12"
                    >
                      #{{ label }}
                    </span>
                  </div>
                </div>

                <div class="flex flex-col items-end gap-2 shrink-0">
                  <div class="flex items-center gap-2">
                    <span class="text-base leading-none">
                      {{ sentimentEmoji(conversation) }}
                    </span>
                    <span
                      class="text-xs rounded-full outline outline-1 px-3 py-1 font-medium"
                      :class="conversationModeClass(conversation)"
                    >
                      {{ conversationModeText(conversation) }}
                    </span>
                  </div>

                  <Button
                    :color="isConversationPaused(conversation) ? 'blue' : 'slate'"
                    size="sm"
                    class="h-9"
                    :is-loading="Boolean(takeoverLoadingMap[String(conversation.id)])"
                    :label="isConversationPaused(conversation) ? 'Mở AI' : 'Dừng AI'"
                    @click="toggleConversationPause(conversation)"
                  />
                </div>
              </div>
            </div>
          </div>

          <div class="lg:col-span-4 flex flex-col gap-4">
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
