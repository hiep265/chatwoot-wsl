<script setup>
import { computed, onMounted, onBeforeUnmount, ref, watch, nextTick } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useStore } from 'vuex';

import ReportsAPI from 'dashboard/api/reports';
import SummaryReportsAPI from 'dashboard/api/summaryReports';
import InboxConversationAPI from 'dashboard/api/inbox/conversation';
import AiControlAPI from 'dashboard/api/aiControl';

import ReportHeader from '../../settings/reports/components/ReportHeader.vue';
import ReportFilterSelector from '../../settings/reports/components/FilterSelector.vue';
import ConversationView from '../../conversation/ConversationView.vue';

import Button from 'dashboard/components-next/button/Button.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';

import AddLabel from '../../settings/labels/AddLabel.vue';
import CommentThread from './CommentThread.vue';
import AftercareEnrollmentDialog from './AftercareEnrollmentDialog.vue';

import { useAlert } from 'dashboard/composables';
import { emitter } from 'shared/helpers/mitt';

const REALTIME_OPERATIONS_REFRESH_DELAY = 300;
const MANAGER_QUEUE_LOG_PREFIX = '[AiControlQueue]';
const REALTIME_REFRESH_LOG_PREFIX = '[AiControlRealtime]';

const props = defineProps({
  standalone: {
    type: Boolean,
    default: false,
  },
});

const route = useRoute();
const router = useRouter();
const store = useStore();

const from = ref(0);
const to = ref(0);
const localAiControlConversationId = ref(0);

const activeMainTab = ref('operations');
const reportingDashboardUrl = ref('https://app.powerbi.com/view?r=custom_id_from_user');

const activeKpiTab = ref('traffic');
const mountedMainTabs = ref({
  operations: activeMainTab.value === 'operations',
  reporting: activeMainTab.value === 'reporting',
  comment: activeMainTab.value === 'comment',
  aftercare: activeMainTab.value === 'aftercare',
});
const panelScrollContainer = ref(null);
const mainTabScrollOffsets = ref({
  operations: 0,
  reporting: 0,
  comment: 0,
  aftercare: 0,
});

const trafficConversationCount = ref(0);
const botConversationCount = ref(0);
const botMessageCount = ref('0');

const labelSummary = ref([]);

const liveConversations = ref([]);
const isLiveConversationsLoading = ref(false);
const paymentReviewCases = ref([]);
const paymentReviewTotal = ref(0);
const paymentReviewCount = ref(0);
const isPaymentReviewLoading = ref(false);
const paymentReviewSegment = ref('all');
const paymentReviewLimit = ref(20);
const paymentReviewOffset = ref(0);
const paymentReviewHasMore = ref(true);
const paymentReviewLastError = ref('');
const paymentReviewActionLoading = ref(new Set());
const isPaymentReviewLoadingMore = ref(false);

const paymentReviewTableContainer = ref(null);
const conversationSectionRef = ref(null);
const managerAiHandoffQueue = ref([]);
const isManagerQueuesLoading = ref(false);
const managerQueuesError = ref('');
const customer360 = ref(null);
const isCustomer360Loading = ref(false);
const customer360Error = ref('');
const aftercareSequences = ref([]);
const aftercareEnrollments = ref([]);
const aftercareEligibility = ref(null);
const aftercareLastError = ref('');
const isAftercareLoading = ref(false);
const isAftercareDialogLoading = ref(false);
const isAftercareSubmitting = ref(false);
const showAftercareDialog = ref(false);
const aftercareEditingDraftStepIds = ref(new Set());
const aftercareSavingDraftStepIds = ref(new Set());
const aftercareDraftEdits = ref({});
const aftercareRefreshingStepIds = ref(new Set());
const aftercareRetryingStepIds = ref(new Set());
const aftercareCancellingEnrollmentIds = ref(new Set());
const aftercareTransitioningEnrollmentIds = ref(new Set());

// Sorted payment cases: pending (chờ xác nhận) first
const sortedPaymentReviewCases = computed(() => {
  const cases = Array.isArray(paymentReviewCases.value) ? paymentReviewCases.value : [];
  return [...cases].sort((a, b) => {
    const statusA = String(a?.review_status || '').toLowerCase();
    const statusB = String(b?.review_status || '').toLowerCase();
    const isPendingA = !statusA.includes('verified') && !statusA.includes('rejected');
    const isPendingB = !statusB.includes('verified') && !statusB.includes('rejected');
    if (isPendingA && !isPendingB) return -1;
    if (!isPendingA && isPendingB) return 1;
    return 0;
  });
});

const showMetadataModal = ref(false);
const selectedMetadataItem = ref(null);

const openMetadataModal = (item) => {
  selectedMetadataItem.value = item;
  showMetadataModal.value = true;
};

const closeMetadataModal = () => {
  showMetadataModal.value = false;
  selectedMetadataItem.value = null;
};

// Queue "Đang chờ nhân viên phản hồi" bám theo label handoff từ Chatwoot
const HANDOFF_LABEL = 'ai_handoff';
const BOOKING_CONFIRMED_LABEL = 'ý_định_đặt_lịch_xác_nhận';
const LABEL_ALIASES = {
  handoff: HANDOFF_LABEL,
  fai_handoff: HANDOFF_LABEL,
  intent_booking_confirmed: BOOKING_CONFIRMED_LABEL,
  ai_upset: 'cảm_xúc_tiêu_cực',
  ai_urgent: 'ưu_tiên_gấp',
  ai_lead: 'khách_tiềm_năng',
  ai_lead_high: 'khách_tiềm_năng_cao',
  ai_lead_medium: 'khách_tiềm_năng_trung_bình',
  ai_lead_low: 'khách_tiềm_năng_thấp',
  payment_collection: 'thu_thập_thanh_toán',
  handover_sales_opportunity: 'lý_do_handoff_cơ_hội_chốt_đơn',
  handover_negative_sentiment: 'lý_do_handoff_khách_tiêu_cực',
  // Legacy ASCII -> diacritics
  khach_moi: 'khách_mới',
  khach_quay_lai: 'khách_quay_lại',
  can_theo_doi: 'cần_theo_dõi',
  off_topic: 'ngoài_chủ_đề',
  y_dinh_dat_lich_xac_nhan: 'ý_định_đặt_lịch_xác_nhận',
  payment_review_pending: 'chờ_xét_thanh_toán',
  cam_xuc_tieu_cuc: 'cảm_xúc_tiêu_cực',
  uu_tien_gap: 'ưu_tiên_gấp',
};

const normalizeLabelKey = label => {
  const key = String(label || '')
    .toLowerCase()
    .trim();
  const directAlias = LABEL_ALIASES[key];
  if (directAlias) return directAlias;

  if (key.startsWith('intent_')) return `y_dinh_${key.replace(/^intent_/, '')}`;
  if (key.startsWith('handover_'))
    return `ly_do_handoff_${key.replace(/^handover_/, '')}`;

  return key;
};

const isTakeoverAllLoading = ref(false);
const blockedInboxIds = ref(new Set());
const isBlockedInboxesLoading = ref(false);
const faqTrainingDays = ref(7);
const isFaqTrainingLoading = ref(false);
const faqTrainingReport = ref(null);

const riskConversationIds = ref(new Set());
const isRiskBannerVisible = ref(false);
const isRiskBannerBlinking = ref(false);
const riskBannerText = ref('');
const riskAudio = ref(null);
const showReportLabelPopup = ref(false);
const selectedReportLabel = ref('');
const reportLabelPreviewItems = ref([]);
const isReportLabelPreviewLoading = ref(false);
const reportLabelPreviewError = ref('');

const aiControlConversationId = computed(
  () =>
    String(localAiControlConversationId.value || '').trim() ||
    route.params.conversation_id ||
    0
);
const adminPanelRoute = computed(() => {
  return {
    name: 'ai_control_panel',
    params: { accountId: route.params.accountId },
  };
});

const hasMountedMainTab = tab => {
  const normalizedTab = String(tab || '').trim();
  return Boolean(normalizedTab && mountedMainTabs.value[normalizedTab]);
};

const markMainTabAsMounted = tab => {
  const normalizedTab = String(tab || '').trim();
  if (!normalizedTab || mountedMainTabs.value[normalizedTab]) return;

  mountedMainTabs.value = {
    ...mountedMainTabs.value,
    [normalizedTab]: true,
  };
};

const saveMainTabScrollPosition = (tab = activeMainTab.value) => {
  const normalizedTab = String(tab || '').trim();
  const container = panelScrollContainer.value;
  if (!normalizedTab || !container) return;

  mainTabScrollOffsets.value = {
    ...mainTabScrollOffsets.value,
    [normalizedTab]: container.scrollTop,
  };
};

const restoreMainTabScrollPosition = tab => {
  const normalizedTab = String(tab || '').trim();
  const container = panelScrollContainer.value;
  if (!normalizedTab || !container) return;

  container.scrollTop = Number(mainTabScrollOffsets.value[normalizedTab] || 0);
};

const hasSelectedConversation = computed(() => {
  const id = String(aiControlConversationId.value || '').trim();
  return Boolean(id && id !== '0');
});

const selectedAftercareConversationLabel = computed(() => {
  if (!hasSelectedConversation.value) return '';

  const name =
    customer360.value?.contact_profile?.name ||
    customer360.value?.contact_id ||
    'Khách hàng';
  const displayId =
    customer360.value?.conversation?.display_id || aiControlConversationId.value;
  return `${name} · #${displayId}`;
});

const selectedAftercareContactEmail = computed(() => {
  if (!hasSelectedConversation.value) return '';

  return String(customer360.value?.contact_profile?.email || '').trim();
});

// Label management state
const showAddLabelPopup = ref(false);
const showDeleteLabelPopup = ref(false);
const selectedLabelToDelete = ref(null);
const isDeletingLabel = ref(false);

let managerQueuesRequestSequence = 0;
let realtimeOperationsRefreshTimer = null;

const formatCount = value => {
  return Number(value || 0).toLocaleString();
};

const labelTestId = name => {
  return normalizeLabelKey(name)
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '');
};

const labelOverviewTotal = computed(() => {
  const trafficTotal = Number(trafficConversationCount.value || 0);
  const botTotal = Number(botConversationCount.value || 0);
  const rows = Array.isArray(labelSummary.value) ? labelSummary.value : [];
  const labelTotal = rows.reduce((total, row) => {
    return (
      total + Number(row?.conversationsCount || row?.conversations_count || 0)
    );
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
  const normalized = normalizeLabelKey(labelName);
  const row = trackedLabelRows.value.find(item => item.name === normalized);
  return Number(row?.conversationsCount || 0);
};

const newClientsCount = computed(() => {
  return trackedLabelCount('khách_mới');
});

const returnClientsCount = computed(() => {
  return trackedLabelCount('khách_quay_lại');
});

const closeCount = computed(() => {
  return trackedLabelCount('ý_định_đặt_lịch_xác_nhận');
});

const closeRateText = computed(() => {
  const total = Number(labelOverviewTotal.value || 0);
  if (!total) return '0%';
  const closed = closeCount.value;
  return Math.round((closed / total) * 100) + '%';
});

const followUpCount = computed(() => {
  return trackedLabelCount('cần_theo_dõi');
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
  const messages = Number(
    String(botMessageCount.value || '0').replace(/,/g, '') || 0
  );
  if (!conversations) return 0;
  return Math.round((messages / conversations) * 10) / 10;
});

const AI_GROWTH_RANGE_OPTIONS = [
  { key: '1m', label: '1T', days: 30 },
  { key: '3m', label: '3T', days: 90 },
  { key: '6m', label: '6T', days: 180 },
  { key: '1y', label: '1N', days: 365 },
];

const TREND_METRIC_OPTIONS = [
  { key: 'revenue', label: 'Doanh thu' },
  { key: 'new_clients', label: 'Khách mới' },
  { key: 'close_rate', label: 'Tỉ lệ chốt' },
  { key: 'return_clients', label: 'Khách quay lại' },
];

const aiGrowthRange = ref('3m');
const activeTrendMetric = ref('revenue');
const aiGrowthSeries = ref([]);
const isAiGrowthLoading = ref(false);
const aiGrowthError = ref('');

const aiGrowthRangeLabel = computed(() => {
  const option = AI_GROWTH_RANGE_OPTIONS.find(
    item => item.key === aiGrowthRange.value
  );
  return option?.label || '3T';
});

const activeTrendMetricLabel = computed(() => {
  const option = TREND_METRIC_OPTIONS.find(
    item => item.key === activeTrendMetric.value
  );
  return option?.label || 'Doanh thu';
});

const aiGrowthTotal = computed(() => {
  if (activeTrendMetric.value === 'close_rate') {
    return Number(aiGrowthSeries.value.at(-1)?.value || 0);
  }
  return (aiGrowthSeries.value || []).reduce((sum, point) => {
    return sum + Number(point?.value || 0);
  }, 0);
});

const aiGrowthLatestValue = computed(() => {
  return Number(aiGrowthSeries.value.at(-1)?.value || 0);
});

const aiGrowthPreviousValue = computed(() => {
  if ((aiGrowthSeries.value || []).length < 2) return 0;
  return Number(aiGrowthSeries.value.at(-2)?.value || 0);
});

const aiGrowthDeltaPercent = computed(() => {
  const latest = aiGrowthLatestValue.value;
  const previous = aiGrowthPreviousValue.value;
  if (!previous) return latest > 0 ? 100 : 0;
  return Math.round(((latest - previous) / previous) * 100);
});

const aiGrowthDeltaTone = computed(() => {
  if (aiGrowthDeltaPercent.value > 0) return 'text-n-teal-11';
  if (aiGrowthDeltaPercent.value < 0) return 'text-n-ruby-11';
  return 'text-n-slate-11';
});

const aiGrowthDeltaText = computed(() => {
  const delta = aiGrowthDeltaPercent.value;
  if (!delta) return 'Không đổi so với mốc trước';
  const prefix = delta > 0 ? '+' : '';
  return `${prefix}${delta}% so với mốc trước`;
});

const aiGrowthRangeClass = key => {
  return aiGrowthRange.value === key
    ? 'bg-n-blue-9 text-white shadow-sm'
    : 'bg-n-slate-2 text-n-slate-11 hover:bg-n-slate-3';
};

const trendMetricClass = key => {
  return activeTrendMetric.value === key
    ? 'bg-n-slate-12 text-white shadow-sm'
    : 'bg-n-slate-2 text-n-slate-11 hover:bg-n-slate-3';
};

const startOfUtcDayTimestamp = date => {
  return Math.floor(
    Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()) /
      1000
  );
};

const getAiGrowthWindow = rangeKey => {
  const option =
    AI_GROWTH_RANGE_OPTIONS.find(item => item.key === rangeKey) ||
    AI_GROWTH_RANGE_OPTIONS[1];
  const endDate = new Date();
  const until = startOfUtcDayTimestamp(endDate);
  const since = until - option.days * 24 * 60 * 60;
  return { since, until };
};

const formatBucketLabel = (timestamp, bucketType) => {
  const date = new Date(Number(timestamp || 0) * 1000);
  if (Number.isNaN(date.getTime())) return '';

  if (bucketType === 'week') {
    return date.toLocaleDateString('vi-VN', {
      day: '2-digit',
      month: '2-digit',
    });
  }

  if (bucketType === 'month') {
    return date.toLocaleDateString('vi-VN', {
      month: '2-digit',
      year: '2-digit',
    });
  }

  return date.toLocaleDateString('vi-VN', {
    day: '2-digit',
    month: '2-digit',
  });
};

const buildTrendBuckets = rangeKey => {
  const { since, until } = getAiGrowthWindow(rangeKey);

  if (rangeKey === '1m') {
    const totalDays = Math.max(0, Math.floor((until - since) / 86400));
    return Array.from({ length: totalDays + 1 }, (_, index) => {
      const timestamp = since + index * 86400;
      return {
        bucketType: 'day',
        since: timestamp,
        until: timestamp,
        timestamp,
        label: formatBucketLabel(timestamp, 'day'),
      };
    });
  }

  if (rangeKey === '3m') {
    const totalWeeks = Math.max(0, Math.ceil((until - since + 86400) / 604800));
    return Array.from({ length: totalWeeks }, (_, index) => {
      const bucketSince = since + index * 604800;
      const bucketUntil = Math.min(until, bucketSince + 6 * 86400);
      return {
        bucketType: 'week',
        since: bucketSince,
        until: bucketUntil,
        timestamp: bucketSince,
        label: formatBucketLabel(bucketSince, 'week'),
      };
    });
  }

  const monthCount = rangeKey === '6m' ? 6 : 12;
  const today = new Date();
  return Array.from({ length: monthCount }, (_, index) => {
    const monthDate = new Date(
      Date.UTC(today.getUTCFullYear(), today.getUTCMonth() - (monthCount - 1 - index), 1)
    );
    const bucketSince = startOfUtcDayTimestamp(monthDate);
    const nextMonthDate = new Date(
      Date.UTC(monthDate.getUTCFullYear(), monthDate.getUTCMonth() + 1, 1)
    );
    const bucketUntil = Math.min(
      until,
      startOfUtcDayTimestamp(nextMonthDate) - 86400
    );
    return {
      bucketType: 'month',
      since: bucketSince,
      until: Math.max(bucketSince, bucketUntil),
      timestamp: bucketSince,
      label: formatBucketLabel(bucketSince, 'month'),
    };
  }).filter(bucket => bucket.since <= until);
};

const buildBucketSeries = (buckets, valueGetter) => {
  return buckets.map(bucket => ({
    timestamp: bucket.timestamp,
    label: bucket.label,
    value: Number(valueGetter(bucket) || 0),
  }));
};

const findCountInLabelSummary = (rows, labelName) => {
  const normalized = normalizeLabelKey(labelName);
  const row = (Array.isArray(rows) ? rows : []).find(item => {
    return normalizeLabelKey(item?.name) === normalized;
  });
  return Number(row?.conversations_count || row?.conversationsCount || 0);
};

const formatTrendValueText = value => {
  const numericValue = Number(value || 0);
  if (activeTrendMetric.value === 'revenue') {
    return `${numericValue.toLocaleString('vi-VN')} USD`;
  }
  if (activeTrendMetric.value === 'close_rate') {
    return `${numericValue}%`;
  }
  return formatCount(numericValue);
};

const trendSummaryText = computed(() => {
  if (activeTrendMetric.value === 'close_rate') {
    return `Tỉ lệ chốt gần nhất trong ${aiGrowthRangeLabel.value}`;
  }
  return `Tổng ${activeTrendMetricLabel.value.toLowerCase()} trong ${aiGrowthRangeLabel.value}`;
});

const trendDeltaText = computed(() => {
  if (activeTrendMetric.value === 'close_rate') {
    return aiGrowthDeltaText.value.replace('%', ' điểm %');
  }
  return aiGrowthDeltaText.value;
});

const formatAiGrowthAxisLabel = timestamp => {
  const date = new Date(Number(timestamp || 0) * 1000);
  if (Number.isNaN(date.getTime())) return '';
  const isLongRange =
    aiGrowthRange.value === '6m' || aiGrowthRange.value === '1y';
  return date.toLocaleDateString('vi-VN', {
    day: isLongRange ? undefined : '2-digit',
    month: '2-digit',
    year: isLongRange ? '2-digit' : undefined,
  });
};

const formatAiGrowthTooltipLabel = timestamp => {
  const date = new Date(Number(timestamp || 0) * 1000);
  if (Number.isNaN(date.getTime())) return '';
  return date.toLocaleDateString('vi-VN', {
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
  });
};

const fetchAllPaymentReviewCasesForTrend = async () => {
  const limit = 100;
  let offset = 0;
  let hasMore = true;
  let rows = [];

  while (hasMore && offset <= 1000) {
    const response = await AiControlAPI.listPaymentReviewCases({
      reviewStatus: 'payment_review_pending',
      limit,
      offset,
    });
    const data = response?.data || {};
    const pageRows = Array.isArray(data?.cases) ? data.cases : [];
    rows = rows.concat(pageRows);
    hasMore = pageRows.length === limit;
    offset += limit;
  }

  return rows;
};

const buildRevenueBucketSeries = (rows, rangeKey) => {
  const buckets = buildTrendBuckets(rangeKey);
  return buildBucketSeries(buckets, bucket => {
    return (Array.isArray(rows) ? rows : []).reduce((sum, row) => {
      const createdAt = String(row?.created_at || '').trim();
      if (!createdAt) return sum;
      const date = new Date(createdAt);
      const timestamp = startOfUtcDayTimestamp(date);
      if (Number.isNaN(date.getTime())) return sum;
      if (timestamp < bucket.since || timestamp > bucket.until) return sum;
      const amount = parseFloat(
        row?.expected_amount_total || row?.expected_amount || 0
      );
      if (Number.isNaN(amount)) return sum;
      return sum + amount;
    }, 0);
  });
};

const fetchLabelBucketSeries = async (labelName, rangeKey) => {
  const buckets = buildTrendBuckets(rangeKey);
  const responses = await Promise.all(
    buckets.map(bucket =>
      SummaryReportsAPI.getLabelReports({
        since: bucket.since,
        until: bucket.until,
        businessHours: false,
      })
    )
  );

  return buildBucketSeries(buckets, bucket => {
    const index = buckets.findIndex(item => item.timestamp === bucket.timestamp);
    return findCountInLabelSummary(
      responses[index]?.data || [],
      labelName
    );
  });
};

const fetchCloseRateBucketSeries = async rangeKey => {
  const buckets = buildTrendBuckets(rangeKey);
  const [labelResponses, summaryResponses] = await Promise.all([
    Promise.all(
      buckets.map(bucket =>
        SummaryReportsAPI.getLabelReports({
          since: bucket.since,
          until: bucket.until,
          businessHours: false,
        })
      )
    ),
    Promise.all(
      buckets.map(bucket =>
        ReportsAPI.getSummary(
          bucket.since,
          bucket.until,
          'account',
          undefined,
          undefined,
          false
        )
      )
    ),
  ]);

  return buildBucketSeries(buckets, bucket => {
    const index = buckets.findIndex(item => item.timestamp === bucket.timestamp);
    const closed = findCountInLabelSummary(
      labelResponses[index]?.data || [],
      BOOKING_CONFIRMED_LABEL
    );
    const total = Number(summaryResponses[index]?.data?.conversations_count || 0);
    if (!total) return 0;
    return Math.round((closed / total) * 1000) / 10;
  });
};

const normalizeLabelSummary = summary => {
  if (!Array.isArray(summary)) return [];
  return summary.map(row => {
    const conversationsCount =
      row.conversationsCount ?? row.conversations_count;
    return {
      name: row.name,
      conversationsCount: Number(conversationsCount || 0),
    };
  });
};

const isAiTrackingLabel = labelName => {
  const name = normalizeLabelKey(labelName);
  if (!name) return false;
  return true;
};

const summaryLabelCountByName = computed(() => {
  const counts = {};
  (labelSummary.value || []).forEach(row => {
    const name = normalizeLabelKey(row?.name);
    if (!name || !isAiTrackingLabel(name)) return;
    const count = Number(
      row?.conversationsCount || row?.conversations_count || 0
    );
    counts[name] = Number(counts[name] || 0) + count;
  });
  return counts;
});

const liveLabelCountByName = computed(() => {
  const counts = {};
  const conversations = Array.isArray(liveConversations.value)
    ? liveConversations.value
    : [];

  conversations.forEach(conversation => {
    const labels = Array.isArray(conversation?.labels)
      ? conversation.labels
      : [];
    labels.forEach(label => {
      const normalizedLabel = normalizeLabelKey(label);
      if (!isAiTrackingLabel(normalizedLabel)) return;
      counts[normalizedLabel] = Number(counts[normalizedLabel] || 0) + 1;
    });
  });

  return counts;
});

const trackedLabelRows = computed(() => {
  const allNames = new Set([
    ...Object.keys(summaryLabelCountByName.value || {}),
    ...Object.keys(liveLabelCountByName.value || {}),
  ]);

  return Array.from(allNames)
    .filter(isAiTrackingLabel)
    .map(name => {
      const summaryCount = Number(summaryLabelCountByName.value[name] || 0);
      const liveCount = Number(liveLabelCountByName.value[name] || 0);
      return {
        name,
        conversationsCount: Math.max(summaryCount, liveCount),
      };
    })
    .filter(row => Number(row?.conversationsCount || 0) > 0)
    .sort((a, b) => {
      const countDiff =
        Number(b.conversationsCount || 0) - Number(a.conversationsCount || 0);
      if (countDiff !== 0) return countDiff;
      return String(a.name || '').localeCompare(String(b.name || ''));
    });
});

const handoverReasonDisplay = label => {
  const raw = String(label || '');
  const key = normalizeLabelKey(raw)
    .replace(/^ly_do_handoff_/, '')
    .replace(/^handover_/, '')
    .toLowerCase();
  return key ? key.replace(/_/g, ' ') : raw;
};

const toTitleCase = text => {
  const value = String(text || '').trim();
  if (!value) return '';
  return value.charAt(0).toUpperCase() + value.slice(1);
};

const formatUnknownLabelDisplay = rawLabel => {
  const label = normalizeLabelKey(rawLabel);
  if (!label) return '';
  if (label.startsWith('ly_do_handoff_') || label.startsWith('handover_')) {
    return handoverReasonDisplay(label);
  }

  const normalized = label
    .replace(/^ai_/, '')
    .replace(/^intent_/, '')
    .replace(/^y_dinh_/, '')
    .replace(/^ly_do_handoff_/, '')
    .replace(/_/g, ' ');

  return toTitleCase(normalized);
};

const labelDisplayName = name => {
  const normalizedName = normalizeLabelKey(name);
  return formatUnknownLabelDisplay(normalizedName);
};

const labelTone = name => {
  const normalizedName = normalizeLabelKey(name);
  if (!normalizedName) return 'slate';
  const tones = ['slate', 'blue', 'teal', 'amber', 'ruby'];
  const hash = Array.from(normalizedName).reduce(
    (acc, ch) => acc + ch.charCodeAt(0),
    0
  );
  return tones[hash % tones.length];
};

const paymentSegmentLabel = segment => {
  const key = String(segment || '')
    .toLowerCase()
    .trim();
  if (key === 'online_course') return 'Khóa online';
  if (key === 'offline_course') return 'Khóa trực tiếp';
  if (key === 'pmu_tool') return 'Công cụ PMU';
  return key || '--';
};

const paymentSegments = item => {
  const fromArray = Array.isArray(item?.segments)
    ? item.segments
        .map(segment =>
          String(segment || '')
            .trim()
            .toLowerCase()
        )
        .filter(Boolean)
    : [];
  const fallback = String(item?.segment || '')
    .trim()
    .toLowerCase();
  const merged = fromArray.length ? fromArray : fallback ? [fallback] : [];
  return Array.from(new Set(merged));
};

const paymentSegmentBadgeClass = segment => {
  const key = String(segment || '')
    .toLowerCase()
    .trim();
  if (key === 'online_course') return 'bg-n-blue-3 text-n-blue-12';
  if (key === 'offline_course') return 'bg-n-amber-3 text-n-amber-12';
  if (key === 'pmu_tool') return 'bg-n-teal-3 text-n-teal-12';
  return 'bg-n-slate-3 text-n-slate-12';
};

const paymentAmountText = item => {
  const amount = String(
    item?.expected_amount_total || item?.expected_amount || ''
  ).trim();
  const currency = String(item?.currency || '').trim();
  if (!amount) return '--';
  return currency ? `${amount} ${currency}` : amount;
};

const paymentTotalAmountSum = computed(() => {
  const cases = Array.isArray(paymentReviewCases.value) ? paymentReviewCases.value : [];
  let total = 0;
  for (const c of cases) {
    const val = parseFloat(c?.expected_amount_total || c?.expected_amount || 0);
    if (!isNaN(val)) total += val;
  }
  return total;
});

const paymentTotalAmountText = computed(() => {
  const val = paymentTotalAmountSum.value;
  if (!val) return '0 USD';
  return val.toLocaleString('vi-VN') + ' USD';
});

const paymentItemCountText = item => {
  const count = Number(
    item?.item_count ||
      (Array.isArray(item?.items) ? item.items.length : 0) ||
      1
  );
  return `${count} item`;
};

const paymentContactName = item => {
  const directName = String(item?.contact_name || '').trim();
  if (directName) return directName;

  const metadata = item?.metadata;
  if (metadata && typeof metadata === 'object') {
    const metaName = String(
      metadata.contact_name || metadata.customer_name || ''
    ).trim();
    if (metaName) return metaName;
  }

  const contactId = String(item?.contact_id || '').trim();
  if (contactId) return `Khách #${contactId}`;
  return 'Khách hàng';
};

const paymentContactAvatar = item => {
  const directAvatar = String(item?.contact_avatar_url || '').trim();
  if (directAvatar) return directAvatar;

  const metadata = item?.metadata;
  if (metadata && typeof metadata === 'object') {
    const metaAvatar = String(
      metadata.contact_avatar_url || metadata.avatar_url || ''
    ).trim();
    if (metaAvatar) return metaAvatar;
  }

  return '';
};

const paymentConversationSubtext = item => {
  const createdAt = formatIsoDateTime(item?.created_at);
  if (createdAt) return `Ca tạo lúc ${createdAt}`;
  return 'Nhấn để mở hội thoại';
};

const paymentNoteText = item => {
  const directNote = String(item?.note || '').trim();
  if (directNote) return directNote;

  const metadata = item?.metadata;
  if (metadata && typeof metadata === 'object') {
    const note = String(
      metadata.note ||
        metadata.notes ||
        metadata.staff_note ||
        metadata.internal_note ||
        ''
    ).trim();
    if (note) return note;
  }
  return '--';
};

const openPaymentConversation = item => {
  openAiControlConversation(item?.conversation_id);
};

const isPaymentCaseActionLoading = caseId => {
  return paymentReviewActionLoading.value.has(String(caseId || '').trim());
};

const confirmPaymentCase = async item => {
  const caseId = String(item?.id || '').trim();
  if (!caseId) return;
  if (isPaymentCaseActionLoading(caseId)) return;

  paymentReviewLastError.value = '';
  paymentReviewActionLoading.value = new Set([
    ...Array.from(paymentReviewActionLoading.value || []),
    caseId,
  ]);

  try {
    const response = await AiControlAPI.reviewPaymentCase(caseId, {
      reviewAction: 'confirm',
      reviewNote: 'Xác nhận thủ công từ Bảng điều khiển AI',
      data: {
        segment: paymentSegments(item)[0] || item?.segment,
        segments: paymentSegments(item),
        item_count: Number(
          item?.item_count ||
            (Array.isArray(item?.items) ? item.items.length : 0) ||
            1
        ),
        order_items: Array.isArray(item?.items) ? item.items : [],
        contact_name: paymentContactName(item),
      },
      triggerPostPaymentSkill: true,
    });

    const result = response?.data || {};
    if (!result?.success) {
      const message =
        result?.message ||
        result?.error ||
        'Không thể xác nhận case thanh toán.';
      throw new Error(String(message));
    }

    // Check kimi skill response
    const skillResult = result?.post_payment_skill || {};
    if (skillResult?.triggered && !skillResult?.error) {
      useAlert('Đã xác nhận thanh toán — Kimi đã gửi phản hồi cho khách.');
    } else if (skillResult?.error) {
      useAlert(
        `Đã xác nhận thanh toán nhưng Kimi gặp lỗi: ${skillResult.error}`
      );
    } else {
      useAlert('Đã xác nhận thanh toán (chưa gửi phản hồi tự động).');
    }

    await fetchPaymentReviewCases();

    if (String(item?.conversation_id || '').trim()) {
      openPaymentConversation(item);
    }
  } catch (e) {
    const message =
      e?.response?.data?.error ||
      e?.response?.data?.detail?.error ||
      e?.message ||
      'Không thể xác nhận case thanh toán.';
    paymentReviewLastError.value = String(message);
    useAlert(paymentReviewLastError.value);
  } finally {
    const next = new Set(paymentReviewActionLoading.value || []);
    next.delete(caseId);
    paymentReviewActionLoading.value = next;
  }
};

const deletePaymentCase = async item => {
  const caseId = String(item?.id || '').trim();
  if (!caseId) return;
  if (isPaymentCaseActionLoading(caseId)) return;

  const confirmed = window.confirm(
    `Xóa case xác minh thanh toán của ${paymentContactName(item)}?`
  );
  if (!confirmed) return;

  paymentReviewLastError.value = '';
  paymentReviewActionLoading.value = new Set([
    ...Array.from(paymentReviewActionLoading.value || []),
    caseId,
  ]);

  try {
    const response = await AiControlAPI.deletePaymentCase(caseId);
    const result = response?.data || {};
    if (!result?.success) {
      const message =
        result?.message || result?.error || 'Không thể xóa case thanh toán.';
      throw new Error(String(message));
    }

    useAlert('Đã xóa case khỏi bảng chờ xác minh thanh toán.');
    await fetchPaymentReviewCases();
  } catch (e) {
    const message =
      e?.response?.data?.error ||
      e?.response?.data?.detail?.error ||
      e?.message ||
      'Không thể xóa case thanh toán.';
    paymentReviewLastError.value = String(message);
    useAlert(paymentReviewLastError.value);
  } finally {
    const next = new Set(paymentReviewActionLoading.value || []);
    next.delete(caseId);
    paymentReviewActionLoading.value = next;
  }
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

const isConversationInHumanMode = conversation => {
  // Chỉ dùng ai_handoff để đánh dấu chế độ human
  const labels = Array.isArray(conversation?.labels) ? conversation.labels : [];
  const normalizedLabels = labels.map(label => normalizeLabelKey(label));
  return normalizedLabels.includes(HANDOFF_LABEL);
};

// ── Per-channel (inbox) AI blocking ──
const inboxList = computed(() => {
  const records = store.getters['inboxes/getInboxes'] || [];
  return records.map(inbox => ({
    id: inbox.id,
    name: inbox.name || `Inbox #${inbox.id}`,
    channelType: inbox.channel_type || '',
  }));
});

const isInboxBlocked = inboxId => {
  return blockedInboxIds.value.has(String(inboxId));
};

const isAllBlocked = computed(() => {
  if (!inboxList.value.length) return false;
  return inboxList.value.every(inbox => isInboxBlocked(inbox.id));
});

const channelIcon = inbox => {
  const type = String(inbox.channelType || '').toLowerCase();
  if (type.includes('facebook')) return '📘';
  if (type.includes('instagram')) return '📸';
  if (type.includes('tiktok')) return '🎵';
  if (type.includes('telegram')) return '✈️';
  if (type.includes('whatsapp')) return '💬';
  if (type.includes('twitter')) return '🐦';
  if (type.includes('email')) return '📧';
  if (type.includes('web')) return '🌐';
  if (type.includes('api')) return '🔌';
  if (type.includes('sms') || type.includes('twilio')) return '📱';
  return '💬';
};

const channelLabel = inbox => {
  const type = String(inbox.channelType || '').toLowerCase();
  if (type.includes('facebook')) return 'Facebook';
  if (type.includes('instagram')) return 'Instagram';
  if (type.includes('tiktok')) return 'TikTok';
  if (type.includes('telegram')) return 'Telegram';
  if (type.includes('whatsapp')) return 'WhatsApp';
  if (type.includes('twitter')) return 'Twitter';
  if (type.includes('email')) return 'Email';
  if (type.includes('web')) return 'Web Widget';
  if (type.includes('api')) return 'API';
  if (type.includes('sms') || type.includes('twilio')) return 'SMS';
  return 'Channel';
};

const fetchBlockedInboxes = async () => {
  isBlockedInboxesLoading.value = true;
  try {
    const response = await AiControlAPI.getBlockedInboxes();
    const ids = response?.data?.blocked_inbox_ids || [];
    blockedInboxIds.value = new Set(ids.map(String));
  } catch (e) {
    useAlert('Không tải được trạng thái dừng AI theo kênh.');
  } finally {
    isBlockedInboxesLoading.value = false;
  }
};

const toggleInboxBlock = async inboxId => {
  const id = String(inboxId);
  try {
    let response;
    if (isInboxBlocked(inboxId)) {
      response = await AiControlAPI.unblockInbox(id);
    } else {
      response = await AiControlAPI.blockInbox(id);
    }
    const ids = response?.data?.blocked_inbox_ids || [];
    blockedInboxIds.value = new Set(ids.map(String));
  } catch (e) {
    useAlert('Không thể thay đổi trạng thái AI cho kênh này.');
  }
};

const toggleAllInboxBlock = async () => {
  isTakeoverAllLoading.value = true;
  try {
    const allIds = inboxList.value.map(inbox => String(inbox.id));
    const action = isAllBlocked.value ? 'unblock' : 'block';
    const response = await AiControlAPI.toggleAllInboxes(allIds, action);
    const ids = response?.data?.blocked_inbox_ids || [];
    blockedInboxIds.value = new Set(ids.map(String));
  } catch (e) {
    useAlert('Không thể thay đổi trạng thái AI cho tất cả kênh.');
  } finally {
    isTakeoverAllLoading.value = false;
  }
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

  trafficConversationCount.value = Number(
    data.incoming_conversations_count || data.conversations_count || 0
  );
};

const fetchBotMetrics = async () => {
  if (!to.value || !from.value) return;

  try {
    const response = await ReportsAPI.getBotMetrics({
      from: from.value,
      to: to.value,
    });
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

const fetchAiGrowthSeries = async (rangeKey = aiGrowthRange.value) => {
  isAiGrowthLoading.value = true;
  aiGrowthError.value = '';

  try {
    if (activeTrendMetric.value === 'revenue') {
      const rows = await fetchAllPaymentReviewCasesForTrend();
      aiGrowthSeries.value = buildRevenueBucketSeries(rows, rangeKey);
      return;
    }

    if (activeTrendMetric.value === 'new_clients') {
      aiGrowthSeries.value = await fetchLabelBucketSeries('khách_mới', rangeKey);
      return;
    }

    if (activeTrendMetric.value === 'return_clients') {
      aiGrowthSeries.value = await fetchLabelBucketSeries(
        'khách_quay_lại',
        rangeKey
      );
      return;
    }

    if (activeTrendMetric.value === 'close_rate') {
      aiGrowthSeries.value = await fetchCloseRateBucketSeries(rangeKey);
      return;
    }

    aiGrowthSeries.value = [];
  } catch (error) {
    aiGrowthSeries.value = [];
    aiGrowthError.value = `Không tải được xu hướng ${activeTrendMetricLabel.value.toLowerCase()}.`;
  } finally {
    isAiGrowthLoading.value = false;
  }
};

const selectAiGrowthRange = async rangeKey => {
  if (!rangeKey || rangeKey === aiGrowthRange.value) return;
  aiGrowthRange.value = rangeKey;
  await fetchAiGrowthSeries(rangeKey);
};

const selectTrendMetric = async metricKey => {
  if (!metricKey || metricKey === activeTrendMetric.value) return;
  activeTrendMetric.value = metricKey;
  await fetchAiGrowthSeries();
};

const isRiskConversation = conversation => {
  const labels = Array.isArray(conversation?.labels) ? conversation.labels : [];
  const normalizedLabels = labels.map(label => normalizeLabelKey(label));
  return (
    normalizedLabels.includes('uu_tien_gap') ||
    normalizedLabels.includes('cam_xuc_tieu_cuc') ||
    normalizedLabels.includes(HANDOFF_LABEL)
  );
};

const playRiskSound = async () => {
  try {
    if (!riskAudio.value) {
      riskAudio.value = new Audio('/audio/dashboard/ding.mp3');
      riskAudio.value.load();
    }
    await riskAudio.value.play();
  } catch (error) {
    useAlert(
      'Trình duyệt đang chặn âm thanh cảnh báo. Hãy cho phép âm thanh để nhận cảnh báo.'
    );
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

const fetchPaymentReviewCases = async (loadMore = false) => {
  isPaymentReviewLoading.value = !loadMore;
  if (loadMore) {
    isPaymentReviewLoadingMore.value = true;
  }
  paymentReviewLastError.value = '';

  try {
    const segment =
      paymentReviewSegment.value === 'all'
        ? undefined
        : paymentReviewSegment.value;
    const response = await AiControlAPI.listPaymentReviewCases({
      reviewStatus: 'all',
      segment,
      limit: paymentReviewLimit.value,
      offset: loadMore ? paymentReviewOffset.value : 0,
    });

    const data = response?.data || {};
    const rows = Array.isArray(data?.cases) ? data.cases : [];
    
    if (loadMore) {
      paymentReviewCases.value = [...paymentReviewCases.value, ...rows];
    } else {
      paymentReviewCases.value = rows;
    }

    paymentReviewTotal.value = Number(data?.total || paymentReviewCases.value.length || 0);
    paymentReviewCount.value = paymentReviewCases.value.length;
    
    paymentReviewHasMore.value = rows.length === paymentReviewLimit.value;
    if (paymentReviewHasMore.value) {
      paymentReviewOffset.value += paymentReviewLimit.value;
    }

  } catch (e) {
    if (!loadMore) {
      paymentReviewCases.value = [];
      paymentReviewTotal.value = 0;
      paymentReviewCount.value = 0;
    }
    paymentReviewLastError.value =
      'Không tải được danh sách chờ xác minh thanh toán.';
    useAlert(paymentReviewLastError.value);
  } finally {
    isPaymentReviewLoading.value = false;
    isPaymentReviewLoadingMore.value = false;
  }
};

const handleTableScroll = (e) => {
  const { scrollTop, clientHeight, scrollHeight } = e.target;
  if (scrollHeight - scrollTop - clientHeight < 50) {
    if (!isPaymentReviewLoading.value && !isPaymentReviewLoadingMore.value && paymentReviewHasMore.value) {
      fetchPaymentReviewCases(true);
    }
  }
};

const refreshPaymentReviewCases = () => {
  paymentReviewOffset.value = 0;
  paymentReviewHasMore.value = true;
  paymentReviewCases.value = [];
  fetchPaymentReviewCases(false);
};

const fetchAll = async () => {
  try {
    await Promise.all([
      fetchTrafficSummary(),
      fetchBotMetrics(),
      fetchLabelSummary(),
      fetchLiveConversations(),
      fetchPaymentReviewCases(),
      fetchManagerQueues(),
    ]);
  } catch (e) {
    useAlert('Không tải được dữ liệu báo cáo.');
  }
};

const formatIsoDateTime = iso => {
  if (!iso) return '';
  try {
    return new Date(iso).toLocaleString('vi-VN');
  } catch (e) {
    return '';
  }
};

const formatQueueAge = minutes => {
  const value = Math.abs(Number(minutes || 0));
  if (!value) return 'vừa cập nhật';
  if (value < 60) return `${value} phút`;
  const hours = Math.floor(value / 60);
  const remain = value % 60;
  if (!remain) return `${hours} giờ`;
  return `${hours} giờ ${remain} phút`;
};

const queueItemTitle = item => {
  return (
    item?.contact_name ||
    item?.contact_id ||
    item?.conversation_display_id ||
    `Hội thoại #${item?.conversation_id || '--'}`
  );
};

const queueReasonLabel = reason => {
  const normalized = normalizeLabelKey(reason || HANDOFF_LABEL);
  if (normalized === HANDOFF_LABEL) return 'Chờ nhân viên phản hồi';

  return toTitleCase(labelDisplayName(normalized)) || 'Chờ nhân viên phản hồi';
};

const scrollToConversationSection = async () => {
  await nextTick();
  conversationSectionRef.value?.scrollIntoView({
    behavior: 'smooth',
    block: 'start',
  });
};

const conversationPreviewName = conversation => {
  const sender = conversation?.meta?.sender;
  const candidates = [
    sender?.name,
    sender?.available_name,
    conversation?.contact?.name,
    conversation?.meta?.name,
  ];
  const match = candidates.find(value => String(value || '').trim());
  return String(match || `Khách #${conversation?.id || '--'}`).trim();
};

const conversationPreviewAvatar = conversation => {
  const sender = conversation?.meta?.sender;
  const candidates = [
    sender?.thumbnail,
    sender?.avatar_url,
    conversation?.contact?.thumbnail,
    conversation?.contact?.avatar_url,
  ];
  const match = candidates.find(value => String(value || '').trim());
  return String(match || '').trim();
};

const conversationStatusText = status => {
  const normalized = String(status || '').toLowerCase().trim();
  if (normalized === 'open') return 'Đang mở';
  if (normalized === 'pending') return 'Đang chờ';
  if (normalized === 'resolved') return 'Đã xử lý';
  if (normalized === 'snoozed') return 'Đang tạm dừng';
  return '';
};

const conversationPreviewSubtext = conversation => {
  const parts = [];
  const displayId = String(
    conversation?.display_id || conversation?.meta?.display_id || ''
  ).trim();
  const statusText = conversationStatusText(conversation?.status);

  if (displayId) parts.push(`#${displayId}`);
  if (statusText) parts.push(statusText);

  return parts.join(' · ') || 'Nhấn để mở phần tin nhắn';
};

const conversationPreviewSnippet = conversation => {
  const candidates = [
    conversation?.last_non_activity_message?.content,
    conversation?.meta?.last_message?.content,
    conversation?.last_activity_message?.content,
    conversation?.meta?.sender?.phone_number,
  ];
  const match = candidates.find(value => String(value || '').trim());
  return String(match || 'Nhấn để mở phần tin nhắn').trim();
};

const normalizeConversationPreviewItem = conversation => {
  const id = String(conversation?.id || '').trim();
  if (!id) return null;

  return {
    id,
    avatarUrl: conversationPreviewAvatar(conversation),
    name: conversationPreviewName(conversation),
    subtext: conversationPreviewSubtext(conversation),
    snippet: conversationPreviewSnippet(conversation),
  };
};

const closeReportLabelPopup = () => {
  showReportLabelPopup.value = false;
  selectedReportLabel.value = '';
  reportLabelPreviewItems.value = [];
  reportLabelPreviewError.value = '';
  isReportLabelPreviewLoading.value = false;
};

const openReportLabelPopup = async label => {
  const normalizedLabel = normalizeLabelKey(label);
  if (!normalizedLabel) return;

  selectedReportLabel.value = normalizedLabel;
  reportLabelPreviewItems.value = [];
  reportLabelPreviewError.value = '';
  showReportLabelPopup.value = true;
  isReportLabelPreviewLoading.value = true;

  try {
    const response = await InboxConversationAPI.get({
      status: 'all',
      assigneeType: 'all',
      sortBy: 'last_activity_at_desc',
      page: 1,
      labels: [normalizedLabel],
    });
    const payload = response?.data?.data?.payload;
    const rows = Array.isArray(payload) ? payload : [];
    reportLabelPreviewItems.value = rows
      .map(normalizeConversationPreviewItem)
      .filter(Boolean);
  } catch (error) {
    reportLabelPreviewError.value =
      error?.response?.data?.error ||
      error?.response?.data?.detail?.error ||
      'Không tải được danh sách hội thoại theo nhãn.';
    useAlert(reportLabelPreviewError.value);
  } finally {
    isReportLabelPreviewLoading.value = false;
  }
};

const openAiControlConversation = async (
  conversationId,
  { preserveRoute = false } = {}
) => {
  const normalizedId = String(conversationId || '').trim();
  if (!normalizedId) return;

  activeMainTab.value = 'operations';

  if (preserveRoute) {
    localAiControlConversationId.value = normalizedId;
  } else {
    localAiControlConversationId.value = 0;
    await router.push({
      name: props.standalone
        ? 'ai_control_simple_conversation'
        : 'ai_control_panel_conversation',
      params: {
        accountId: route.params.accountId,
        conversation_id: normalizedId,
      },
    });
  }

  await scrollToConversationSection();
};

const openReportLabelConversation = async item => {
  const normalizedId = String(item?.id || '').trim();
  if (!normalizedId) return;
  closeReportLabelPopup();
  await openAiControlConversation(normalizedId, { preserveRoute: true });
};

const fetchManagerQueues = async () => {
  const requestSequence = managerQueuesRequestSequence + 1;
  managerQueuesRequestSequence = requestSequence;

  isManagerQueuesLoading.value = true;
  managerQueuesError.value = '';
  // eslint-disable-next-line no-console
  console.log(`${MANAGER_QUEUE_LOG_PREFIX} Bắt đầu luồng`);
  // eslint-disable-next-line no-console
  console.log(
    `${MANAGER_QUEUE_LOG_PREFIX} Bước 1: Tải danh sách chờ nhân viên phản hồi.`
  );

  try {
    const handoffResp = await AiControlAPI.getManagerAiHandoffQueue({
      limit: 20,
      maxConversations: 200,
    });
    if (requestSequence !== managerQueuesRequestSequence) {
      // eslint-disable-next-line no-console
      console.warn(
        `${MANAGER_QUEUE_LOG_PREFIX} Cảnh báo tại bước 2: Bỏ qua response cũ vì đã có lượt tải mới hơn.`
      );
      return;
    }

    managerAiHandoffQueue.value = Array.isArray(handoffResp?.data?.items)
      ? handoffResp.data.items
      : [];
    // eslint-disable-next-line no-console
    console.log(
      `${MANAGER_QUEUE_LOG_PREFIX} Bước 2: Đã cập nhật danh sách chờ nhân viên phản hồi.`
    );
  } catch (error) {
    if (requestSequence !== managerQueuesRequestSequence) {
      // eslint-disable-next-line no-console
      console.warn(
        `${MANAGER_QUEUE_LOG_PREFIX} Cảnh báo tại bước 2: Bỏ qua lỗi cũ vì đã có lượt tải mới hơn.`
      );
      return;
    }

    managerAiHandoffQueue.value = [];
    managerQueuesError.value =
      error?.response?.data?.error ||
      error?.response?.data?.detail?.error ||
      'Không tải được danh sách chờ nhân viên phản hồi.';
    // eslint-disable-next-line no-console
    console.error(
      `${MANAGER_QUEUE_LOG_PREFIX} Lỗi tại bước 2: Không tải được danh sách chờ nhân viên phản hồi.`,
      error
    );
    useAlert(managerQueuesError.value);
  } finally {
    if (requestSequence !== managerQueuesRequestSequence) {
      return;
    }

    isManagerQueuesLoading.value = false;
    // eslint-disable-next-line no-console
    console.log(`${MANAGER_QUEUE_LOG_PREFIX} Kết thúc luồng`);
  }
};

const fetchCustomer360 = async conversationId => {
  const normalizedId = String(conversationId || '').trim();
  if (!normalizedId || normalizedId === '0') {
    customer360.value = null;
    customer360Error.value = '';
    return;
  }

  isCustomer360Loading.value = true;
  customer360Error.value = '';
  try {
    const response = await AiControlAPI.getManagerCustomer360({
      conversationId: normalizedId,
      recentMessageLimit: 8,
      memoryLimit: 5,
    });
    customer360.value =
      response?.data && typeof response.data === 'object' ? response.data : null;
  } catch (error) {
    customer360.value = null;
    customer360Error.value =
      error?.response?.data?.error ||
      error?.response?.data?.detail?.error ||
      'Không tải được Customer 360.';
  } finally {
    isCustomer360Loading.value = false;
  }
};

const fetchAftercareSequences = async () => {
  const response = await AiControlAPI.listAftercareSequences();
  aftercareSequences.value = Array.isArray(response?.data?.payload)
    ? response.data.payload
    : [];
};

const fetchAftercareEligibility = async conversationId => {
  const normalizedId = String(conversationId || '').trim();
  if (!normalizedId || normalizedId === '0') {
    aftercareEligibility.value = null;
    return null;
  }

  const response = await AiControlAPI.getAftercareEligibility({
    conversationId: normalizedId,
  });
  aftercareEligibility.value =
    response?.data && typeof response.data === 'object' ? response.data : null;
  return aftercareEligibility.value;
};

const fetchAftercareEnrollments = async () => {
  isAftercareLoading.value = true;
  aftercareLastError.value = '';

  try {
    const response = await AiControlAPI.listAftercareEnrollments();
    aftercareEnrollments.value = Array.isArray(response?.data?.payload)
      ? response.data.payload
      : [];
  } catch (error) {
    aftercareEnrollments.value = [];
    aftercareLastError.value =
      error?.response?.data?.error ||
      error?.response?.data?.detail ||
      'Không tải được danh sách tư vấn sau mua.';
    useAlert(aftercareLastError.value);
  } finally {
    isAftercareLoading.value = false;
  }
};

const aftercareDraftEditKey = (enrollmentId, stepId) => {
  return `${String(enrollmentId || '').trim()}:${String(stepId || '').trim()}`;
};

const isAftercareDraftEditing = (enrollmentId, stepId) => {
  return aftercareEditingDraftStepIds.value.has(
    aftercareDraftEditKey(enrollmentId, stepId)
  );
};

const isAftercareDraftSaving = (enrollmentId, stepId) => {
  return aftercareSavingDraftStepIds.value.has(
    aftercareDraftEditKey(enrollmentId, stepId)
  );
};

const getAftercareDraftEditValue = (enrollmentId, stepId) => {
  const key = aftercareDraftEditKey(enrollmentId, stepId);
  return String(aftercareDraftEdits.value[key] || '');
};

const setAftercareDraftEditValue = (enrollmentId, stepId, value) => {
  const key = aftercareDraftEditKey(enrollmentId, stepId);
  aftercareDraftEdits.value = {
    ...aftercareDraftEdits.value,
    [key]: String(value || ''),
  };
};

const startAftercareDraftEdit = (enrollmentId, step) => {
  const normalizedEnrollmentId = String(enrollmentId || '').trim();
  const normalizedStepId = String(step?.id || '').trim();
  if (!normalizedEnrollmentId || !normalizedStepId) return;

  const key = aftercareDraftEditKey(normalizedEnrollmentId, normalizedStepId);
  aftercareEditingDraftStepIds.value = new Set([
    ...Array.from(aftercareEditingDraftStepIds.value || []),
    key,
  ]);
  setAftercareDraftEditValue(
    normalizedEnrollmentId,
    normalizedStepId,
    step?.draft_body || ''
  );
};

const cancelAftercareDraftEdit = (enrollmentId, stepId) => {
  const key = aftercareDraftEditKey(enrollmentId, stepId);
  const nextEditing = new Set(aftercareEditingDraftStepIds.value || []);
  nextEditing.delete(key);
  aftercareEditingDraftStepIds.value = nextEditing;

  const nextDraftEdits = { ...(aftercareDraftEdits.value || {}) };
  delete nextDraftEdits[key];
  aftercareDraftEdits.value = nextDraftEdits;
};

const setAftercareDraftSaving = (enrollmentId, stepId, isSaving) => {
  const key = aftercareDraftEditKey(enrollmentId, stepId);
  const next = new Set(aftercareSavingDraftStepIds.value || []);
  if (isSaving) {
    next.add(key);
  } else {
    next.delete(key);
  }
  aftercareSavingDraftStepIds.value = next;
};

const setAftercareStepRefreshing = (stepId, isRefreshing) => {
  const key = String(stepId || '').trim();
  const next = new Set(aftercareRefreshingStepIds.value);
  if (!key) return;

  if (isRefreshing) {
    next.add(key);
  } else {
    next.delete(key);
  }

  aftercareRefreshingStepIds.value = next;
};

const isAftercareStepRefreshing = stepId => {
  return aftercareRefreshingStepIds.value.has(String(stepId || '').trim());
};

const setAftercareStepRetrying = (stepId, isRetrying) => {
  const normalizedId = String(stepId || '').trim();
  if (!normalizedId) return;

  const next = new Set(aftercareRetryingStepIds.value);
  if (isRetrying) {
    next.add(normalizedId);
  } else {
    next.delete(normalizedId);
  }
  aftercareRetryingStepIds.value = next;
};

const isAftercareStepRetrying = stepId => {
  return aftercareRetryingStepIds.value.has(String(stepId || '').trim());
};

const setAftercareEnrollmentCancelling = (enrollmentId, isCancelling) => {
  const normalizedId = String(enrollmentId || '').trim();
  if (!normalizedId) return;

  const next = new Set(aftercareCancellingEnrollmentIds.value);
  if (isCancelling) {
    next.add(normalizedId);
  } else {
    next.delete(normalizedId);
  }
  aftercareCancellingEnrollmentIds.value = next;
};

const isAftercareEnrollmentCancelling = enrollmentId => {
  return aftercareCancellingEnrollmentIds.value.has(
    String(enrollmentId || '').trim()
  );
};

const setAftercareEnrollmentTransitioning = (enrollmentId, isTransitioning) => {
  const normalizedId = String(enrollmentId || '').trim();
  if (!normalizedId) return;

  const next = new Set(aftercareTransitioningEnrollmentIds.value);
  if (isTransitioning) {
    next.add(normalizedId);
  } else {
    next.delete(normalizedId);
  }
  aftercareTransitioningEnrollmentIds.value = next;
};

const isAftercareEnrollmentTransitioning = enrollmentId => {
  return aftercareTransitioningEnrollmentIds.value.has(
    String(enrollmentId || '').trim()
  );
};

const openAftercareDialog = async () => {
  const normalizedId = String(aiControlConversationId.value || '').trim();
  if (!normalizedId || normalizedId === '0') {
    useAlert('Chọn một hội thoại trước khi tạo kế hoạch tư vấn sau mua.');
    return;
  }

  showAftercareDialog.value = true;
  isAftercareDialogLoading.value = true;
  aftercareLastError.value = '';

  try {
    await Promise.all([
      fetchAftercareSequences(),
      fetchAftercareEligibility(normalizedId),
    ]);
  } catch (error) {
    aftercareLastError.value =
      error?.response?.data?.error ||
      error?.response?.data?.detail ||
      'Không tải được cấu hình tư vấn sau mua.';
    useAlert(aftercareLastError.value);
  } finally {
    isAftercareDialogLoading.value = false;
  }
};

const submitAftercareEnrollment = async payload => {
  isAftercareSubmitting.value = true;

  try {
    await AiControlAPI.createAftercareEnrollment(payload);
    showAftercareDialog.value = false;
    activeMainTab.value = 'aftercare';
    await fetchAftercareEnrollments();
    useAlert('Đã tạo kế hoạch tư vấn sau mua.');
  } catch (error) {
    const message =
      error?.response?.data?.detail ||
      error?.response?.data?.error ||
      'Không thể tạo kế hoạch tư vấn sau mua.';
    useAlert(String(message));
  } finally {
    isAftercareSubmitting.value = false;
  }
};

const aftercareDraftStatusText = value => {
  const key = String(value || '').trim();
  const labels = {
    not_requested: 'Chưa tạo bản nháp',
    pending: 'Đang tạo bản nháp',
    ready: 'Đã sẵn sàng',
    failed_generation: 'Lỗi tạo bản nháp',
  };
  return labels[key] || key || '—';
};

const aftercareStepStatusText = value => {
  const key = String(value || '').trim();
  const labels = {
    draft_pending: 'Chờ bản nháp',
    draft_ready: 'Bản nháp sẵn sàng',
    scheduled: 'Chờ gửi',
    sending: 'Đang gửi',
    sent: 'Đã gửi',
    failed: 'Lỗi gửi',
    cancelled: 'Đã hủy',
    skipped: 'Bỏ qua',
  };
  return labels[key] || key || '—';
};

const aftercareDispatchStatusText = value => {
  const key = String(value || '').trim();
  const labels = {
    sending: 'Đang gửi',
    sent: 'Đã gửi',
    failed: 'Lỗi gửi',
  };
  return labels[key] || key || '—';
};

const updateAftercareEnrollmentInState = enrollmentPayload => {
  const normalizedEnrollmentId = String(enrollmentPayload?.id || '').trim();
  if (!normalizedEnrollmentId) return;

  aftercareEnrollments.value = (aftercareEnrollments.value || []).map(item => {
    if (String(item?.id || '').trim() !== normalizedEnrollmentId) {
      return item;
    }

    return {
      ...item,
      ...enrollmentPayload,
    };
  });
};

const updateAftercareStepInState = (enrollmentId, stepPayload) => {
  const normalizedEnrollmentId = String(enrollmentId || '').trim();
  const normalizedStepId = String(stepPayload?.id || '').trim();
  if (!normalizedEnrollmentId || !normalizedStepId) return;

  aftercareEnrollments.value = (aftercareEnrollments.value || []).map(item => {
    if (String(item?.id || '').trim() !== normalizedEnrollmentId) {
      return item;
    }

    const nextSteps = Array.isArray(item?.steps)
      ? item.steps.map(step => {
          if (String(step?.id || '').trim() !== normalizedStepId) {
            return step;
          }

          return {
            ...step,
            ...stepPayload,
          };
        })
      : [];

    return {
      ...item,
      steps: nextSteps,
    };
  });
};

const regenerateAftercareDraft = async (enrollmentId, stepId) => {
  const normalizedEnrollmentId = String(enrollmentId || '').trim();
  const normalizedStepId = String(stepId || '').trim();
  if (!normalizedEnrollmentId || !normalizedStepId) return;

  setAftercareStepRefreshing(normalizedStepId, true);

  try {
    const response = await AiControlAPI.regenerateAftercareDraft({
      enrollmentId: normalizedEnrollmentId,
      stepId: normalizedStepId,
    });
    const payload =
      response?.data && typeof response.data === 'object'
        ? response.data.payload
        : null;
    if (payload && typeof payload === 'object') {
      updateAftercareStepInState(normalizedEnrollmentId, payload);
    }
    useAlert('Đã tạo lại bản nháp tư vấn sau mua.');
  } catch (error) {
    const message =
      error?.response?.data?.detail ||
      error?.response?.data?.error ||
      'Không thể tạo lại bản nháp tư vấn sau mua.';
    useAlert(String(message));
  } finally {
    setAftercareStepRefreshing(normalizedStepId, false);
  }
};

const saveAftercareDraftEdit = async (enrollmentId, stepId) => {
  const normalizedEnrollmentId = String(enrollmentId || '').trim();
  const normalizedStepId = String(stepId || '').trim();
  if (!normalizedEnrollmentId || !normalizedStepId) return;

  const draftBody = getAftercareDraftEditValue(
    normalizedEnrollmentId,
    normalizedStepId
  ).trim();
  if (!draftBody) {
    useAlert('Nội dung bản nháp không được để trống.');
    return;
  }

  setAftercareDraftSaving(normalizedEnrollmentId, normalizedStepId, true);

  try {
    const response = await AiControlAPI.updateAftercareStepDraft({
      enrollmentId: normalizedEnrollmentId,
      stepId: normalizedStepId,
      draftBody,
    });
    const payload =
      response?.data && typeof response.data === 'object'
        ? response.data.payload
        : null;
    if (payload && typeof payload === 'object') {
      updateAftercareStepInState(normalizedEnrollmentId, payload);
      setAftercareDraftEditValue(
        normalizedEnrollmentId,
        normalizedStepId,
        payload.draft_body || draftBody
      );
    }
    cancelAftercareDraftEdit(normalizedEnrollmentId, normalizedStepId);
    useAlert('Đã lưu nội dung bản nháp.');
  } catch (error) {
    const message =
      error?.response?.data?.detail ||
      error?.response?.data?.error ||
      'Không thể lưu nội dung bản nháp.';
    useAlert(String(message));
  } finally {
    setAftercareDraftSaving(normalizedEnrollmentId, normalizedStepId, false);
  }
};

const retryAftercareStep = async (enrollmentId, stepId) => {
  const normalizedEnrollmentId = String(enrollmentId || '').trim();
  const normalizedStepId = String(stepId || '').trim();
  if (!normalizedEnrollmentId || !normalizedStepId) return;

  setAftercareStepRetrying(normalizedStepId, true);

  try {
    const response = await AiControlAPI.retryAftercareStep({
      enrollmentId: normalizedEnrollmentId,
      stepId: normalizedStepId,
    });
    const payload =
      response?.data && typeof response.data === 'object'
        ? response.data.payload
        : null;
    if (payload && typeof payload === 'object') {
      updateAftercareStepInState(normalizedEnrollmentId, payload);
    }
    useAlert('Đã đưa bước tư vấn sau mua vào hàng chờ gửi lại.');
  } catch (error) {
    const message =
      error?.response?.data?.detail ||
      error?.response?.data?.error ||
      'Không thể gửi lại bước tư vấn sau mua.';
    useAlert(String(message));
  } finally {
    setAftercareStepRetrying(normalizedStepId, false);
  }
};

const cancelAftercareEnrollment = async enrollmentId => {
  const normalizedEnrollmentId = String(enrollmentId || '').trim();
  if (!normalizedEnrollmentId) return;

  setAftercareEnrollmentCancelling(normalizedEnrollmentId, true);

  try {
    const response = await AiControlAPI.cancelAftercareEnrollment({
      enrollmentId: normalizedEnrollmentId,
    });
    const payload =
      response?.data && typeof response.data === 'object'
        ? response.data.payload
        : null;
    if (payload && typeof payload === 'object') {
      updateAftercareEnrollmentInState(payload);
    }
    useAlert('Đã hủy kế hoạch tư vấn sau mua.');
  } catch (error) {
    const message =
      error?.response?.data?.detail ||
      error?.response?.data?.error ||
      'Không thể hủy kế hoạch tư vấn sau mua.';
    useAlert(String(message));
  } finally {
    setAftercareEnrollmentCancelling(normalizedEnrollmentId, false);
  }
};

const pauseAftercareEnrollment = async enrollmentId => {
  const normalizedEnrollmentId = String(enrollmentId || '').trim();
  if (!normalizedEnrollmentId) return;

  setAftercareEnrollmentTransitioning(normalizedEnrollmentId, true);

  try {
    const response = await AiControlAPI.pauseAftercareEnrollment({
      enrollmentId: normalizedEnrollmentId,
    });
    const payload =
      response?.data && typeof response.data === 'object'
        ? response.data.payload
        : null;
    if (payload && typeof payload === 'object') {
      updateAftercareEnrollmentInState(payload);
    }
    useAlert('Đã tạm dừng kế hoạch tư vấn sau mua.');
  } catch (error) {
    const message =
      error?.response?.data?.detail ||
      error?.response?.data?.error ||
      'Không thể tạm dừng kế hoạch tư vấn sau mua.';
    useAlert(String(message));
  } finally {
    setAftercareEnrollmentTransitioning(normalizedEnrollmentId, false);
  }
};

const resumeAftercareEnrollment = async enrollmentId => {
  const normalizedEnrollmentId = String(enrollmentId || '').trim();
  if (!normalizedEnrollmentId) return;

  setAftercareEnrollmentTransitioning(normalizedEnrollmentId, true);

  try {
    const response = await AiControlAPI.resumeAftercareEnrollment({
      enrollmentId: normalizedEnrollmentId,
    });
    const payload =
      response?.data && typeof response.data === 'object'
        ? response.data.payload
        : null;
    if (payload && typeof payload === 'object') {
      updateAftercareEnrollmentInState(payload);
    }
    useAlert('Đã tiếp tục kế hoạch tư vấn sau mua.');
  } catch (error) {
    const message =
      error?.response?.data?.detail ||
      error?.response?.data?.error ||
      'Không thể tiếp tục kế hoạch tư vấn sau mua.';
    useAlert(String(message));
  } finally {
    setAftercareEnrollmentTransitioning(normalizedEnrollmentId, false);
  }
};

const aftercareStatusText = value => {
  const key = String(value || '').trim();
  const labels = {
    draft: 'Bản nháp',
    pending_optin: 'Chờ Gmail sẵn sàng',
    active: 'Đang hoạt động',
    paused: 'Tạm dừng',
    blocked_outside_window: 'Bị chặn do ngoài cửa sổ gửi',
    blocked_capability_disabled: 'Bị chặn do Gmail chưa sẵn sàng',
    completed: 'Hoàn tất',
    cancelled: 'Đã hủy',
    expired: 'Hết hạn',
  };
  return labels[key] || key || '—';
};

const aftercareOptInText = value => {
  const key = String(value || '').trim();
  const labels = {
    not_requested: 'Chưa kiểm tra',
    requested: 'Đang chuẩn bị Gmail',
    subscribed: 'Gmail sẵn sàng',
    reoptin_required: 'Cần kích hoạt lại',
    expired: 'Hết hạn',
    revoked: 'Đã tắt',
    unsupported_channel_capability: 'Gmail chưa sẵn sàng',
  };
  return labels[key] || key || '—';
};

const aftercareCapabilityStatusText = value => {
  const key = String(value || '').trim();
  const labels = {
    supported: 'Đã sẵn sàng',
    disabled: 'Đang tắt',
    unsupported: 'Chưa hỗ trợ',
    permission_required: 'Thiếu quyền',
    reauthorization_required: 'Cần kết nối lại hộp thư',
    email_missing: 'Thiếu email khách',
    smtp_not_configured: 'SMTP/Gmail chưa cấu hình',
  };
  return labels[key] || key || '—';
};

const aftercareOptInWarningText = enrollment => {
  const item = enrollment || {};
  const subscription = item?.opt_in_subscription || {};

  if (item?.reauthorization_required) {
    return 'Hộp thư cần kết nối lại trước khi gửi ngoài 24 giờ.';
  }

  if (String(subscription?.status || '').trim() === 'expired') {
    return 'Kết nối Gmail cho tư vấn sau mua đã hết hạn.';
  }

  const capabilityStatus = String(subscription?.capability_status || '').trim();
  if (capabilityStatus && capabilityStatus !== 'supported') {
    return `Gmail: ${aftercareCapabilityStatusText(capabilityStatus)}.`;
  }

  return String(item?.last_error || subscription?.last_error || '').trim();
};

const aftercareNextSendText = enrollment => {
  const rows = Array.isArray(enrollment?.steps) ? enrollment.steps : [];
  const nextStep = rows
    .filter(step => step?.enabled !== false && step?.scheduled_for)
    .sort((a, b) => new Date(a.scheduled_for) - new Date(b.scheduled_for))[0];

  return formatIsoDateTime(nextStep?.scheduled_for) || '—';
};

const AFTERCARE_DRAFT_PREVIEW_LIMIT = 110;

const normalizeAftercareDraftBody = value => {
  return String(value || '').replace(/\s+/g, ' ').trim();
};

const aftercareDraftPreviewText = value => {
  const normalized = normalizeAftercareDraftBody(value);
  if (!normalized) return '';
  if (normalized.length <= AFTERCARE_DRAFT_PREVIEW_LIMIT) {
    return normalized;
  }
  return `${normalized.slice(0, AFTERCARE_DRAFT_PREVIEW_LIMIT).trimEnd()}...`;
};

const runFaqTraining = async () => {
  const days = Number(faqTrainingDays.value || 0);
  if (!Number.isFinite(days) || days < 1 || days > 365) {
    useAlert('Số ngày training phải trong khoảng 1-365.');
    return;
  }

  isFaqTrainingLoading.value = true;
  try {
    const response = await AiControlAPI.trainFaq({
      days,
      dryRun: false,
      conversationsPerBatch: 20,
    });

    const report = response?.data?.report || response?.data;
    faqTrainingReport.value =
      report && typeof report === 'object' ? report : null;

    const created = Number(report?.published_count || 0);
    const duplicates = Number(report?.duplicate_count || 0);
    const conflicts = Number(report?.conflict_count || 0);
    const errors = Number(report?.error_count || 0);
    useAlert(
      `Training FAQ ${days} ngày xong: mới ${created}, trùng ${duplicates}, conflict ${conflicts}, lỗi ${errors}.`
    );
  } catch (error) {
    const message =
      error?.response?.data?.detail?.error ||
      error?.response?.data?.detail?.raw ||
      error?.response?.data?.error ||
      'Không thể chạy training FAQ.';
    useAlert(String(message));
  } finally {
    isFaqTrainingLoading.value = false;
  }
};

const onFilterChange = async ({ from: nextFrom, to: nextTo }) => {
  from.value = nextFrom;
  to.value = nextTo;
  await fetchAll();
};

// Old per-conversation pause logic removed — now using per-channel inbox blocking

const refreshLiveConversationsNow = async () => {
  await Promise.all([
    fetchLiveConversations(),
    fetchPaymentReviewCases(),
    fetchManagerQueues(),
  ]);
  if (to.value && from.value) {
    await Promise.all([
      fetchTrafficSummary(),
      fetchBotMetrics(),
      fetchLabelSummary(),
    ]);
  }
};

const onRefreshLiveConversations = () => {
  if (realtimeOperationsRefreshTimer) {
    window.clearTimeout(realtimeOperationsRefreshTimer);
    // eslint-disable-next-line no-console
    console.log(
      `${REALTIME_REFRESH_LOG_PREFIX} Bước 1: Có thêm event realtime nên dời lịch tải lại dữ liệu.`
    );
  } else {
    // eslint-disable-next-line no-console
    console.log(`${REALTIME_REFRESH_LOG_PREFIX} Bắt đầu luồng`);
    // eslint-disable-next-line no-console
    console.log(
      `${REALTIME_REFRESH_LOG_PREFIX} Bước 1: Gom các event realtime gần nhau trước khi tải lại dữ liệu.`
    );
  }

  realtimeOperationsRefreshTimer = window.setTimeout(async () => {
    try {
      // eslint-disable-next-line no-console
      console.log(
        `${REALTIME_REFRESH_LOG_PREFIX} Bước 2: Tải lại dữ liệu vận hành từ event realtime.`
      );
      await refreshLiveConversationsNow();
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error(
        `${REALTIME_REFRESH_LOG_PREFIX} Lỗi tại bước 2: Không tải lại được dữ liệu vận hành.`,
        error
      );
    } finally {
      realtimeOperationsRefreshTimer = null;
      // eslint-disable-next-line no-console
      console.log(`${REALTIME_REFRESH_LOG_PREFIX} Kết thúc luồng`);
    }
  }, REALTIME_OPERATIONS_REFRESH_DELAY);
};

const openReportingDashboard = () => {
  window.open(reportingDashboardUrl.value, '_blank');
};

// Label management methods
const openAddLabelPopup = () => {
  showAddLabelPopup.value = true;
};

const closeAddLabelPopup = () => {
  showAddLabelPopup.value = false;
};

const openDeleteLabelPopup = label => {
  selectedLabelToDelete.value = label;
  showDeleteLabelPopup.value = true;
};

const closeDeleteLabelPopup = () => {
  showDeleteLabelPopup.value = false;
  selectedLabelToDelete.value = null;
};

const deleteLabel = async () => {
  if (!selectedLabelToDelete.value?.id) return;
  isDeletingLabel.value = true;
  try {
    await store.dispatch('labels/delete', selectedLabelToDelete.value.id);
    useAlert('Đã xóa nhãn thành công.');
    closeDeleteLabelPopup();
  } catch (error) {
    const message =
      error?.message || 'Không thể xóa nhãn.';
    useAlert(message);
  } finally {
    isDeletingLabel.value = false;
  }
};

const labelRecords = computed(() => {
  return store.getters['labels/getLabels'] || [];
});

const findLabelByTitle = labelTitle => {
  const normalized = normalizeLabelKey(labelTitle);
  return labelRecords.value.find(
    label => normalizeLabelKey(label.title) === normalized
  );
};

// ── Chart.js integration ──
const chartJsLoaded = ref(false);
const handoffChartRef = ref(null);
const aiGrowthChartRef = ref(null);
const labelPolarChartRef = ref(null);
let handoffChartInstance = null;
let aiGrowthChartInstance = null;
let labelPolarChartInstance = null;

const loadChartJs = () => {
  return new Promise((resolve) => {
    if (window.Chart) { chartJsLoaded.value = true; resolve(); return; }
    const script = document.createElement('script');
    script.src = 'https://cdn.jsdelivr.net/npm/chart.js@4.4.7/dist/chart.umd.min.js';
    script.onload = () => { chartJsLoaded.value = true; resolve(); };
    script.onerror = () => resolve();
    document.head.appendChild(script);
  });
};

const reportHandoffData = computed(() => {
  const total = Number(labelOverviewTotal.value || 0);
  const handoff = trackedLabelCount('ai_handoff');
  const confirmed = trackedLabelCount(BOOKING_CONFIRMED_LABEL);
  const botHandled = Math.max(0, total - handoff - confirmed);
  return { total, handoff, confirmed, botHandled };
});

const reportLabelChartData = computed(() => {
  const rows = Array.isArray(trackedLabelRows.value) ? trackedLabelRows.value : [];
  return rows
    .filter(r => !String(r?.name || '').startsWith('ly_do_handoff_'))
    .slice(0, 8);
});

const renderCharts = () => {
  if (!window.Chart || !chartJsLoaded.value) return;
  const Chart = window.Chart;

  // Cleanup old instances
  if (handoffChartInstance) { handoffChartInstance.destroy(); handoffChartInstance = null; }
  if (aiGrowthChartInstance) { aiGrowthChartInstance.destroy(); aiGrowthChartInstance = null; }
  if (labelPolarChartInstance) { labelPolarChartInstance.destroy(); labelPolarChartInstance = null; }

  // 1. AI Handoff Doughnut
  const doughnutEl = handoffChartRef.value;
  if (doughnutEl) {
    const hd = reportHandoffData.value;
    handoffChartInstance = new Chart(doughnutEl, {
      type: 'doughnut',
      data: {
        labels: ['Bot tự xử lý', 'Chuyển nhân viên (Handoff)', 'Xác nhận đặt lịch'],
        datasets: [{ data: [hd.botHandled, hd.handoff, hd.confirmed], backgroundColor: ['rgba(16,185,129,0.8)','rgba(239,68,68,0.8)','rgba(59,130,246,0.8)'], borderWidth: 0, hoverOffset: 4 }]
      },
      options: { responsive: true, maintainAspectRatio: false, cutout: '65%', plugins: { legend: { position: 'bottom', labels: { padding: 12, usePointStyle: true, boxWidth: 8, color: '#64748b', font: { size: 11 } } } } }
    });
  }

  // 2. AI Growth Line
  const growthEl = aiGrowthChartRef.value;
  if (growthEl) {
    const points = Array.isArray(aiGrowthSeries.value) ? aiGrowthSeries.value : [];
    aiGrowthChartInstance = new Chart(growthEl, {
      type: 'line',
      data: {
        labels: points.map(point => point.label || formatAiGrowthAxisLabel(point.timestamp)),
        datasets: [{
          label: activeTrendMetricLabel.value,
          data: points.map(point => point.value || 0),
          borderColor: 'rgba(37,99,235,0.95)',
          backgroundColor: 'rgba(59,130,246,0.14)',
          fill: true,
          tension: 0.35,
          borderWidth: 2,
          pointRadius: 0,
          pointHoverRadius: 4,
          pointHoverBackgroundColor: 'rgba(37,99,235,1)',
          pointHoverBorderColor: '#ffffff',
          pointHoverBorderWidth: 2,
        }]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
          legend: { display: false },
          tooltip: {
            callbacks: {
              title: items => {
                const point = points[items?.[0]?.dataIndex || 0];
                return point?.label || formatAiGrowthTooltipLabel(point?.timestamp);
              },
              label: item => ` ${formatTrendValueText(item.raw || 0)}`,
            },
          },
        },
        scales: {
          x: {
            grid: { display: false },
            ticks: {
              color: '#64748b',
              maxTicksLimit: aiGrowthRange.value === '1y' ? 6 : 8,
            },
          },
          y: {
            beginAtZero: true,
            grid: { color: 'rgba(0,0,0,0.06)' },
            ticks: {
              color: '#64748b',
              callback: value => formatTrendValueText(value),
            },
          },
        },
      }
    });
  }

  // 3. Label Distribution Polar
  const polarEl = labelPolarChartRef.value;
  if (polarEl) {
    const lblData = reportLabelChartData.value;
    const polarColors = ['rgba(59,130,246,0.7)','rgba(16,185,129,0.7)','rgba(168,85,247,0.7)','rgba(245,158,11,0.7)','rgba(236,72,153,0.7)','rgba(14,165,233,0.7)','rgba(244,63,94,0.7)','rgba(34,197,94,0.7)'];
    labelPolarChartInstance = new Chart(polarEl, {
      type: 'polarArea',
      data: {
        labels: lblData.map(r => toTitleCase(labelDisplayName(r.name))),
        datasets: [{ data: lblData.map(r => r.conversationsCount || 0), backgroundColor: lblData.map((_, i) => polarColors[i % polarColors.length]), borderWidth: 1, borderColor: 'rgba(0,0,0,0.05)' }]
      },
      options: { responsive: true, maintainAspectRatio: false, plugins: { legend: { position: 'bottom', labels: { padding: 10, usePointStyle: true, boxWidth: 8, color: '#64748b', font: { size: 11 } } } }, scales: { r: { ticks: { display: false }, grid: { color: 'rgba(0,0,0,0.06)' } } } }
    });
  }
};

// ── Comment Tab State ──
const commentQueue = ref([]);
const commentTotal = ref(0);
const isCommentLoading = ref(false);
const commentOffset = ref(0);
const commentLimit = ref(50);
const commentStatusFilter = ref('');
const selectedCommentConversation = ref(null);
const commentThread = ref([]);
const isCommentThreadLoading = ref(false);
const commentReplyText = ref('');
const isCommentReplying = ref(false);
const isCommentAutoReplying = ref(false);
const replyingToComment = ref(null);

const setReplyingTo = (msg) => {
  replyingToComment.value = msg;
  commentReplyText.value = '';
};

const clearReplyingTo = () => {
  replyingToComment.value = null;
};

// Build nested comment tree from flat list
const buildCommentTree = (comments) => {
  if (!Array.isArray(comments)) return [];

  const commentMap = {};
  const rootComments = [];

  // First pass: create map of all comments
  comments.forEach(c => {
    commentMap[c.id] = { ...c, replies: [] };
  });

  // Second pass: build tree structure
  comments.forEach(c => {
    const node = commentMap[c.id];
    if (c.parent_comment_id && commentMap[comments.find(x => x.comment_id === c.parent_comment_id)?.id]) {
      // Find parent by comment_id
      const parent = Object.values(commentMap).find(p => p.comment_id === c.parent_comment_id);
      if (parent) {
        parent.replies.push(node);
      } else {
        rootComments.push(node);
      }
    } else {
      rootComments.push(node);
    }
  });

  return rootComments;
};

// Nested comment component template (rendered recursively)
const renderCommentNode = (msg, depth = 0) => {
  const isReply = depth > 0;
  const maxDepth = 3;

  return `
    <div class="flex flex-col gap-1 ${isReply ? 'ml-6 mt-2 border-l-2 border-n-slate-3 pl-3' : ''}">
      <div
        class="max-w-[85%] rounded-xl px-3 py-2 text-sm shadow-sm group relative"
        :class="
          msg.direction === 'outgoing'
            ? 'bg-n-teal-3 text-n-teal-12 rounded-br-md'
            : 'bg-n-slate-3 text-n-slate-12 rounded-bl-md'
        "
      >
        <div class="flex items-center gap-2 mb-1">
          <div
            class="w-5 h-5 rounded-full flex-shrink-0 flex items-center justify-center text-[9px] font-bold"
            :class="msg.direction === 'outgoing' ? 'bg-n-teal-4 text-n-teal-11' : 'bg-n-slate-4 text-n-slate-11'"
          >
            ${msg.direction === 'outgoing' ? '🤖' : (msg.author_name || 'U')[0].toUpperCase()}
          </div>
          <span class="text-[10px] font-semibold opacity-80">
            {{ msg.direction === 'outgoing' ? 'Bot / Agent' : (msg.author_name || 'Khách') }}
          </span>
          <span class="text-[9px] opacity-50">{{ commentTimeAgo(msg.created_at) }}</span>
        </div>
        <div class="text-xs leading-relaxed">{{ msg.content }}</div>
      </div>
      <!-- Reply button -->
      <button
        v-if="msg.direction === 'incoming'"
        @click="setReplyingTo(msg)"
        class="text-[9px] font-medium text-n-slate-11 hover:text-n-blue-11 bg-white px-2 py-0.5 rounded shadow-sm w-fit opacity-0 group-hover:opacity-100 transition-opacity"
      >
        ↩️ Reply
      </button>
    </div>
  `;
};

const fetchCommentQueue = async () => {
  isCommentLoading.value = true;
  try {
    const response = await AiControlAPI.listComments({
      status: commentStatusFilter.value || undefined,
      limit: commentLimit.value,
      offset: commentOffset.value,
    });
    const data = response?.data || {};
    commentQueue.value = Array.isArray(data.comments) ? data.comments : [];
    commentTotal.value = Number(data.total || 0);
  } catch (e) {
    commentQueue.value = [];
    useAlert('Không tải được danh sách comment.');
  } finally {
    isCommentLoading.value = false;
  }
};

const selectCommentConversation = (item) => {
  selectedCommentConversation.value = item;
  commentReplyText.value = '';
  replyingToComment.value = null;
  // Use embedded messages from the comments API response
  commentThread.value = Array.isArray(item.messages) ? item.messages : [];
};

const sendCommentReply = async () => {
  const text = commentReplyText.value.trim();
  if (!text || !selectedCommentConversation.value) return;
  // Use the selected comment to reply to, or fallback to last incoming
  const targetComment = replyingToComment.value || commentThread.value.filter(m => m.direction === 'incoming').slice(-1)[0];
  if (!targetComment) { useAlert('Không tìm thấy comment để reply.'); return; }
  isCommentReplying.value = true;
  try {
    await AiControlAPI.replyComment(targetComment.id, { message: text });
    commentReplyText.value = '';
    replyingToComment.value = null;
    useAlert('Đã gửi reply comment thành công.');
    await fetchCommentQueue();
    const updated = commentQueue.value.find(
      c => c.post_id === selectedCommentConversation.value.post_id
    );
    if (updated) selectCommentConversation(updated);
  } catch (e) {
    useAlert('Không thể gửi reply comment.');
  } finally {
    isCommentReplying.value = false;
  }
};

const triggerAutoReply = async (item) => {
  const target = item || selectedCommentConversation.value;
  if (!target) return;
  // Find the last incoming comment to trigger auto-reply on
  const msgs = target.messages || [];
  const lastIncoming = msgs.filter(m => m.direction === 'incoming').slice(-1)[0];
  if (!lastIncoming) { useAlert('Không tìm thấy comment để auto-reply.'); return; }
  isCommentAutoReplying.value = true;
  try {
    const response = await AiControlAPI.autoReplyComment(lastIncoming.id);
    const usedWebhookUrl = String(response?.data?.webhook_url || '').trim();
    if (usedWebhookUrl) {
      useAlert(`Đã gửi yêu cầu auto-reply qua ${usedWebhookUrl}`);
    } else {
      useAlert('Đã gửi yêu cầu auto-reply. AI sẽ phản hồi trong giây lát.');
    }
  } catch (e) {
    useAlert('Không thể trigger auto-reply.');
  } finally {
    isCommentAutoReplying.value = false;
  }
};

const commentTimeAgo = (iso) => {
  if (!iso) return '';
  try {
    const diff = Date.now() - new Date(iso).getTime();
    const mins = Math.floor(diff / 60000);
    if (mins < 1) return 'vừa xong';
    if (mins < 60) return `${mins} phút trước`;
    const hours = Math.floor(mins / 60);
    if (hours < 24) return `${hours} giờ trước`;
    const days = Math.floor(hours / 24);
    return `${days} ngày trước`;
  } catch {
    return '';
  }
};

const initializeMainTab = async tab => {
  const normalizedTab = String(tab || '').trim();
  if (!normalizedTab) return;

  const isFirstVisit = !hasMountedMainTab(normalizedTab);
  markMainTabAsMounted(normalizedTab);

  if (normalizedTab === 'reporting') {
    await loadChartJs();
    if (isFirstVisit) {
      await fetchAiGrowthSeries();
    }
    return;
  }

  if (!isFirstVisit) return;

  if (normalizedTab === 'comment') {
    await fetchCommentQueue();
  }

  if (normalizedTab === 'aftercare') {
    await fetchAftercareEnrollments();
  }
};

watch(activeMainTab, async (tab, previousTab) => {
  if (previousTab) {
    saveMainTabScrollPosition(previousTab);
  }

  await initializeMainTab(tab);
  await nextTick();

  if (tab === 'reporting') {
    renderCharts();
    await nextTick();
  }

  restoreMainTabScrollPosition(tab);
});

watch([trackedLabelRows, aiGrowthSeries], () => {
  if (activeMainTab.value === 'reporting') {
    nextTick(() => renderCharts());
  }
});

watch(
  () => aiControlConversationId.value,
  async conversationId => {
    if (activeMainTab.value !== 'operations') return;
    await fetchCustomer360(conversationId);
  },
  { immediate: true }
);

onMounted(() => {
  fetchManagerQueues();
  fetchPaymentReviewCases();
  fetchBlockedInboxes();
  store.dispatch('inboxes/get');
  store.dispatch('labels/get');
  emitter.on(
    'ai_control_panel:refresh_live_conversations',
    onRefreshLiveConversations
  );
  // Fetch happens after the first filter event
});

onBeforeUnmount(() => {
  if (realtimeOperationsRefreshTimer) {
    window.clearTimeout(realtimeOperationsRefreshTimer);
    realtimeOperationsRefreshTimer = null;
  }
  emitter.off(
    'ai_control_panel:refresh_live_conversations',
    onRefreshLiveConversations
  );
});
</script>

<template>
  <div ref="panelScrollContainer" class="overflow-auto bg-n-background w-full px-6">
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

      <div class="pb-6">
        <!-- Main Tabs Switcher -->
        <div class="flex items-center justify-center mb-6">
          <div
            class="inline-flex items-center rounded-xl bg-n-solid-2 p-1 border border-n-slate-3 shadow-sm"
          >
            <button
              data-test-id="ai-control-tab-operations"
              class="flex items-center gap-2 rounded-lg px-6 py-2.5 text-sm font-semibold transition-all duration-200"
              :class="
                activeMainTab === 'operations'
                  ? 'bg-n-background text-n-slate-12 shadow ring-1 ring-n-slate-4/50'
                  : 'text-n-slate-11 hover:text-n-slate-12 hover:bg-n-slate-3/50'
              "
              @click="activeMainTab = 'operations'"
            >
              <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="2" y="3" width="20" height="14" rx="2" /><line x1="8" y1="21" x2="16" y2="21" /><line x1="12" y1="17" x2="12" y2="21" /></svg>
              <span>Vận hành Hệ thống</span>
            </button>
            <button
              data-test-id="ai-control-tab-reporting"
              class="flex items-center gap-2 rounded-lg px-6 py-2.5 text-sm font-semibold transition-all duration-200"
              :class="
                activeMainTab === 'reporting'
                  ? 'bg-n-background text-n-blue-11 shadow ring-1 ring-n-blue-4/50'
                  : 'text-n-slate-11 hover:text-n-slate-12 hover:bg-n-slate-3/50'
              "
              @click="activeMainTab = 'reporting'"
            >
              <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><line x1="18" y1="20" x2="18" y2="10" /><line x1="12" y1="20" x2="12" y2="4" /><line x1="6" y1="20" x2="6" y2="14" /></svg>
              <span>Báo cáo</span>
            </button>
            <button
              data-test-id="ai-control-tab-comment"
              class="flex items-center gap-2 rounded-lg px-6 py-2.5 text-sm font-semibold transition-all duration-200"
              :class="
                activeMainTab === 'comment'
                  ? 'bg-n-background text-n-teal-11 shadow ring-1 ring-n-teal-4/50'
                  : 'text-n-slate-11 hover:text-n-slate-12 hover:bg-n-slate-3/50'
              "
              @click="activeMainTab = 'comment'"
            >
              <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/></svg>
              <span>Comment</span>
            </button>
            <button
              data-test-id="ai-control-tab-aftercare"
              class="flex items-center gap-2 rounded-lg px-6 py-2.5 text-sm font-semibold transition-all duration-200"
              :class="
                activeMainTab === 'aftercare'
                  ? 'bg-n-background text-n-violet-11 shadow ring-1 ring-n-violet-4/50'
                  : 'text-n-slate-11 hover:text-n-slate-12 hover:bg-n-slate-3/50'
              "
              @click="activeMainTab = 'aftercare'"
            >
              <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 2v20"/><path d="M2 12h20"/></svg>
              <span>Tư vấn sau mua</span>
            </button>
          </div>
        </div>

        <!-- TAB: VẬN HÀNH -->
        <div
          v-if="hasMountedMainTab('operations')"
          v-show="activeMainTab === 'operations'"
          class="flex flex-col gap-6"
        >
            <!-- Risk Banner -->
            <div
              v-if="isRiskBannerVisible"
              class="sticky top-4 z-50 rounded-2xl shadow-lg border border-n-ruby-4 px-5 py-4 transition-all duration-300 backdrop-blur-md"
              :class="
                isRiskBannerBlinking
                  ? 'bg-n-ruby-3/90 text-n-ruby-12 animate-pulse ring-4 ring-n-ruby-3/30'
                  : 'bg-n-ruby-2/90 text-n-ruby-12'
              "
            >
              <div class="flex items-center justify-between gap-4">
                <div class="flex items-center gap-3">
                  <div class="relative flex h-3 w-3">
                    <span
                      class="animate-ping absolute inline-flex h-full w-full rounded-full bg-n-ruby-9 opacity-75"
                    ></span>
                    <span
                      class="relative inline-flex rounded-full h-3 w-3 bg-n-ruby-9"
                    ></span>
                  </div>
                  <div class="text-sm font-semibold tracking-wide">
                    {{ riskBannerText }}
                  </div>
                </div>
                <Button
                  color="ruby"
                  size="sm"
                  class="h-9 font-medium shadow-sm transition-transform active:scale-95"
                  :is-loading="isLiveConversationsLoading"
                  label="Làm mới"
                  @click="fetchLiveConversations"
                />
              </div>
            </div>

            <div
              class="rounded-2xl outline outline-1 outline-n-slate-4 bg-n-solid-1 shadow-sm overflow-hidden"
            >
              <div class="px-6 py-5 border-b border-n-slate-3 bg-n-solid-2">
                <div class="flex flex-wrap items-center justify-between gap-4">
                  <div class="flex flex-col gap-1">
                    <div class="text-lg font-semibold tracking-tight text-n-slate-12">
                      Đang chờ nhân viên phản hồi
                    </div>
                    <div class="text-sm font-medium text-n-slate-11/80">
                      Chỉ giữ lại các hội thoại có nhãn `handoff` và chưa có phản hồi công khai mới sau khi chuyển cho nhân viên.
                    </div>
                  </div>
                  <Button
                    color="slate"
                    size="sm"
                    class="h-9 shadow-sm"
                    :is-loading="isManagerQueuesLoading"
                    label="Làm mới danh sách"
                    @click="fetchManagerQueues"
                  />
                </div>
              </div>

              <div class="p-6 flex flex-col gap-4">
                <div
                  v-if="managerQueuesError"
                  class="rounded-xl border border-n-ruby-4 bg-n-ruby-2 px-4 py-3 text-sm font-medium text-n-ruby-11"
                >
                  {{ managerQueuesError }}
                </div>

                <div class="rounded-2xl border border-n-ruby-4 bg-n-ruby-2/60 px-4 py-4">
                  <div class="text-[11px] font-semibold uppercase tracking-wide text-n-ruby-11">
                    Danh sách hiện tại
                  </div>
                  <div class="mt-2 text-3xl font-bold text-n-ruby-12">
                    {{ managerAiHandoffQueue.length.toLocaleString() }}
                  </div>
                  <div class="mt-1 text-sm text-n-ruby-11">
                    {{ managerAiHandoffQueue.length ? 'Hội thoại cần nhân viên phản hồi ngay' : 'Hiện không có hội thoại nào đang chờ' }}
                  </div>
                </div>

                <div class="rounded-2xl border border-n-slate-3 bg-n-solid-2/40 p-5">
                  <div class="text-sm font-semibold text-n-slate-12">
                    Danh sách đang chờ phản hồi
                  </div>
                  <div class="mt-1 text-xs text-n-slate-11">
                    Chỉ hiển thị các hội thoại còn nhãn `handoff` và tin nhắn khách gần nhất chưa có phản hồi công khai mới hơn.
                  </div>

                  <div
                    class="mt-4 flex max-h-[30.25rem] flex-col gap-3 overflow-y-auto pr-2"
                  >
                    <button
                      v-for="item in managerAiHandoffQueue"
                      :key="`handoff-${item.conversation_id}`"
                      class="h-28 rounded-xl border border-n-slate-3 bg-n-solid-1 px-4 py-3 text-left transition-all hover:-translate-y-0.5 hover:border-n-ruby-4 hover:shadow-sm"
                      @click="openAiControlConversation(item.conversation_id)"
                    >
                      <div class="flex items-start justify-between gap-3">
                        <div class="min-w-0">
                          <div class="truncate text-sm font-semibold text-n-slate-12">
                            {{ queueItemTitle(item) }}
                          </div>
                          <div class="mt-1 text-xs text-n-slate-11">
                            {{ item.topic_guess || 'Chưa rõ chủ đề' }} · chờ {{ formatQueueAge(item.waiting_minutes) }}
                          </div>
                        </div>
                        <span class="rounded-full bg-n-ruby-3 px-2.5 py-1 text-[11px] font-semibold text-n-ruby-12">
                          {{ queueReasonLabel(item.handoff_reason) }}
                        </span>
                      </div>
                      <div class="mt-2 text-sm text-n-slate-11 line-clamp-2">
                        {{ item.issue_summary || item.last_customer_message || 'Chưa có tóm tắt' }}
                      </div>
                    </button>

                    <div
                      v-if="!managerAiHandoffQueue.length && !isManagerQueuesLoading"
                      class="rounded-xl border border-dashed border-n-slate-4 px-4 py-6 text-center text-sm text-n-slate-11"
                    >
                      Không có hội thoại nào đang chờ nhân viên phản hồi.
                    </div>
                  </div>
                </div>
              </div>
            </div>

            <!-- ===== SECTION 1: Bảng chờ xác minh thanh toán (CHÍNH) ===== -->
            <div
              class="rounded-2xl outline outline-1 outline-n-slate-4 bg-n-solid-1 shadow-sm overflow-hidden"
            >
              <div class="px-6 py-5 border-b border-n-slate-3 bg-n-solid-2">
                <div class="flex flex-wrap items-center justify-between gap-4">
                  <div class="flex flex-col gap-1">
                    <div
                      class="text-lg font-semibold tracking-tight text-n-slate-12"
                    >
                      💳 Bảng chờ xác minh thanh toán
                    </div>
                    <div class="text-sm font-medium text-n-slate-11/80">
                      {{ paymentReviewTotal.toLocaleString() }} ca đang chờ ·
                      Tổng giá trị: {{ paymentTotalAmountText }}
                    </div>
                  </div>
                  <div class="flex items-center gap-3">
                    <select
                      v-model="paymentReviewSegment"
                      class="h-9 rounded-lg outline outline-1 outline-n-weak bg-n-background px-3 text-sm font-medium text-n-slate-12 transition-all hover:outline-n-slate-6 focus:outline-n-blue-6"
                      @change="fetchPaymentReviewCases"
                    >
                      <option value="all">Tất cả lĩnh vực</option>
                      <option value="online_course">Khóa online</option>
                      <option value="offline_course">Khóa trực tiếp</option>
                      <option value="pmu_tool">Công cụ PMU</option>
                    </select>
                    <Button
                      color="slate"
                      size="sm"
                      class="h-9 shadow-sm"
                      :is-loading="isPaymentReviewLoading"
                      label="Làm mới"
                      @click="fetchPaymentReviewCases"
                    />
                  </div>
                </div>
              </div>
              <div ref="paymentReviewTableContainer" class="overflow-x-auto overflow-y-auto max-h-[32rem]" @scroll="handleTableScroll">
                <table class="min-w-full divide-y divide-n-slate-3">
                  <thead class="bg-n-solid-2/50 backdrop-blur-sm">
                    <tr
                      class="text-left text-xs font-semibold uppercase tracking-wider text-n-slate-11"
                    >
                      <th class="px-6 py-3">Khách hàng</th>
                      <th class="px-6 py-3">Thông tin liên hệ</th>
                      <th class="px-6 py-3">Địa chỉ/Giao hàng</th>
                      <th class="px-6 py-3">Hạng mục mua</th>
                      <th class="px-6 py-3">Số item</th>
                      <th class="px-6 py-3">Giá trị dự kiến</th>
                      <th class="px-6 py-3">Ghi chú</th>
                      <th class="px-6 py-3">Thông tin đơn hàng</th>
                      <th class="px-6 py-3">Trạng thái</th>
                      <th class="px-6 py-3 text-right">Thao tác</th>
                    </tr>
                  </thead>
                  <tbody class="divide-y divide-n-slate-3 bg-n-solid-1">
                    <tr v-if="isPaymentReviewLoading">
                      <td
                        colspan="7"
                        class="py-8 text-center text-sm text-n-slate-11"
                      >
                        <div class="flex items-center justify-center gap-2">
                          <div
                            class="w-4 h-4 rounded-full border-2 border-n-blue-9 border-t-transparent animate-spin"
                          ></div>
                          Đang tải hàng chờ xác minh...
                        </div>
                      </td>
                    </tr>
                    <tr v-else-if="paymentReviewLastError">
                      <td
                        colspan="7"
                        class="py-8 text-center text-sm font-medium text-n-ruby-11"
                      >
                        {{ paymentReviewLastError }}
                      </td>
                    </tr>
                    <tr v-else-if="!paymentReviewCases.length">
                      <td colspan="7" class="py-12 text-center">
                        <div class="text-sm font-medium text-n-slate-12">
                          Không có dữ liệu
                        </div>
                        <div class="mt-1 text-xs text-n-slate-11">
                          Chưa có ca nào trong hàng chờ xác minh.
                        </div>
                      </td>
                    </tr>
                    <template v-else>
                      <tr
                        v-for="item in sortedPaymentReviewCases"
                        :key="item.id"
                        class="group align-middle cursor-pointer transition-colors hover:bg-n-slate-2/50"
                        @click="openPaymentConversation(item)"
                      >
                        <td class="px-6 py-4">
                          <div class="flex items-center gap-3">
                            <Avatar
                              :name="paymentContactName(item)"
                              :src="paymentContactAvatar(item)"
                              :size="36"
                              rounded-full
                              class="ring-2 ring-white"
                            />
                            <div class="min-w-0">
                              <div
                                class="truncate text-sm font-semibold text-n-slate-12 group-hover:text-n-blue-11 transition-colors"
                              >
                                {{ paymentContactName(item) }}
                              </div>
                              <div
                                class="mt-0.5 text-xs text-n-slate-11 group-hover:text-n-slate-12 transition-colors"
                              >
                                {{ paymentConversationSubtext(item) }}
                              </div>
                            </div>
                          </div>
                        </td>
                        <td class="px-6 py-4">
                          <div class="text-sm text-n-slate-12">
                            <div v-if="item.metadata?.phone || item.metadata?.contact_phone">📞 {{ item.metadata?.phone || item.metadata?.contact_phone }}</div>
                            <div v-if="item.metadata?.email || item.metadata?.contact_email">✉️ {{ item.metadata?.email || item.metadata?.contact_email }}</div>
                            <div v-if="!item.metadata?.phone && !item.metadata?.contact_phone && !item.metadata?.email && !item.metadata?.contact_email" class="text-n-slate-10 italic">Không có</div>
                          </div>
                        </td>
                        <td class="px-6 py-4 text-sm text-n-slate-12 max-w-[200px] truncate" :title="item.metadata?.address || item.metadata?.shipping_address || '--'">
                          {{ item.metadata?.address || item.metadata?.shipping_address || '--' }}
                        </td>
                        <td class="px-6 py-4">
                          <div class="flex flex-wrap gap-2">
                            <span
                              v-for="segment in paymentSegments(item)"
                              :key="`${item.id}-${segment}`"
                              class="inline-flex items-center rounded-md px-2.5 py-1 text-[11px] font-semibold tracking-wide uppercase"
                              :class="paymentSegmentBadgeClass(segment)"
                            >
                              {{ paymentSegmentLabel(segment) }}
                            </span>
                          </div>
                        </td>
                        <td
                          class="px-6 py-4 text-sm font-medium text-n-slate-12"
                        >
                          {{ paymentItemCountText(item) }}
                        </td>
                        <td
                          class="px-6 py-4 text-sm font-semibold text-n-slate-12"
                        >
                          {{ paymentAmountText(item) }}
                        </td>
                        <td
                          class="px-6 py-4 text-sm text-n-slate-11 max-w-[200px] truncate"
                          :title="paymentNoteText(item)"
                        >
                          {{ paymentNoteText(item) }}
                        </td>
                        <td class="px-6 py-4">
                          <div class="flex flex-col gap-1.5 max-w-[220px]">
                            <div class="text-xs text-n-slate-12 space-y-1">
                              <div v-if="item.items && item.items.length" class="font-medium">
                                {{ item.items.length }} sản phẩm
                              </div>
                              <div v-else-if="item.item_count" class="font-medium">
                                {{ item.item_count }} item(s)
                              </div>
                              <div v-if="item.metadata?.order_items?.length" class="text-n-slate-11 line-clamp-2">
                                {{ item.metadata.order_items.map(oi => oi.sku || oi.name || oi.segment).filter(Boolean).join(', ') || 'Đơn hàng' }}
                              </div>
                              <div v-else-if="item.metadata?.product_name" class="text-n-slate-11 line-clamp-2">
                                {{ item.metadata.product_name }}
                              </div>
                              <div v-else-if="item.metadata?.items?.length" class="text-n-slate-11 line-clamp-2">
                                {{ item.metadata.items.map(i => i.name || i.sku).filter(Boolean).join(', ') || 'Đơn hàng' }}
                              </div>
                              <div v-else-if="item.metadata?.order_code || item.metadata?.order_id" class="text-n-slate-11">
                                Mã: {{ item.metadata.order_code || item.metadata.order_id }}
                              </div>
                              <div v-else class="text-n-slate-10 italic text-[11px]">
                                Không có thông tin
                              </div>
                            </div>
                            <button
                              v-if="item.metadata && Object.keys(item.metadata).length > 0"
                              @click.stop="openMetadataModal(item)"
                              class="text-n-blue-11 hover:text-n-blue-12 hover:underline text-[11px] font-medium w-fit"
                            >
                              Xem chi tiết
                            </button>
                          </div>
                        </td>
                        <td class="px-6 py-4">
                          <span
                            class="inline-flex items-center rounded-full px-2.5 py-1 text-xs font-semibold ring-1 ring-inset"
                            :class="
                              (item.review_status || '').includes('verified')
                                ? 'bg-n-teal-3 text-n-teal-12 ring-n-teal-5'
                                : (item.review_status || '').includes('rejected')
                                  ? 'bg-n-ruby-3 text-n-ruby-12 ring-n-ruby-5'
                                  : 'bg-n-amber-3 text-n-amber-12 ring-n-amber-5'
                            "
                          >
                            {{
                              (item.review_status || '').includes('verified')
                                ? '✅ Đã xác nhận'
                                : (item.review_status || '').includes('rejected')
                                  ? '❌ Từ chối'
                                  : '⏳ Chờ xác nhận'
                            }}
                          </span>
                        </td>
                        <td class="px-6 py-4 text-right">
                          <div
                            v-if="
                              !(item.review_status || '').includes('verified') &&
                              !(item.review_status || '').includes('rejected')
                            "
                            class="flex items-center justify-end gap-2"
                          >
                            <Button
                              color="teal"
                              size="sm"
                              class="h-8 shadow-sm transition-transform active:scale-95"
                              label="Xác nhận"
                              :is-loading="isPaymentCaseActionLoading(item.id)"
                              :disabled="isPaymentCaseActionLoading(item.id)"
                              @click.stop="confirmPaymentCase(item)"
                            />
                            <Button
                              color="ruby"
                              variant="faded"
                              size="sm"
                              class="h-8 shadow-sm"
                              label="Xóa"
                              :disabled="isPaymentCaseActionLoading(item.id)"
                              @click.stop="deletePaymentCase(item)"
                            />
                          </div>
                          <span
                            v-else
                            class="text-xs text-n-slate-10"
                          >
                            {{ paymentContactName(item) }}
                          </span>
                        </td>
                      </tr>
                    </template>
                    <!-- Loading Indicator for Infinite Scroll -->
                    <tr v-if="isPaymentReviewLoadingMore">
                      <td colspan="10" class="py-4 text-center text-sm text-n-slate-11">
                        <div class="flex items-center justify-center gap-2">
                          <div class="w-4 h-4 rounded-full border-2 border-n-blue-9 border-t-transparent animate-spin"></div>
                          Đang tải thêm...
                        </div>
                      </td>
                    </tr>
                    <tr v-if="!paymentReviewHasMore && paymentReviewCases.length > 0">
                      <td colspan="10" class="py-4 text-center text-xs text-n-slate-10 italic border-t border-n-slate-3">
                        Đã tải hết danh sách
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
              <div
                class="px-6 py-4 border-t border-n-slate-3 bg-n-solid-2/50 flex justify-between items-center text-xs font-medium text-n-slate-11"
              >
                <span>Đang hiển thị {{ paymentReviewCases.length }} / {{ paymentReviewCount.toLocaleString() }} bản ghi.</span>
                <span v-if="isPaymentReviewLoadingMore" class="text-n-blue-11 animate-pulse">Đang rải thêm...</span>
              </div>
            </div>

            <!-- Metadata Detail Modal -->
            <woot-modal :show.sync="showMetadataModal" :on-close="closeMetadataModal">
              <div class="p-6 max-w-lg">
                <h3 class="text-lg font-semibold text-n-slate-12 mb-4">Chi tiết đơn hàng</h3>
                <div v-if="selectedMetadataItem" class="space-y-5">
                  <!-- Thông tin người mua -->
                  <div class="bg-n-slate-2 rounded-xl p-4 border border-n-slate-4">
                    <div class="text-xs font-bold uppercase text-n-slate-10 mb-3 tracking-wider flex items-center gap-2">
                      <span>👤</span> Thông tin người mua
                    </div>
                    <div class="space-y-2 text-sm">
                      <div class="flex justify-between">
                        <span class="text-n-slate-11">Họ tên:</span>
                        <span class="font-medium text-n-slate-12">{{ selectedMetadataItem.contact_name || selectedMetadataItem.metadata?.contact_name || selectedMetadataItem.metadata?.customer_name || '—' }}</span>
                      </div>
                      <div class="flex justify-between">
                        <span class="text-n-slate-11">Điện thoại:</span>
                        <span class="font-medium text-n-slate-12">{{ selectedMetadataItem.metadata?.phone || selectedMetadataItem.metadata?.contact_phone || '—' }}</span>
                      </div>
                      <div class="flex justify-between">
                        <span class="text-n-slate-11">Email:</span>
                        <span class="font-medium text-n-slate-12">{{ selectedMetadataItem.metadata?.email || selectedMetadataItem.metadata?.contact_email || '—' }}</span>
                      </div>
                      <div class="flex justify-between">
                        <span class="text-n-slate-11">Địa chỉ:</span>
                        <span class="font-medium text-n-slate-12 text-right max-w-[200px]">{{ selectedMetadataItem.metadata?.address || selectedMetadataItem.metadata?.shipping_address || '—' }}</span>
                      </div>
                    </div>
                  </div>

                  <!-- Thông tin đơn hàng -->
                  <div class="bg-n-slate-2 rounded-xl p-4 border border-n-slate-4">
                    <div class="text-xs font-bold uppercase text-n-slate-10 mb-3 tracking-wider flex items-center gap-2">
                      <span>📦</span> Thông tin đơn hàng
                    </div>
                    <div class="space-y-3">
                      <!-- Danh sách sản phẩm từ items hoặc order_items -->
                      <div v-if="(selectedMetadataItem.items?.length || selectedMetadataItem.metadata?.order_items?.length)" class="space-y-2">
                        <div
                          v-for="(item, i) in (selectedMetadataItem.items || selectedMetadataItem.metadata?.order_items || [])"
                          :key="i"
                          class="bg-n-solid-1 rounded-lg p-3 border border-n-slate-3"
                        >
                          <div class="flex justify-between items-start mb-2">
                            <span class="font-semibold text-n-slate-12">{{ item.sku || item.name || item.item_id || `Item ${i + 1}` }}</span>
                            <span class="text-xs px-2 py-0.5 rounded bg-n-blue-3 text-n-blue-12">{{ item.segment || selectedMetadataItem.segment }}</span>
                          </div>
                          <div class="grid grid-cols-2 gap-x-4 gap-y-1 text-xs text-n-slate-11">
                            <div v-if="item.quantity">Số lượng: <span class="font-medium text-n-slate-12">{{ item.quantity }}</span></div>
                            <div v-if="item.unit_price">Đơn giá: <span class="font-medium text-n-slate-12">{{ item.unit_price }}</span></div>
                            <div v-if="item.line_amount">Thành tiền: <span class="font-medium text-n-slate-12">{{ item.line_amount }}</span></div>
                            <div v-if="item.fulfillment_status">Trạng thái: <span class="font-medium text-n-slate-12">{{ item.fulfillment_status }}</span></div>
                          </div>
                        </div>
                      </div>
                      <div v-else class="text-sm text-n-slate-10 italic">Không có chi tiết sản phẩm</div>

                      <!-- Tổng giá trị -->
                      <div class="pt-3 border-t border-n-slate-3 flex justify-between items-center">
                        <span class="text-sm font-medium text-n-slate-11">Tổng giá trị:</span>
                        <span class="text-base font-bold text-n-slate-12">{{ selectedMetadataItem.expected_amount_total || selectedMetadataItem.expected_amount }} {{ selectedMetadataItem.currency }}</span>
                      </div>

                      <!-- Ghi chú đơn hàng -->
                      <div v-if="selectedMetadataItem.note || selectedMetadataItem.metadata?.note" class="pt-2 text-sm">
                        <span class="text-n-slate-11">Ghi chú:</span>
                        <span class="text-n-slate-12 ml-1">{{ selectedMetadataItem.note || selectedMetadataItem.metadata?.note }}</span>
                      </div>
                    </div>
                  </div>
                </div>
                <div class="mt-6 flex justify-end">
                  <Button @click="closeMetadataModal" label="Đóng" color="slate" variant="smooth" />
                </div>
              </div>
            </woot-modal>

            <!-- ===== SECTION 2: Hội thoại (CHÍNH) + Sidebar tools ===== -->
            <div
              ref="conversationSectionRef"
              class="grid gap-6 lg:grid-cols-12 lg:items-start"
            >
              <!-- ConversationView — chiếm 8/12 cột -->
              <div
                class="lg:col-span-8 xl:col-span-9 self-start rounded-2xl outline outline-1 outline-n-slate-4 bg-n-solid-1 shadow-sm overflow-hidden"
              >
                <div class="h-[52rem] bg-n-solid-2">
                  <ConversationView
                    :inbox-id="0"
                    :conversation-id="aiControlConversationId"
                    force-two-pane
                  />
                </div>
              </div>

              <!-- Sidebar tools — 4/12 cột -->
              <div class="lg:col-span-4 xl:col-span-3 flex flex-col gap-5">
                <div
                  class="rounded-2xl outline outline-1 outline-n-slate-4 bg-n-solid-1 shadow-sm overflow-hidden"
                >
                  <div class="px-5 py-4 border-b border-n-slate-3 bg-n-solid-2">
                    <div class="flex items-center justify-between gap-3">
                      <div>
                        <div class="text-base font-semibold tracking-tight text-n-slate-12">
                          Customer 360
                        </div>
                        <div class="mt-0.5 text-xs text-n-slate-11">
                          Hồ sơ nhanh của hội thoại đang mở
                        </div>
                      </div>
                      <Button
                        color="slate"
                        size="sm"
                        class="h-8"
                        :is-loading="isCustomer360Loading"
                        label="Làm mới"
                        @click="fetchCustomer360(aiControlConversationId)"
                      />
                    </div>
                    <Button
                      v-if="hasSelectedConversation"
                      data-test-id="aftercare-open-dialog"
                      color="blue"
                      size="sm"
                      class="mt-3 h-9 w-full"
                      label="Tư vấn sau mua"
                      @click="openAftercareDialog"
                    />
                  </div>

                  <div class="p-5 flex flex-col gap-4">
                    <div
                      v-if="!hasSelectedConversation"
                      class="rounded-xl border border-dashed border-n-slate-4 px-4 py-6 text-center text-sm text-n-slate-11"
                    >
                      Chọn một hội thoại ở panel để xem hồ sơ 360.
                    </div>

                    <div
                      v-else-if="isCustomer360Loading"
                      class="flex items-center justify-center py-6 text-sm text-n-slate-11"
                    >
                      <div class="w-4 h-4 rounded-full border-2 border-n-blue-9 border-t-transparent animate-spin"></div>
                      <span class="ml-2">Đang tải hồ sơ...</span>
                    </div>

                    <div
                      v-else-if="customer360Error"
                      class="rounded-xl border border-n-ruby-4 bg-n-ruby-2 px-4 py-3 text-sm font-medium text-n-ruby-11"
                    >
                      {{ customer360Error }}
                    </div>

                    <template v-else-if="customer360">
                      <div class="flex items-center gap-3">
                        <Avatar
                          :name="customer360.contact_profile?.name || customer360.contact_id || 'Khách hàng'"
                          :src="customer360.contact_profile?.avatar_url"
                          :size="40"
                          rounded-full
                        />
                        <div class="min-w-0">
                          <div class="truncate text-sm font-semibold text-n-slate-12">
                            {{ customer360.contact_profile?.name || customer360.contact_id || 'Khách hàng' }}
                          </div>
                          <div class="mt-0.5 text-xs text-n-slate-11">
                            #{{ customer360.conversation?.display_id || customer360.conversation_id }} · {{ customer360.topic_guess || 'Chưa rõ chủ đề' }}
                          </div>
                        </div>
                      </div>

                      <div class="grid grid-cols-2 gap-3 text-xs text-n-slate-11">
                        <div class="rounded-xl bg-n-slate-2 px-3 py-2">
                          <div class="font-semibold text-n-slate-12">Điện thoại</div>
                          <div class="mt-1 break-words">{{ customer360.contact_profile?.phone_number || '—' }}</div>
                        </div>
                        <div class="rounded-xl bg-n-slate-2 px-3 py-2">
                          <div class="font-semibold text-n-slate-12">Email</div>
                          <div class="mt-1 break-words">{{ customer360.contact_profile?.email || '—' }}</div>
                        </div>
                      </div>

                      <div class="rounded-xl bg-n-slate-2 px-4 py-3">
                        <div class="text-xs font-semibold uppercase tracking-wide text-n-slate-10">
                          Vấn đề hiện tại
                        </div>
                        <div class="mt-2 text-sm text-n-slate-12">
                          {{ customer360.issue_summary || 'Chưa có tóm tắt vấn đề.' }}
                        </div>
                      </div>

                      <div
                        v-if="(customer360.conversation?.labels || []).length"
                        class="flex flex-wrap gap-2"
                      >
                        <span
                          v-for="label in customer360.conversation?.labels || []"
                          :key="`customer360-${label}`"
                          class="inline-flex items-center rounded-full bg-n-slate-3 px-2.5 py-1 text-[11px] font-semibold text-n-slate-12"
                        >
                          {{ labelDisplayName(label) }}
                        </span>
                      </div>

                      <div
                        v-if="customer360.recent_summary?.summary_text"
                        class="rounded-xl border border-n-teal-4 bg-n-teal-2/50 px-4 py-3"
                      >
                        <div class="text-[10px] font-bold uppercase tracking-wider text-n-teal-11">
                          Tóm tắt gần nhất
                        </div>
                        <div class="mt-2 text-sm text-n-slate-12 line-clamp-4">
                          {{ customer360.recent_summary.summary_text }}
                        </div>
                      </div>

                      <div class="grid grid-cols-1 gap-3">
                        <div
                          v-if="customer360.open_case"
                          class="rounded-xl border border-n-ruby-4 bg-n-ruby-2/50 px-4 py-3"
                        >
                          <div class="text-[10px] font-bold uppercase tracking-wider text-n-ruby-11">
                            Case nhân viên
                          </div>
                          <div class="mt-2 text-sm text-n-slate-12">
                            {{ customer360.open_case.handoff_reason || 'Đang chờ nhân viên xử lý' }}
                          </div>
                        </div>

                        <div
                          v-if="customer360.payment_review_case"
                          class="rounded-xl border border-n-amber-4 bg-n-amber-2/50 px-4 py-3"
                        >
                          <div class="text-[10px] font-bold uppercase tracking-wider text-n-amber-11">
                            Thanh toán
                          </div>
                          <div class="mt-2 text-sm text-n-slate-12">
                            {{ customer360.payment_review_case.review_status || 'payment_review_pending' }}
                          </div>
                        </div>
                      </div>

                      <div
                        v-if="(customer360.memories || []).length"
                        class="rounded-xl border border-n-slate-3 bg-n-solid-2/50 px-4 py-3"
                      >
                        <div class="text-[10px] font-bold uppercase tracking-wider text-n-slate-10">
                          Memories
                        </div>
                        <div class="mt-3 flex flex-col gap-2">
                          <div
                            v-for="(memory, index) in (customer360.memories || []).slice(0, 3)"
                            :key="`memory-${index}`"
                            class="rounded-lg bg-n-solid-1 px-3 py-2 text-xs text-n-slate-12"
                          >
                            <div class="font-semibold text-n-slate-11">
                              {{ memory.category || 'context' }}
                            </div>
                            <div class="mt-1 line-clamp-2">{{ memory.content }}</div>
                          </div>
                        </div>
                      </div>
                    </template>
                  </div>
                </div>

                <!-- Điều khiển AI theo kênh -->
                <div
                  class="rounded-2xl outline outline-1 outline-n-slate-4 bg-n-solid-1 shadow-sm overflow-hidden"
                >
                  <div class="px-5 py-4 border-b border-n-slate-3 bg-n-solid-2">
                    <div
                      class="text-base font-semibold tracking-tight text-n-slate-12"
                    >
                      🔌 Điều khiển AI theo kênh
                    </div>
                    <div class="mt-0.5 text-xs text-n-slate-11">
                      Dừng/Mở AI webhook cho từng kênh
                    </div>
                  </div>
                  <div class="p-5 flex flex-col gap-4">
                    <Button
                      :color="isAllBlocked ? 'blue' : 'ruby'"
                      size="sm"
                      class="h-10 w-full shadow-sm transition-transform active:scale-95"
                      :is-loading="isTakeoverAllLoading"
                      :label="isAllBlocked ? 'Mở AI tất cả kênh' : 'Dừng AI tất cả kênh'"
                      @click="toggleAllInboxBlock"
                    />
                    <div
                      class="text-[11px] leading-relaxed text-n-slate-11 bg-n-slate-2 p-3 rounded-xl border border-n-slate-3"
                    >
                      Trạng thái:
                      <span class="font-semibold" :class="isAllBlocked ? 'text-n-ruby-11' : 'text-n-teal-11'">{{
                        isAllBlocked ? 'Tất cả đã dừng' : 'Đang hoạt động'
                      }}</span>
                    </div>
                    <div
                      v-if="isBlockedInboxesLoading"
                      class="flex items-center justify-center py-4"
                    >
                      <div class="w-4 h-4 rounded-full border-2 border-n-blue-9 border-t-transparent animate-spin"></div>
                      <span class="ml-2 text-xs text-n-slate-11">Đang tải...</span>
                    </div>
                    <div v-else-if="!inboxList.length" class="text-xs text-n-slate-11 text-center py-4">
                      Không có kênh nào.
                    </div>
                    <div v-else class="flex flex-col gap-2">
                      <div
                        v-for="inbox in inboxList"
                        :key="inbox.id"
                        class="flex items-center justify-between rounded-xl px-3.5 py-2.5 transition-all duration-200 group"
                        :class="isInboxBlocked(inbox.id)
                          ? 'bg-n-ruby-2/60 outline outline-1 outline-n-ruby-4/50'
                          : 'bg-n-teal-2/40 outline outline-1 outline-n-teal-4/50 hover:bg-n-teal-2/70'"
                      >
                        <div class="flex items-center gap-2.5 min-w-0">
                          <span class="text-base flex-shrink-0">{{ channelIcon(inbox) }}</span>
                          <div class="min-w-0">
                            <div class="text-xs font-semibold text-n-slate-12 truncate">{{ inbox.name }}</div>
                            <div class="text-[10px] text-n-slate-11">{{ channelLabel(inbox) }}</div>
                          </div>
                        </div>
                        <button
                          class="relative flex-shrink-0 w-10 h-5.5 rounded-full transition-all duration-300 focus:outline-none focus:ring-2 focus:ring-offset-1"
                          :class="isInboxBlocked(inbox.id)
                            ? 'bg-n-ruby-6 focus:ring-n-ruby-4'
                            : 'bg-n-teal-8 focus:ring-n-teal-4'"
                          @click="toggleInboxBlock(inbox.id)"
                        >
                          <span
                            class="absolute top-0.5 block w-4.5 h-4.5 rounded-full bg-white shadow-sm transition-transform duration-300"
                            :class="isInboxBlocked(inbox.id) ? 'left-0.5' : 'left-[calc(100%-1.25rem)]'"
                          />
                        </button>
                      </div>
                    </div>
                  </div>
                </div>

                <!-- FAQ Training -->
                <div
                  class="rounded-2xl outline outline-1 outline-n-slate-4 bg-n-solid-1 shadow-sm overflow-hidden"
                >
                  <div class="px-5 py-4 border-b border-n-slate-3 bg-n-solid-2">
                    <div
                      class="text-base font-semibold tracking-tight text-n-slate-12"
                    >
                      📚 FAQ Training
                    </div>
                    <div class="mt-0.5 text-xs text-n-slate-11">
                      Quét lịch sử và cập nhật FAQ
                    </div>
                  </div>
                  <div class="p-5 flex flex-col gap-4">
                    <div class="flex flex-col gap-1.5">
                      <label
                        class="text-xs font-medium text-n-slate-12"
                        for="faq-training-days"
                      >
                        Số ngày quét
                      </label>
                      <input
                        id="faq-training-days"
                        v-model.number="faqTrainingDays"
                        type="number"
                        min="1"
                        max="365"
                        class="h-10 rounded-xl outline outline-1 outline-n-slate-4 bg-n-background px-3 text-sm font-medium text-n-slate-12 focus:outline-n-blue-6 focus:ring-2 focus:ring-n-blue-4/20 transition-all"
                      />
                    </div>
                    <Button
                      color="blue"
                      size="sm"
                      class="h-10 w-full shadow-sm transition-transform active:scale-95"
                      :is-loading="isFaqTrainingLoading"
                      label="Training FAQ ngay"
                      @click="runFaqTraining"
                    />
                    <div
                      v-if="faqTrainingReport"
                      class="rounded-xl outline outline-1 outline-n-teal-4 bg-n-teal-2/50 px-4 py-3 text-xs text-n-slate-12 shadow-sm flex flex-col gap-3"
                    >
                      <div>
                        <div
                          class="flex justify-between items-center pb-2 border-b border-n-teal-4/50 mb-2"
                        >
                          <span
                            class="font-semibold text-n-teal-11 uppercase tracking-wider text-[10px]"
                            >Trạng thái</span
                          >
                          <span
                            class="font-medium px-2 py-0.5 rounded bg-n-teal-3 text-n-teal-11"
                            >{{ faqTrainingReport.status || '--' }}</span
                          >
                        </div>
                        <div class="grid grid-cols-2 gap-2 mt-2 font-medium">
                          <div>Mới: <span class="text-n-blue-11">{{ Number(faqTrainingReport.published_count || 0).toLocaleString() }}</span></div>
                          <div>Trùng: <span class="text-n-amber-11">{{ Number(faqTrainingReport.duplicate_count || 0).toLocaleString() }}</span></div>
                          <div>Xung đột: <span class="text-n-ruby-11">{{ Number(faqTrainingReport.conflict_count || 0).toLocaleString() }}</span></div>
                          <div>Lỗi: <span class="text-n-slate-11">{{ Number(faqTrainingReport.error_count || 0).toLocaleString() }}</span></div>
                        </div>
                      </div>

                      <div v-if="faqTrainingReport.published_items?.length" class="mt-2 flex flex-col gap-2">
                        <div class="text-[10px] font-bold uppercase tracking-wider text-n-slate-11 mb-1">CÁC HỘI THOẠI FAQ ĐÃ HỌC</div>
                        <div class="flex flex-col gap-2 max-h-64 overflow-y-auto pr-1">
                          <div
                            v-for="item in faqTrainingReport.published_items"
                            :key="item.id"
                            class="bg-n-background outline outline-1 outline-n-slate-3 rounded-lg p-3 text-[11px] flex flex-col gap-1.5"
                          >
                            <div class="font-semibold text-n-blue-11 line-clamp-2" :title="item.question">Q: {{ item.question }}</div>
                            <div class="text-n-slate-11 line-clamp-3" :title="item.answer">A: {{ item.answer }}</div>
                            <div class="text-[9px] text-n-slate-10 mt-0.5 uppercase tracking-wider">
                              Nguồn: {{ item.source_type }} · Trạng thái: {{ item.status }}
                            </div>
                          </div>
                        </div>
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            </div>
        </div>

        <div
          v-if="hasMountedMainTab('aftercare')"
          v-show="activeMainTab === 'aftercare'"
          class="flex flex-col gap-6"
        >
            <div class="rounded-2xl outline outline-1 outline-n-slate-4 bg-n-solid-1 shadow-sm overflow-hidden">
              <div class="px-6 py-5 border-b border-n-slate-3 bg-n-solid-2">
                <div class="flex flex-wrap items-center justify-between gap-4">
                  <div>
                    <div class="text-lg font-semibold tracking-tight text-n-slate-12">
                      Tư vấn sau mua
                    </div>
                    <div class="mt-1 text-sm text-n-slate-11/80">
                      Theo dõi các kế hoạch tư vấn sau mua và trạng thái gửi Gmail ngoài 24 giờ trong TA AI TECH.
                    </div>
                  </div>
                  <div class="flex items-center gap-3">
                    <Button
                      v-if="hasSelectedConversation"
                      color="blue"
                      size="sm"
                      class="h-9"
                      label="Tạo từ hội thoại đang mở"
                      @click="openAftercareDialog"
                    />
                    <Button
                      color="slate"
                      size="sm"
                      class="h-9"
                      :is-loading="isAftercareLoading"
                      label="Làm mới"
                      @click="fetchAftercareEnrollments"
                    />
                  </div>
                </div>
              </div>

              <div class="p-6 flex flex-col gap-4">
                <div
                  v-if="aftercareLastError"
                  class="rounded-xl border border-n-ruby-4 bg-n-ruby-2 px-4 py-3 text-sm font-medium text-n-ruby-11"
                >
                  {{ aftercareLastError }}
                </div>

                <div
                  v-else-if="isAftercareLoading"
                  class="rounded-xl border border-dashed border-n-slate-4 px-4 py-10 text-center text-sm text-n-slate-11"
                >
                  Đang tải danh sách tư vấn sau mua...
                </div>

                <div
                  v-else-if="!aftercareEnrollments.length"
                  class="rounded-xl border border-dashed border-n-slate-4 px-4 py-10 text-center text-sm text-n-slate-11"
                >
                  Chưa có kế hoạch nào. Chọn một hội thoại rồi bấm `Tư vấn sau mua` để tạo kế hoạch đầu tiên.
                </div>

                <div v-else class="overflow-x-auto">
                  <table class="min-w-full divide-y divide-n-slate-3">
                    <thead class="bg-n-solid-2/50">
                      <tr class="text-left text-xs font-semibold uppercase tracking-wider text-n-slate-11">
                        <th class="px-4 py-3">Khách hàng</th>
                        <th class="px-4 py-3">Chuỗi chăm sóc</th>
                        <th class="px-4 py-3">Trạng thái kế hoạch</th>
                        <th class="px-4 py-3">Trạng thái Gmail</th>
                        <th class="px-4 py-3">Lần gửi kế tiếp</th>
                        <th class="px-4 py-3">Bản nháp</th>
                        <th class="px-4 py-3">Hành động</th>
                      </tr>
                    </thead>
                    <tbody class="divide-y divide-n-slate-3 bg-n-solid-1">
                      <tr
                        v-for="item in aftercareEnrollments"
                        :key="`aftercare-enrollment-${item.id}`"
                        class="cursor-pointer transition-colors hover:bg-n-slate-2/50"
                        @click="openAiControlConversation(item.conversation?.id || item.conversation_id || 0)"
                      >
                        <td class="px-4 py-4 text-sm text-n-slate-12">
                          <div class="font-semibold">{{ item.contact?.name || 'Khách hàng' }}</div>
                          <div class="mt-1 text-xs text-n-slate-11">
                            #{{ item.conversation?.display_id || item.conversation_id || '—' }}
                          </div>
                        </td>
                        <td class="px-4 py-4 text-sm text-n-slate-12">
                          {{ item.sequence?.name || item.aftercare_sequence?.name || '—' }}
                        </td>
                        <td class="px-4 py-4 text-sm text-n-slate-12">
                          {{ aftercareStatusText(item.status) }}
                        </td>
                        <td class="px-4 py-4 text-sm text-n-slate-12">
                          <div>{{ aftercareOptInText(item.opt_in_subscription?.status) }}</div>
                          <div
                            v-if="aftercareOptInWarningText(item)"
                            class="mt-1 text-xs leading-5 text-n-ruby-11"
                          >
                            {{ aftercareOptInWarningText(item) }}
                          </div>
                        </td>
                        <td class="px-4 py-4 text-sm text-n-slate-12">
                          {{ aftercareNextSendText(item) }}
                        </td>
                        <td
                          class="px-4 py-4 text-sm text-n-slate-12 align-top"
                          @click.stop
                        >
                          <div class="flex flex-col gap-3 min-w-[280px]">
                            <div
                              v-for="step in item.steps || []"
                              :key="`aftercare-draft-${item.id}-${step.id || step.position}`"
                              class="rounded-xl border border-n-slate-3 bg-n-solid-2/40 px-3 py-2"
                            >
                              <div class="flex items-center justify-between gap-3">
                                <div class="text-xs font-semibold text-n-slate-12">
                                  B{{ step.position || '—' }} · {{ step.title || 'Bước' }}
                                </div>
                                <div class="text-right text-[11px] text-n-slate-10">
                                  <div>{{ aftercareDraftStatusText(step.draft_status) }}</div>
                                  <div class="mt-0.5">{{ aftercareStepStatusText(step.status) }}</div>
                                </div>
                              </div>
                              <div
                                v-if="isAftercareDraftEditing(item.id, step.id)"
                                class="mt-2"
                              >
                                <textarea
                                  :data-test-id="`aftercare-edit-input-${item.id}-${step.id}`"
                                  class="min-h-[92px] w-full rounded-lg border border-n-slate-4 bg-white px-3 py-2 text-xs leading-5 text-n-slate-12 outline-none transition focus:border-n-blue-6"
                                  :value="getAftercareDraftEditValue(item.id, step.id)"
                                  @click.stop
                                  @input="
                                    setAftercareDraftEditValue(
                                      item.id,
                                      step.id,
                                      $event.target.value
                                    )
                                  "
                                />
                                <div class="mt-2 flex items-center gap-2">
                                  <button
                                    type="button"
                                    class="rounded-lg border border-n-blue-4 bg-n-blue-2 px-3 py-1.5 text-xs font-semibold text-n-blue-11 transition hover:bg-n-blue-3 disabled:cursor-not-allowed disabled:opacity-60"
                                    :data-test-id="`aftercare-edit-save-${item.id}-${step.id}`"
                                    :disabled="isAftercareDraftSaving(item.id, step.id)"
                                    @click.stop="saveAftercareDraftEdit(item.id, step.id)"
                                  >
                                    {{
                                      isAftercareDraftSaving(item.id, step.id)
                                        ? 'Đang lưu...'
                                        : 'Lưu nội dung'
                                    }}
                                  </button>
                                  <button
                                    type="button"
                                    class="rounded-lg border border-n-slate-4 bg-n-solid-2 px-3 py-1.5 text-xs font-semibold text-n-slate-11 transition hover:bg-n-slate-2"
                                    :data-test-id="`aftercare-edit-cancel-${item.id}-${step.id}`"
                                    :disabled="isAftercareDraftSaving(item.id, step.id)"
                                    @click.stop="cancelAftercareDraftEdit(item.id, step.id)"
                                  >
                                    Hủy
                                  </button>
                                </div>
                              </div>
                              <div
                                v-else-if="step.draft_body"
                                :data-test-id="`aftercare-draft-preview-${item.id}-${step.id}`"
                                :title="step.draft_body"
                                class="mt-2 block max-w-[320px] truncate text-xs leading-5 text-n-slate-12"
                              >
                                {{ aftercareDraftPreviewText(step.draft_body) }}
                              </div>
                              <div
                                v-else-if="step.draft_error"
                                class="mt-2 text-xs leading-5 text-n-ruby-11"
                              >
                                {{ step.draft_error }}
                              </div>
                              <div
                                v-else
                                class="mt-2 text-xs leading-5 text-n-slate-10"
                              >
                                Chưa có bản xem trước của bản nháp.
                              </div>
                              <div
                                v-if="step.latest_dispatch_log"
                                class="mt-2 text-[11px] leading-5 text-n-slate-10"
                              >
                                Gửi gần nhất:
                                {{ aftercareDispatchStatusText(step.latest_dispatch_log.status) }}
                                <span v-if="step.latest_dispatch_log.sent_at">
                                  · {{ formatIsoDateTime(step.latest_dispatch_log.sent_at) }}
                                </span>
                                <span v-else-if="step.latest_dispatch_log.error_message">
                                  · {{ step.latest_dispatch_log.error_message }}
                                </span>
                              </div>
                              <div
                                v-if="step.last_error"
                                class="mt-2 text-xs leading-5 text-n-ruby-11"
                              >
                                {{ step.last_error }}
                              </div>
                            </div>
                          </div>
                        </td>
                        <td class="px-4 py-4 text-sm text-n-slate-12 align-top">
                          <div class="flex min-w-[160px] flex-col gap-2">
                            <button
                              v-if="String(item.status || '').trim() === 'active'"
                              type="button"
                              class="rounded-lg border border-n-amber-4 bg-n-amber-2 px-3 py-2 text-left text-xs font-semibold text-n-amber-11 transition hover:bg-n-amber-3 disabled:cursor-not-allowed disabled:opacity-60"
                              :data-test-id="`aftercare-pause-${item.id}`"
                              :disabled="isAftercareEnrollmentTransitioning(item.id)"
                              @click.stop="pauseAftercareEnrollment(item.id)"
                            >
                              {{
                                isAftercareEnrollmentTransitioning(item.id)
                                  ? 'Đang tạm dừng...'
                                  : 'Tạm dừng kế hoạch'
                              }}
                            </button>
                            <button
                              v-if="String(item.status || '').trim() === 'paused'"
                              type="button"
                              class="rounded-lg border border-n-teal-4 bg-n-teal-2 px-3 py-2 text-left text-xs font-semibold text-n-teal-11 transition hover:bg-n-teal-3 disabled:cursor-not-allowed disabled:opacity-60"
                              :data-test-id="`aftercare-resume-${item.id}`"
                              :disabled="isAftercareEnrollmentTransitioning(item.id)"
                              @click.stop="resumeAftercareEnrollment(item.id)"
                            >
                              {{
                                isAftercareEnrollmentTransitioning(item.id)
                                  ? 'Đang tiếp tục...'
                                  : 'Tiếp tục kế hoạch'
                              }}
                            </button>
                            <button
                              type="button"
                              class="rounded-lg border border-n-ruby-4 bg-n-ruby-2 px-3 py-2 text-left text-xs font-semibold text-n-ruby-11 transition hover:bg-n-ruby-3 disabled:cursor-not-allowed disabled:opacity-60"
                              :data-test-id="`aftercare-cancel-${item.id}`"
                              :disabled="
                                isAftercareEnrollmentCancelling(item.id) ||
                                ['cancelled', 'completed'].includes(String(item.status || '').trim())
                              "
                              @click.stop="cancelAftercareEnrollment(item.id)"
                            >
                              {{
                                isAftercareEnrollmentCancelling(item.id)
                                  ? 'Đang hủy kế hoạch...'
                                  : 'Hủy kế hoạch'
                              }}
                            </button>
                            <button
                              v-for="step in item.steps || []"
                              :key="`aftercare-edit-${item.id}-${step.id || step.position}`"
                              type="button"
                              class="rounded-lg border border-n-blue-4 bg-n-blue-2 px-3 py-2 text-left text-xs font-semibold text-n-blue-11 transition hover:bg-n-blue-3 disabled:cursor-not-allowed disabled:opacity-60"
                              :data-test-id="`aftercare-edit-${item.id}-${step.id}`"
                              :disabled="
                                isAftercareDraftSaving(item.id, step.id) ||
                                isAftercareStepRefreshing(step.id)
                              "
                              @click.stop="startAftercareDraftEdit(item.id, step)"
                            >
                              {{
                                isAftercareDraftEditing(item.id, step.id)
                                  ? `Đang sửa B${step.position || ''}`
                                  : `Sửa nội dung B${step.position || ''}`
                              }}
                            </button>
                            <button
                              v-for="step in item.steps || []"
                              :key="`aftercare-regenerate-${item.id}-${step.id || step.position}`"
                              type="button"
                              class="rounded-lg border border-n-slate-4 bg-n-solid-2 px-3 py-2 text-left text-xs font-semibold text-n-slate-12 transition hover:bg-n-slate-2 disabled:cursor-not-allowed disabled:opacity-60"
                              :data-test-id="`aftercare-regenerate-${item.id}-${step.id}`"
                              :disabled="
                                isAftercareStepRefreshing(step.id) ||
                                isAftercareDraftSaving(item.id, step.id)
                              "
                              @click.stop="regenerateAftercareDraft(item.id, step.id)"
                            >
                              {{
                                isAftercareStepRefreshing(step.id)
                                  ? 'Đang tạo lại bản nháp...'
                                  : `Tạo lại bản nháp B${step.position || ''}`
                              }}
                            </button>
                            <button
                              v-for="step in (item.steps || []).filter(
                                row => String(row?.status || '').trim() === 'failed'
                              )"
                              :key="`aftercare-retry-${item.id}-${step.id || step.position}`"
                              type="button"
                              class="rounded-lg border border-n-amber-4 bg-n-amber-2 px-3 py-2 text-left text-xs font-semibold text-n-amber-11 transition hover:bg-n-amber-3 disabled:cursor-not-allowed disabled:opacity-60"
                              :data-test-id="`aftercare-retry-${item.id}-${step.id}`"
                              :disabled="isAftercareStepRetrying(step.id)"
                              @click.stop="retryAftercareStep(item.id, step.id)"
                            >
                              {{
                                isAftercareStepRetrying(step.id)
                                  ? 'Đang xếp hàng gửi lại...'
                                  : `Gửi lại B${step.position || ''}`
                              }}
                            </button>
                          </div>
                        </td>
                      </tr>
                    </tbody>
                  </table>
                </div>
              </div>
            </div>
        </div>

        <!-- TAB: BÁO CÁO -->
        <div
          v-if="hasMountedMainTab('reporting')"
          v-show="activeMainTab === 'reporting'"
          class="flex flex-col gap-6"
        >
            <!-- Report Filter -->
            <ReportFilterSelector
              :show-agents-filter="false"
              :show-group-by-filter="false"
              :show-business-hours-switch="false"
              @filterChange="onFilterChange"
              @filter-change="onFilterChange"
            />

            <!-- KPI Cards (clickable) -->
            <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-5 gap-4">
              <div
                class="rounded-2xl outline outline-1 outline-n-amber-4 bg-gradient-to-br from-n-amber-2 to-n-amber-3 shadow-sm p-5 cursor-pointer transition-all hover:-translate-y-0.5 hover:shadow-md"
                @click="activeMainTab = 'operations'"
              >
                <div class="text-[10px] font-bold uppercase tracking-wider text-n-amber-11">Doanh thu chờ duyệt</div>
                <div class="mt-1 text-2xl font-bold text-n-amber-12">{{ paymentTotalAmountText }}</div>
                <div class="mt-2 text-[10px] text-n-amber-11/70">{{ paymentReviewTotal }} ca thanh toán →</div>
              </div>

              <button
                type="button"
                :data-test-id="`report-label-trigger-${labelTestId('khách_mới')}`"
                class="rounded-2xl outline outline-1 outline-n-blue-4 bg-gradient-to-br from-n-blue-2 to-n-blue-3 shadow-sm p-5 transition-all hover:-translate-y-0.5 hover:shadow-md"
                @click="openReportLabelPopup('khách_mới')"
              >
                <div class="text-[10px] font-bold uppercase tracking-wider text-n-blue-11">Khách mới</div>
                <div class="mt-1 text-2xl font-bold text-n-blue-12">{{ newClientsCount.toLocaleString() }}</div>
                <div class="mt-2 text-[10px] text-n-blue-11/70">Nhãn #khách_mới →</div>
              </button>

              <button
                type="button"
                :data-test-id="`report-label-trigger-${labelTestId('ý_định_đặt_lịch_xác_nhận')}`"
                class="rounded-2xl outline outline-1 outline-n-teal-4 bg-gradient-to-br from-n-teal-2 to-n-teal-3 shadow-sm p-5 transition-all hover:-translate-y-0.5 hover:shadow-md"
                @click="openReportLabelPopup('ý_định_đặt_lịch_xác_nhận')"
              >
                <div class="text-[10px] font-bold uppercase tracking-wider text-n-teal-11">Tỉ lệ chốt (Close Rate)</div>
                <div class="mt-1 text-2xl font-bold text-n-teal-12">{{ closeRateText }}</div>
                <div class="mt-2 text-[10px] text-n-teal-11/70">{{ closeCount }} ca chốt thành công →</div>
              </button>

              <button
                type="button"
                :data-test-id="`report-label-trigger-${labelTestId('khách_quay_lại')}`"
                class="rounded-2xl outline outline-1 outline-n-violet-4 bg-gradient-to-br from-n-violet-2 to-n-violet-3 shadow-sm p-5 transition-all hover:-translate-y-0.5 hover:shadow-md"
                @click="openReportLabelPopup('khách_quay_lại')"
              >
                <div class="text-[10px] font-bold uppercase tracking-wider text-n-violet-11">Khách quay lại</div>
                <div class="mt-1 text-2xl font-bold text-n-violet-12">{{ returnClientsCount.toLocaleString() }}</div>
                <div class="mt-2 text-[10px] text-n-violet-11/70">Nhãn #khách_quay_lại →</div>
              </button>

              <button
                type="button"
                :data-test-id="`report-label-trigger-${labelTestId('cần_theo_dõi')}`"
                class="rounded-2xl outline outline-1 outline-n-ruby-4 bg-gradient-to-br from-n-ruby-2 to-n-ruby-3 shadow-sm p-5 transition-all hover:-translate-y-0.5 hover:shadow-md"
                @click="openReportLabelPopup('cần_theo_dõi')"
              >
                <div class="text-[10px] font-bold uppercase tracking-wider text-n-ruby-11">Khách cần dặn / Nhắc lịch</div>
                <div class="mt-1 text-2xl font-bold text-n-ruby-12">{{ followUpCount.toLocaleString() }}</div>
                <div class="mt-2 text-[10px] text-n-ruby-11/70">Nhãn #cần_theo_dõi →</div>
              </button>
            </div>

            <!-- Charts -->
            <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
              <div class="rounded-2xl outline outline-1 outline-n-slate-4 bg-n-solid-1 shadow-sm p-6">
                <div class="text-sm font-semibold text-n-slate-12 mb-4 flex items-center gap-2">
                  <span class="w-2 h-2 rounded-full bg-n-teal-9 inline-block"></span>
                  Luồng xử lý AI
                </div>
                <div class="relative h-64">
                  <canvas ref="handoffChartRef"></canvas>
                </div>
                <div v-if="reportHandoffData.total" class="mt-3 text-center text-xs text-n-slate-11">
                  Tổng: {{ formatCount(reportHandoffData.total) }} hội thoại
                </div>
              </div>

              <div class="rounded-2xl outline outline-1 outline-n-slate-4 bg-n-solid-1 shadow-sm p-6">
                <div class="flex flex-col gap-4 mb-4">
                  <div class="flex flex-col gap-3 md:flex-row md:items-start md:justify-between">
                    <div>
                      <div class="text-sm font-semibold text-n-slate-12 flex items-center gap-2">
                        <span class="w-2 h-2 rounded-full bg-n-blue-9 inline-block"></span>
                        {{ activeTrendMetricLabel }}
                      </div>
                      <div class="mt-1 text-2xl font-bold text-n-slate-12">
                        {{ formatTrendValueText(aiGrowthTotal) }}
                      </div>
                      <div class="mt-1 text-[11px] text-n-slate-11">
                        {{ trendSummaryText }}
                      </div>
                      <div class="mt-2 text-[11px] font-medium" :class="aiGrowthDeltaTone">
                        {{ trendDeltaText }}
                      </div>
                    </div>

                    <div class="flex flex-col items-start gap-2 md:items-end">
                      <div class="flex items-center gap-2 flex-wrap">
                        <button
                          v-for="option in TREND_METRIC_OPTIONS"
                          :key="option.key"
                          type="button"
                          :data-test-id="`trend-metric-${option.key}`"
                          class="rounded-full px-3 py-1.5 text-[11px] font-semibold transition-colors"
                          :class="trendMetricClass(option.key)"
                          @click="selectTrendMetric(option.key)"
                        >
                          {{ option.label }}
                        </button>
                      </div>

                      <div class="flex items-center gap-2 flex-wrap">
                      <button
                        v-for="option in AI_GROWTH_RANGE_OPTIONS"
                        :key="option.key"
                        type="button"
                        :data-test-id="`ai-growth-range-${option.key}`"
                        class="rounded-full px-3 py-1.5 text-[11px] font-semibold transition-colors"
                        :class="aiGrowthRangeClass(option.key)"
                        @click="selectAiGrowthRange(option.key)"
                      >
                        {{ option.label }}
                      </button>
                      </div>
                    </div>
                  </div>

                  <div v-if="aiGrowthError" class="rounded-xl bg-n-ruby-2 px-3 py-2 text-xs text-n-ruby-11">
                    {{ aiGrowthError }}
                  </div>
                </div>
                <div class="relative h-64">
                  <div
                    v-if="isAiGrowthLoading"
                    class="absolute inset-0 z-10 flex items-center justify-center rounded-2xl bg-n-solid-1/70 text-xs font-medium text-n-slate-11 backdrop-blur-sm"
                  >
                    Đang tải dữ liệu xu hướng...
                  </div>
                  <canvas ref="aiGrowthChartRef"></canvas>
                </div>
              </div>
            </div>

            <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
              <div class="rounded-2xl outline outline-1 outline-n-slate-4 bg-n-solid-1 shadow-sm p-6">
                <div class="text-sm font-semibold text-n-slate-12 mb-4 flex items-center gap-2">
                  <span class="w-2 h-2 rounded-full bg-n-amber-9 inline-block"></span>
                  Phân bố nhãn AI
                </div>
                <div class="relative h-64">
                  <canvas ref="labelPolarChartRef"></canvas>
                </div>
              </div>

              <!-- Label Detail Table (clickable) -->
              <div class="rounded-2xl outline outline-1 outline-n-slate-4 bg-n-solid-1 shadow-sm overflow-hidden">
                <div class="px-5 py-4 border-b border-n-slate-3 bg-n-solid-2 flex items-center justify-between">
                  <div>
                    <div class="text-sm font-semibold text-n-slate-12 flex items-center gap-2">
                      <span class="w-2 h-2 rounded-full bg-n-slate-9 inline-block"></span>
                      Chi tiết nhãn AI
                    </div>
                    <div class="mt-0.5 text-[10px] text-n-slate-11">Hệ thống sẽ tự động học các nhãn tùy chỉnh bạn thêm</div>
                  </div>
                  <div class="flex items-center gap-2">
                    <button
                      class="flex items-center gap-1 text-[10px] font-semibold text-n-teal-11 bg-n-teal-2 px-2.5 py-1.5 rounded-lg outline outline-1 outline-n-teal-4 hover:bg-n-teal-3 transition-colors uppercase tracking-wide"
                      @click="openAddLabelPopup"
                    >
                      <svg xmlns="http://www.w3.org/2000/svg" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><line x1="12" y1="5" x2="12" y2="19" /><line x1="5" y1="12" x2="19" y2="12" /></svg>
                      THÊM NHÃN
                    </button>
                    <router-link
                      :to="{ name: 'labels_list', params: { accountId: route.params.accountId } }"
                      class="flex items-center gap-1 text-[10px] font-semibold text-n-blue-11 bg-n-blue-2 px-2.5 py-1.5 rounded-lg outline outline-1 outline-n-blue-4 hover:bg-n-blue-3 transition-colors uppercase tracking-wide"
                    >
                      QUẢN LÝ
                    </router-link>
                  </div>
                </div>
                <div class="p-4 flex flex-col gap-2 max-h-80 overflow-y-auto">
                  <div
                    v-for="row in trackedLabelRows"
                    :key="row.name"
                    class="flex items-center justify-between rounded-xl outline outline-1 outline-n-slate-3 bg-n-solid-2 px-4 py-3 transition-all hover:bg-n-slate-3 hover:outline-n-blue-4 group cursor-pointer"
                  >
                    <button
                      type="button"
                      :data-test-id="`report-label-trigger-${labelTestId(row.name)}`"
                      class="flex flex-col gap-1 min-w-0 flex-1"
                      @click="openReportLabelPopup(row.name)"
                    >
                      <div class="text-xs font-semibold text-n-slate-12 group-hover:text-n-blue-11 transition-colors truncate">
                        {{ labelDisplayName(row.name) }}
                      </div>
                      <div class="flex items-center gap-2">
                        <div class="flex-1 h-1.5 rounded-full bg-n-slate-3 overflow-hidden">
                          <div
                            class="h-full rounded-full transition-all duration-500"
                            :class="
                              labelTone(row.name) === 'teal' ? 'bg-n-teal-9'
                              : labelTone(row.name) === 'ruby' ? 'bg-n-ruby-9'
                              : labelTone(row.name) === 'amber' ? 'bg-n-amber-9'
                              : labelTone(row.name) === 'blue' ? 'bg-n-blue-9'
                              : 'bg-n-slate-9'
                            "
                            :style="{ width: `${labelPercent(row)}%` }"
                          />
                        </div>
                        <div class="text-[10px] font-semibold text-n-slate-11 w-8 text-right">
                          {{ labelPercent(row) }}%
                        </div>
                      </div>
                    </button>
                    <div class="flex items-center gap-2 ml-3">
                      <div class="text-sm font-bold text-n-slate-11 bg-n-slate-3 px-2.5 py-1 rounded-lg">
                        {{ row.conversationsCount.toLocaleString() }}
                      </div>
                      <button
                        v-if="findLabelByTitle(row.name)"
                        v-tooltip.top="'Xóa nhãn này'"
                        class="p-1.5 rounded-lg text-n-ruby-11 bg-n-ruby-2/50 opacity-0 group-hover:opacity-100 hover:bg-n-ruby-3 transition-all"
                        :disabled="isDeletingLabel"
                        @click.stop="openDeleteLabelPopup(findLabelByTitle(row.name))"
                      >
                        <svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 6h18" /><path d="M19 6v14c0 1-1 2-2 2H7c-1 0-2-1-2-2V6" /><path d="M8 6V4c0-1 1-2 2-2h4c1 0 2 1 2 2v2" /><line x1="10" y1="11" x2="10" y2="17" /><line x1="14" y1="11" x2="14" y2="17" /></svg>
                      </button>
                    </div>
                  </div>
                </div>
              </div>
            </div>
        </div>

        <!-- TAB: COMMENT -->
        <div
          v-if="hasMountedMainTab('comment')"
          v-show="activeMainTab === 'comment'"
          class="grid gap-6 lg:grid-cols-12 lg:items-start"
        >
            <!-- Comment Queue (Left) -->
            <div class="lg:col-span-4 xl:col-span-4 self-start rounded-2xl outline outline-1 outline-n-slate-4 bg-n-solid-1 shadow-sm overflow-hidden">
              <div class="px-5 py-4 border-b border-n-slate-3 bg-n-solid-2">
                <div class="flex items-center justify-between">
                  <div class="text-base font-semibold text-n-slate-12">💬 Comment Queue</div>
                  <div class="flex items-center gap-2">
                    <select
                      v-model="commentStatusFilter"
                      class="h-8 rounded-lg outline outline-1 outline-n-weak bg-n-background px-2 text-xs font-medium text-n-slate-12"
                      @change="fetchCommentQueue"
                    >
                      <option value="">Tất cả</option>
                      <option value="open">Đang mở</option>
                      <option value="pending">Chờ xử lý</option>
                      <option value="resolved">Đã xử lý</option>
                    </select>
                    <button
                      class="h-8 w-8 rounded-lg flex items-center justify-center bg-n-slate-3 hover:bg-n-slate-4 text-n-slate-11 transition-colors"
                      @click="fetchCommentQueue"
                    >
                      <svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="23 4 23 10 17 10"/><polyline points="1 20 1 14 7 14"/><path d="M3.51 9a9 9 0 0 1 14.85-3.36L23 10M1 14l4.64 4.36A9 9 0 0 0 20.49 15"/></svg>
                    </button>
                  </div>
                </div>
                <div class="mt-1 text-xs text-n-slate-11">{{ commentTotal }} comment · {{ commentQueue.length }} hiển thị</div>
              </div>

              <div class="overflow-y-auto max-h-[52rem] divide-y divide-n-slate-3">
                <!-- Loading -->
                <div v-if="isCommentLoading" class="py-12 text-center text-sm text-n-slate-11">
                  <div class="flex items-center justify-center gap-2">
                    <div class="w-4 h-4 rounded-full border-2 border-n-teal-9 border-t-transparent animate-spin"></div>
                    Đang tải...
                  </div>
                </div>

                <!-- Empty -->
                <div v-else-if="!commentQueue.length" class="py-12 text-center">
                  <div class="text-3xl mb-2">💬</div>
                  <div class="text-sm font-medium text-n-slate-12">Chưa có comment nào</div>
                  <div class="mt-1 text-xs text-n-slate-11">Comment từ Instagram sẽ hiển thị ở đây</div>
                </div>

                <!-- Queue Items -->
                <div
                  v-for="item in commentQueue"
                  :key="item.post_id"
                  class="px-4 py-3 cursor-pointer transition-all hover:bg-n-slate-2/50"
                  :class="selectedCommentConversation?.post_id === item.post_id ? 'bg-n-teal-2/50 border-l-2 border-n-teal-9' : ''"
                  @click="selectCommentConversation(item)"
                >
                  <!-- Post header with media and latest comment -->
                  <div class="flex items-start gap-3">
                    <!-- Post Media Preview -->
                    <div class="w-14 h-14 rounded-lg bg-n-slate-3 flex-shrink-0 overflow-hidden relative">
                      <img
                        v-if="item.post_media_url"
                        :src="item.post_media_url"
                        class="w-full h-full object-cover"
                        alt="Post preview"
                        @error="$event.target.style.display='none'"
                      />
                      <div v-else class="w-full h-full flex items-center justify-center text-n-slate-10">
                        <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="3" width="18" height="18" rx="2" ry="2"/><circle cx="8.5" cy="8.5" r="1.5"/><polyline points="21 15 16 10 5 21"/></svg>
                      </div>
                      <!-- Platform badge overlay -->
                      <div
                        class="absolute bottom-0.5 right-0.5 w-4 h-4 rounded-sm flex items-center justify-center text-[8px]"
                        :class="item.platform === 'instagram' ? 'bg-gradient-to-br from-purple-500 to-pink-500 text-white' : 'bg-blue-600 text-white'"
                      >
                        {{ item.platform === 'instagram' ? '📸' : '📘' }}
                      </div>
                    </div>
                    <div class="min-w-0 flex-1">
                      <div class="flex items-center justify-between">
                        <span class="text-sm font-semibold text-n-slate-12 truncate">{{ item.post_caption ? item.post_caption.substring(0, 35) + '...' : 'Bài viết' }}</span>
                        <span class="text-[10px] text-n-slate-10 flex-shrink-0 ml-2">{{ commentTimeAgo(item.last_activity_at) }}</span>
                      </div>
                      <!-- Latest comment preview -->
                      <div class="mt-1 text-xs text-n-slate-11 line-clamp-2">
                        <span v-if="item.messages && item.messages.length">
                          <span class="font-medium text-n-slate-12">{{ item.messages[item.messages.length - 1].author_name || 'Khách' }}:</span>
                          {{ item.messages[item.messages.length - 1].content || '...' }}
                        </span>
                      </div>
                      <div class="text-[10px] text-n-slate-10 mt-1">{{ item.messages_count }} comment · Nhấn để xem chi tiết</div>
                    </div>
                  </div>
                </div>
              </div>
            </div>

            <!-- Post Preview + Thread (Right) -->
            <div class="lg:col-span-8 xl:col-span-8 self-start">
              <!-- Empty State -->
              <div v-if="!selectedCommentConversation" class="rounded-2xl outline outline-1 outline-n-slate-4 bg-n-solid-1 shadow-sm p-12 text-center">
                <div class="text-4xl mb-3">📱</div>
                <div class="text-base font-semibold text-n-slate-12">Chọn một comment để xem</div>
                <div class="mt-1 text-sm text-n-slate-11">Chọn comment từ danh sách bên trái để xem chi tiết</div>
              </div>

              <!-- Phone Mock Preview -->
              <div v-else class="flex flex-col gap-4">
                <!-- Post Card -->
                <div class="rounded-2xl outline outline-1 outline-n-slate-4 bg-n-solid-1 shadow-sm overflow-hidden">
                  <!-- Post header -->
                  <div class="px-4 py-3 flex items-center gap-3 border-b border-n-slate-3">
                    <div class="w-8 h-8 rounded-full bg-gradient-to-br from-purple-500 to-pink-500 flex items-center justify-center text-white text-xs font-bold">
                      📷
                    </div>
                    <div>
                      <div class="text-sm font-semibold text-n-slate-12">Post: {{ selectedCommentConversation.post_id }}</div>
                      <div class="text-[10px] text-n-slate-10">{{ selectedCommentConversation.platform || 'instagram' }}</div>
                    </div>
                    <a
                      v-if="selectedCommentConversation.post_permalink"
                      :href="selectedCommentConversation.post_permalink"
                      target="_blank"
                      class="ml-auto text-xs text-n-blue-11 hover:underline"
                    >
                      Mở trên Instagram ↗
                    </a>
                  </div>

                  <!-- Post media -->
                  <div v-if="selectedCommentConversation.post_media_url" class="bg-n-slate-2">
                    <img
                      :src="selectedCommentConversation.post_media_url"
                      class="w-full max-h-80 object-cover"
                      alt="Post media"
                      @error="$event.target.style.display='none'"
                    />
                  </div>

                  <!-- Post stats + caption -->
                  <div class="px-4 py-3">
                    <div class="flex items-center gap-4 text-sm text-n-slate-11 mb-2">
                      <span v-if="selectedCommentConversation.post_like_count" class="flex items-center gap-1">
                        ❤️ {{ Number(selectedCommentConversation.post_like_count).toLocaleString() }}
                      </span>
                      <span v-if="selectedCommentConversation.post_comment_count" class="flex items-center gap-1">
                        💬 {{ Number(selectedCommentConversation.post_comment_count).toLocaleString() }}
                      </span>
                    </div>
                    <div v-if="selectedCommentConversation.post_caption" class="text-sm text-n-slate-12 line-clamp-3">
                      {{ selectedCommentConversation.post_caption }}
                    </div>
                  </div>
                </div>

                <!-- Thread -->
                <div class="rounded-2xl outline outline-1 outline-n-slate-4 bg-n-solid-1 shadow-sm overflow-hidden">
                  <div class="px-4 py-3 border-b border-n-slate-3 bg-n-solid-2 flex items-center justify-between">
                    <span class="text-sm font-semibold text-n-slate-12">💬 Thread Comment</span>
                    <div class="flex items-center gap-2">
                      <button
                        class="h-8 px-3 rounded-lg text-xs font-medium bg-n-teal-3 text-n-teal-12 hover:bg-n-teal-4 transition-colors flex items-center gap-1.5"
                        :disabled="isCommentAutoReplying"
                        @click="triggerAutoReply(selectedCommentConversation)"
                      >
                        <div v-if="isCommentAutoReplying" class="w-3 h-3 rounded-full border-2 border-n-teal-9 border-t-transparent animate-spin"></div>
                        <span>🤖 Auto Reply</span>
                      </button>
                    </div>
                  </div>

                  <div class="overflow-y-auto max-h-[28rem] p-4 space-y-3">
                    <!-- Loading -->
                    <div v-if="isCommentThreadLoading" class="py-8 text-center text-sm text-n-slate-11">
                      <div class="flex items-center justify-center gap-2">
                        <div class="w-4 h-4 rounded-full border-2 border-n-teal-9 border-t-transparent animate-spin"></div>
                        Đang tải thread...
                      </div>
                    </div>

                    <!-- Empty -->
                    <div v-else-if="!commentThread.length" class="py-8 text-center text-sm text-n-slate-11">
                      Chưa có tin nhắn trong thread này
                    </div>

                    <!-- Messages with nested structure -->
                    <CommentThread
                      :comments="commentThread"
                      :replying-to="replyingToComment"
                      @reply="setReplyingTo"
                    />
                  </div>

                  <!-- Reply Composer -->
                  <div class="px-4 py-3 border-t border-n-slate-3 bg-n-solid-2">
                    <!-- Replying to indicator -->
                    <div
                      v-if="replyingToComment"
                      class="mb-2 px-3 py-2 rounded-lg bg-n-blue-2 border border-n-blue-4 flex items-center justify-between"
                    >
                      <div class="text-xs text-n-blue-11">
                        <span class="font-semibold">Đang reply:</span>
                        <span class="ml-1 text-n-slate-12">{{ replyingToComment.author_name || 'Khách' }}</span>
                        <span class="text-n-slate-10 ml-1">"{{ (replyingToComment.content || '').substring(0, 50) }}{{ (replyingToComment.content || '').length > 50 ? '...' : '' }}"</span>
                      </div>
                      <button
                        @click="clearReplyingTo"
                        class="text-n-slate-10 hover:text-n-slate-12"
                      >
                        ✕
                      </button>
                    </div>
                    <div class="flex items-end gap-2">
                      <textarea
                        v-model="commentReplyText"
                        rows="2"
                        class="flex-1 rounded-xl outline outline-1 outline-n-weak bg-n-background px-4 py-2.5 text-sm text-n-slate-12 resize-none focus:outline-n-teal-6 transition-colors placeholder:text-n-slate-10"
                        :placeholder="replyingToComment ? `Reply ${replyingToComment.author_name || 'Khách'}...` : 'Viết reply comment...'"
                        @keydown.meta.enter="sendCommentReply"
                        @keydown.ctrl.enter="sendCommentReply"
                      />
                      <button
                        class="h-10 px-4 rounded-xl bg-n-teal-9 text-white text-sm font-semibold hover:bg-n-teal-10 transition-colors shadow-sm flex items-center gap-1.5 disabled:opacity-50"
                        :disabled="!commentReplyText.trim() || isCommentReplying"
                        @click="sendCommentReply"
                      >
                        <div v-if="isCommentReplying" class="w-3.5 h-3.5 rounded-full border-2 border-white border-t-transparent animate-spin"></div>
                        <span>Gửi</span>
                      </button>
                    </div>
                    <div class="mt-1.5 text-[10px] text-n-slate-10">⌘+Enter hoặc Ctrl+Enter để gửi nhanh</div>
                  </div>
                </div>
              </div>
            </div>
        </div>
      </div>
    </div>
    <!-- Add Label Modal -->
    <woot-modal v-model:show="showAddLabelPopup" :on-close="closeAddLabelPopup">
      <AddLabel @close="closeAddLabelPopup" />
    </woot-modal>

    <woot-modal v-model:show="showReportLabelPopup" :on-close="closeReportLabelPopup">
      <div class="w-[40rem] max-w-[calc(100vw-2rem)] p-6">
        <div class="flex items-start justify-between gap-4">
          <div>
            <div class="text-lg font-semibold text-n-slate-12">
              {{ toTitleCase(labelDisplayName(selectedReportLabel)) || 'Chi tiết nhãn' }}
            </div>
            <div class="mt-1 text-sm text-n-slate-11">
              Chọn khách để mở phần tin nhắn ngay trong trang AI Control.
            </div>
          </div>
          <Button
            color="slate"
            size="sm"
            label="Đóng"
            @click="closeReportLabelPopup"
          />
        </div>

        <div class="mt-5">
          <div
            v-if="isReportLabelPreviewLoading"
            class="flex items-center justify-center rounded-2xl border border-n-slate-3 bg-n-solid-2 px-4 py-10 text-sm text-n-slate-11"
          >
            <div class="w-4 h-4 rounded-full border-2 border-n-blue-9 border-t-transparent animate-spin"></div>
            <span class="ml-2">Đang tải danh sách khách...</span>
          </div>

          <div
            v-else-if="reportLabelPreviewError"
            class="rounded-2xl border border-n-ruby-4 bg-n-ruby-2 px-4 py-4 text-sm font-medium text-n-ruby-11"
          >
            {{ reportLabelPreviewError }}
          </div>

          <div
            v-else-if="!reportLabelPreviewItems.length"
            class="rounded-2xl border border-dashed border-n-slate-4 px-4 py-10 text-center text-sm text-n-slate-11"
          >
            Chưa có hội thoại nào cho nhãn này.
          </div>

          <div v-else class="flex max-h-[28rem] flex-col gap-3 overflow-y-auto pr-1">
            <button
              v-for="item in reportLabelPreviewItems"
              :key="`report-label-conversation-${item.id}`"
              type="button"
              :data-test-id="`report-label-conversation-${item.id}`"
              class="flex items-start gap-3 rounded-2xl border border-n-slate-3 bg-n-solid-1 px-4 py-3 text-left transition-all hover:border-n-blue-4 hover:bg-n-blue-2/30"
              @click="openReportLabelConversation(item)"
            >
              <Avatar
                :name="item.name"
                :src="item.avatarUrl"
                :size="40"
                rounded-full
              />
              <div class="min-w-0 flex-1">
                <div class="truncate text-sm font-semibold text-n-slate-12">
                  {{ item.name }}
                </div>
                <div class="mt-1 text-xs text-n-slate-11">
                  {{ item.subtext }}
                </div>
                <div class="mt-2 text-sm text-n-slate-11 line-clamp-2">
                  {{ item.snippet }}
                </div>
              </div>
            </button>
          </div>
        </div>
      </div>
    </woot-modal>

    <AftercareEnrollmentDialog
      :show="showAftercareDialog"
      :conversation-id="aiControlConversationId"
      :conversation-label="selectedAftercareConversationLabel"
      :contact-email="selectedAftercareContactEmail"
      :sequences="aftercareSequences"
      :eligibility="aftercareEligibility"
      :is-loading="isAftercareDialogLoading"
      :is-submitting="isAftercareSubmitting"
      @update:show="showAftercareDialog = $event"
      @submit="submitAftercareEnrollment"
    />

    <!-- Delete Label Confirmation Modal -->
    <woot-delete-modal
      v-model:show="showDeleteLabelPopup"
      :on-close="closeDeleteLabelPopup"
      :on-confirm="deleteLabel"
      :title="'Xác nhận xóa nhãn'"
      :message="'Bạn có chắc chắn muốn xóa nhãn'"
      :message-value="selectedLabelToDelete ? ` ${selectedLabelToDelete.title}?` : '?'"
      :confirm-text="'Xóa'"
      :reject-text="'Hủy'"
      :is-loading="isDeletingLabel"
    />
  </div>
</template>
