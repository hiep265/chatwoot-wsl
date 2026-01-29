<script setup>
import { computed, onMounted, onBeforeUnmount, ref } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';

import ReportsAPI from 'dashboard/api/reports';
import SummaryReportsAPI from 'dashboard/api/summaryReports';
import ConversationLabelsAPI from 'dashboard/api/conversations';
import InboxConversationAPI from 'dashboard/api/inbox/conversation';

import ReportHeader from '../../settings/reports/components/ReportHeader.vue';
import ReportFilterSelector from '../../settings/reports/components/FilterSelector.vue';
import ReportMetricCard from '../../settings/reports/components/ReportMetricCard.vue';

import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';

import { useAlert } from 'dashboard/composables';
import { emitter } from 'shared/helpers/mitt';

const route = useRoute();
const { t } = useI18n();

const from = ref(0);
const to = ref(0);

const trafficConversationCount = ref(0);
const aiResolvedConversationCount = ref(0);
const aiHandoffConversationCount = ref(0);
const botMessageCount = ref('0');

const labelSummary = ref([]);

const liveConversations = ref([]);
const isLiveConversationsLoading = ref(false);

const conversationDisplayId = ref('');
const conversationLabels = ref([]);
const isLabelsLoading = ref(false);

const PAUSE_LABEL = 'ai_paused';
const BOT_BLOCK_LABEL = 'khongtraloibangai';

const riskConversationIds = ref(new Set());
const isRiskBannerVisible = ref(false);
const isRiskBannerBlinking = ref(false);
const riskBannerText = ref('');
const riskAudio = ref(null);

const isPaused = computed(() => {
  return Array.isArray(conversationLabels.value)
    ? conversationLabels.value.includes(PAUSE_LABEL) ||
        conversationLabels.value.includes(BOT_BLOCK_LABEL)
    : false;
});

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

const conversationModeText = conversation => {
  return isConversationInHumanMode(conversation)
    ? t('AI_CONTROL_PANEL.CONVERSATIONS.MODE_HUMAN')
    : t('AI_CONTROL_PANEL.CONVERSATIONS.MODE_AI');
};

const conversationModeClass = conversation => {
  return isConversationInHumanMode(conversation)
    ? 'bg-n-slate-3 text-n-slate-11 outline-n-slate-4'
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
    useAlert('Risk alert sound blocked by browser permissions');
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

  riskBannerText.value = `High risk conversations: ${nextIds.size}`;
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
    useAlert(t('REPORT.DATA_FETCHING_FAILED'));
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
    useAlert(t('REPORT.DATA_FETCHING_FAILED'));
  }
};

const onFilterChange = async ({ from: nextFrom, to: nextTo }) => {
  from.value = nextFrom;
  to.value = nextTo;
  await fetchAll();
};

const refreshConversationLabels = async () => {
  const id = String(conversationDisplayId.value || '').trim();
  if (!id) {
    conversationLabels.value = [];
    return;
  }

  isLabelsLoading.value = true;
  try {
    const response = await ConversationLabelsAPI.getLabels(id);
    conversationLabels.value = response?.data?.payload || [];
  } catch (e) {
    useAlert(t('CONVERSATION.CHANGE_STATUS_FAILED'));
  } finally {
    isLabelsLoading.value = false;
  }
};

const setPause = async shouldPause => {
  const id = String(conversationDisplayId.value || '').trim();
  if (!id) {
    useAlert(t('AI_CONTROL_PANEL.TAKEOVER.MISSING_CONVERSATION_ID'));
    return;
  }

  isLabelsLoading.value = true;
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
    await refreshConversationLabels();
  } catch (e) {
    useAlert(t('CONVERSATION.CHANGE_STATUS_FAILED'));
  } finally {
    isLabelsLoading.value = false;
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
  <div class="px-6">
    <ReportHeader
      :header-title="t('AI_CONTROL_PANEL.HEADER')"
      :header-description="t('AI_CONTROL_PANEL.DESCRIPTION')"
    />

    <div class="flex flex-col gap-4 pb-6">
      <div
        v-if="isRiskBannerVisible"
        class="rounded-xl outline outline-1 px-4 py-3"
        :class="
          isRiskBannerBlinking
            ? 'bg-n-ruby-3 text-n-ruby-12 outline-n-ruby-4 animate-pulse'
            : 'bg-n-ruby-3 text-n-ruby-12 outline-n-ruby-4'
        "
      >
        <div class="text-sm font-medium">
          {{ riskBannerText }}
        </div>
      </div>

      <ReportFilterSelector
        :show-agents-filter="false"
        :show-group-by-filter="false"
        :show-business-hours-switch="false"
        @filterChange="onFilterChange"
        @filter-change="onFilterChange"
      />

      <div
        class="flex flex-wrap mx-0 shadow outline-1 outline outline-n-container rounded-xl bg-n-solid-2 px-6 py-5"
      >
        <ReportMetricCard
          :label="t('AI_CONTROL_PANEL.METRICS.TRAFFIC')"
          :info-text="t('AI_CONTROL_PANEL.METRICS.TRAFFIC_HELP')"
          :value="trafficConversationCountText"
          class="flex-1"
        />
        <ReportMetricCard
          :label="t('AI_CONTROL_PANEL.METRICS.AI_AUTOMATION')"
          :info-text="t('AI_CONTROL_PANEL.METRICS.AI_AUTOMATION_HELP')"
          :value="aiAutomationText"
          class="flex-1"
        />
        <ReportMetricCard
          :label="t('AI_CONTROL_PANEL.METRICS.AI_HANDOFF')"
          :info-text="t('AI_CONTROL_PANEL.METRICS.AI_HANDOFF_HELP')"
          :value="aiHandoffText"
          class="flex-1"
        />
        <ReportMetricCard
          :label="t('AI_CONTROL_PANEL.METRICS.TOTAL_MESSAGES')"
          :info-text="t('AI_CONTROL_PANEL.METRICS.TOTAL_MESSAGES_HELP')"
          :value="botMessageCount"
          class="flex-1"
        />
      </div>

      <div
        class="shadow outline-1 outline outline-n-container rounded-xl bg-n-solid-2 px-6 py-5"
      >
        <div class="flex items-center justify-between gap-3">
          <div class="flex flex-col gap-1">
            <div class="text-base font-medium text-n-slate-12">
              {{ t('AI_CONTROL_PANEL.CONVERSATIONS.HEADER') }}
            </div>
            <div class="text-sm text-n-slate-11">
              {{ t('AI_CONTROL_PANEL.CONVERSATIONS.DESCRIPTION') }}
            </div>
          </div>

          <Button
            color="slate"
            size="sm"
            class="h-10"
            :is-loading="isLiveConversationsLoading"
            :label="t('AI_CONTROL_PANEL.CONVERSATIONS.REFRESH')"
            @click="fetchLiveConversations"
          />
        </div>

        <div
          v-if="isLiveConversationsLoading && !liveConversations.length"
          class="mt-4 text-sm text-n-slate-11"
        >
          {{ t('AI_CONTROL_PANEL.CONVERSATIONS.LOADING') }}
        </div>

        <div
          v-else-if="!liveConversations.length"
          class="mt-4 text-sm text-n-slate-11"
        >
          {{ t('AI_CONTROL_PANEL.CONVERSATIONS.EMPTY') }}
        </div>

        <div v-else class="mt-4 divide-y divide-n-weak">
          <div
            v-for="conversation in liveConversations"
            :key="conversation.id"
            class="flex items-start justify-between gap-4 py-3"
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
                <span class="font-medium text-n-slate-12">Reason:</span>
                <span>
                  {{ conversationHandoverReasonLabels(conversation).join(', ') }}
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
                  class="text-xs rounded-md outline outline-1 px-2 py-1"
                  :class="conversationModeClass(conversation)"
                >
                  {{ conversationModeText(conversation) }}
                </span>
              </div>
            </div>
          </div>
        </div>
      </div>

      <div
        class="shadow outline-1 outline outline-n-container rounded-xl bg-n-solid-2 px-6 py-5"
      >
        <div class="flex items-center justify-between gap-3">
          <div class="flex flex-col gap-1">
            <div class="text-base font-medium text-n-slate-12">
              {{ t('AI_CONTROL_PANEL.LABELS.HEADER') }}
            </div>
            <div class="text-sm text-n-slate-11">
              {{ t('AI_CONTROL_PANEL.LABELS.DESCRIPTION') }}
            </div>
          </div>
        </div>

        <div class="grid gap-2 mt-4">
          <div
            v-for="row in trackedLabelRows"
            :key="row.name"
            class="flex items-center justify-between rounded-lg outline outline-1 outline-n-weak px-3 py-2"
          >
            <router-link
              class="text-sm font-medium text-n-slate-12 hover:underline"
              :to="labelRoute(row.name)"
            >
              #{{ row.name }}
            </router-link>
            <div class="text-sm text-n-slate-11">
              {{ row.conversationsCount.toLocaleString() }}
            </div>
          </div>
        </div>
      </div>

      <div
        class="shadow outline-1 outline outline-n-container rounded-xl bg-n-solid-2 px-6 py-5"
      >
        <div class="flex items-center justify-between gap-3">
          <div class="flex flex-col gap-1">
            <div class="text-base font-medium text-n-slate-12">
              {{ t('AI_CONTROL_PANEL.TAKEOVER.HEADER') }}
            </div>
            <div class="text-sm text-n-slate-11">
              {{ t('AI_CONTROL_PANEL.TAKEOVER.DESCRIPTION') }}
            </div>
          </div>
        </div>

        <div class="grid gap-3 mt-4 md:grid-cols-[1fr_auto_auto] items-end">
          <Input
            v-model="conversationDisplayId"
            :label="t('AI_CONTROL_PANEL.TAKEOVER.CONVERSATION_ID_LABEL')"
            :placeholder="t('AI_CONTROL_PANEL.TAKEOVER.CONVERSATION_ID_PLACEHOLDER')"
            @enter="refreshConversationLabels"
          />

          <Button
            color="slate"
            size="sm"
            class="h-10"
            :is-loading="isLabelsLoading"
            :label="t('AI_CONTROL_PANEL.TAKEOVER.CHECK_STATUS')"
            @click="refreshConversationLabels"
          />

          <Button
            :color="isPaused ? 'slate' : 'blue'"
            size="sm"
            class="h-10"
            :is-loading="isLabelsLoading"
            :label="isPaused ? t('AI_CONTROL_PANEL.TAKEOVER.RESUME') : t('AI_CONTROL_PANEL.TAKEOVER.PAUSE')"
            @click="setPause(!isPaused)"
          />
        </div>

        <div class="mt-4 text-sm text-n-slate-11">
          <span class="font-medium text-n-slate-12">{{ t('AI_CONTROL_PANEL.TAKEOVER.CURRENT_STATE') }}:</span>
          <span v-if="conversationDisplayId && isPaused">{{ t('AI_CONTROL_PANEL.TAKEOVER.STATE_PAUSED') }}</span>
          <span v-else-if="conversationDisplayId && !isPaused">{{ t('AI_CONTROL_PANEL.TAKEOVER.STATE_ACTIVE') }}</span>
          <span v-else>--</span>
        </div>

        <div v-if="conversationDisplayId" class="mt-2">
          <router-link
            class="text-sm text-n-blue-text hover:underline"
            :to="conversationRoute(conversationDisplayId)"
          >
            {{ t('AI_CONTROL_PANEL.TAKEOVER.OPEN_CONVERSATION') }}
          </router-link>
        </div>

        <div v-if="conversationLabels.length" class="flex flex-wrap gap-2 mt-3">
          <span
            v-for="label in conversationLabels"
            :key="label"
            class="text-xs rounded-md outline outline-1 outline-n-weak px-2 py-1 text-n-slate-12"
          >
            #{{ label }}
          </span>
        </div>
      </div>
    </div>
  </div>
</template>
