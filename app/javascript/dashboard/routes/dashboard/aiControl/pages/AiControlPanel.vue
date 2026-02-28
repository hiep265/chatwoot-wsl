<script setup>
import { computed, onMounted, onBeforeUnmount, ref, watch, nextTick } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useStore } from 'vuex';

import ReportsAPI from 'dashboard/api/reports';
import SummaryReportsAPI from 'dashboard/api/summaryReports';
import ConversationLabelsAPI from 'dashboard/api/conversations';
import InboxConversationAPI from 'dashboard/api/inbox/conversation';
import AiControlAPI from 'dashboard/api/aiControl';

import ReportHeader from '../../settings/reports/components/ReportHeader.vue';
import ReportFilterSelector from '../../settings/reports/components/FilterSelector.vue';
import ConversationView from '../../conversation/ConversationView.vue';

import Button from 'dashboard/components-next/button/Button.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';

import { useAlert } from 'dashboard/composables';
import { emitter } from 'shared/helpers/mitt';

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

const activeMainTab = ref('operations');
const reportingDashboardUrl = ref('https://app.powerbi.com/view?r=custom_id_from_user');

const activeKpiTab = ref('traffic');

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
const paymentReviewLimit = ref(50);
const paymentReviewLastError = ref('');
const paymentReviewActionLoading = ref(new Set());

// Chỉ dùng ai_handoff để đánh dấu cả chuyển nhân viên và dừng AI
const HANDOFF_LABEL = 'ai_handoff';
const BOOKING_CONFIRMED_LABEL = 'y_dinh_dat_lich_xac_nhan';
const LABEL_ALIASES = {
  fai_handoff: HANDOFF_LABEL,
  intent_booking_confirmed: BOOKING_CONFIRMED_LABEL,
  ai_upset: 'cam_xuc_tieu_cuc',
  ai_urgent: 'uu_tien_gap',
  ai_lead: 'khach_tiem_nang',
  ai_lead_high: 'khach_tiem_nang_cao',
  ai_lead_medium: 'khach_tiem_nang_trung_binh',
  ai_lead_low: 'khach_tiem_nang_thap',
  payment_collection: 'thu_thap_thanh_toan',
  handover_sales_opportunity: 'ly_do_handoff_co_hoi_chot_don',
  handover_negative_sentiment: 'ly_do_handoff_khach_tieu_cuc',
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
const aiControlConversationId = computed(
  () => route.params.conversation_id || 0
);
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

const aiAutomationText = computed(() => {
  const total = Number(labelOverviewTotal.value || 0);
  const resolved = trackedLabelCount(BOOKING_CONFIRMED_LABEL);
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
  const messages = Number(
    String(botMessageCount.value || '0').replace(/,/g, '') || 0
  );
  if (!conversations) return 0;
  return Math.round((messages / conversations) * 10) / 10;
});

const topHandoverReasons = computed(() => {
  const rows = Array.isArray(trackedLabelRows.value)
    ? trackedLabelRows.value
    : [];
  return rows
    .filter(r => {
      const name = normalizeLabelKey(r?.name);
      return name.startsWith('ly_do_handoff_') || name.startsWith('handover_');
    })
    .sort((a, b) => (b.conversationsCount || 0) - (a.conversationsCount || 0))
    .slice(0, 5);
});

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
  if (!val) return '0 ₫';
  return val.toLocaleString('vi-VN') + ' ₫';
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
  const conversationId = String(item?.conversation_id || '').trim();
  if (!conversationId) return;

  router.push({
    name: props.standalone
      ? 'ai_control_simple_conversation'
      : 'ai_control_panel_conversation',
    params: {
      accountId: route.params.accountId,
      conversation_id: conversationId,
    },
  });
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

    useAlert('Đã xác nhận thanh toán và kích hoạt luồng hậu thanh toán.');
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
      label: normalizeLabelKey(label),
    },
  };
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

const fetchPaymentReviewCases = async () => {
  isPaymentReviewLoading.value = true;
  paymentReviewLastError.value = '';

  try {
    const segment =
      paymentReviewSegment.value === 'all'
        ? undefined
        : paymentReviewSegment.value;
    const response = await AiControlAPI.listPaymentReviewCases({
      reviewStatus: 'payment_review_pending',
      segment,
      limit: paymentReviewLimit.value,
      offset: 0,
    });

    const data = response?.data || {};
    const rows = Array.isArray(data?.cases) ? data.cases : [];
    paymentReviewCases.value = rows;
    paymentReviewTotal.value = Number(data?.total || rows.length || 0);
    paymentReviewCount.value = Number(data?.count || rows.length || 0);
  } catch (e) {
    paymentReviewCases.value = [];
    paymentReviewTotal.value = 0;
    paymentReviewCount.value = 0;
    paymentReviewLastError.value =
      'Không tải được danh sách chờ xác minh thanh toán.';
    useAlert(paymentReviewLastError.value);
  } finally {
    isPaymentReviewLoading.value = false;
  }
};

const fetchAll = async () => {
  try {
    await Promise.all([
      fetchTrafficSummary(),
      fetchBotMetrics(),
      fetchLabelSummary(),
      fetchLiveConversations(),
      fetchPaymentReviewCases(),
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

const onRefreshLiveConversations = async () => {
  await Promise.all([fetchLiveConversations(), fetchPaymentReviewCases()]);
  if (to.value && from.value) {
    await Promise.all([
      fetchTrafficSummary(),
      fetchBotMetrics(),
      fetchLabelSummary(),
    ]);
  }
};

const openReportingDashboard = () => {
  window.open(reportingDashboardUrl.value, '_blank');
};

// ── Chart.js integration ──
const chartJsLoaded = ref(false);
const handoffChartRef = ref(null);
const handoverBarChartRef = ref(null);
const labelPolarChartRef = ref(null);
let handoffChartInstance = null;
let handoverBarChartInstance = null;
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
  if (handoverBarChartInstance) { handoverBarChartInstance.destroy(); handoverBarChartInstance = null; }
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

  // 2. Handover Reasons Bar
  const barEl = handoverBarChartRef.value;
  if (barEl) {
    const reasons = Array.isArray(topHandoverReasons.value) ? topHandoverReasons.value : [];
    const barColors = ['rgba(59,130,246,0.8)','rgba(168,85,247,0.8)','rgba(245,158,11,0.8)','rgba(16,185,129,0.8)','rgba(239,68,68,0.8)'];
    handoverBarChartInstance = new Chart(barEl, {
      type: 'bar',
      data: {
        labels: reasons.map(r => toTitleCase(handoverReasonDisplay(r.name))),
        datasets: [{ label: 'Số lượng', data: reasons.map(r => r.conversationsCount || 0), backgroundColor: reasons.map((_, i) => barColors[i % barColors.length]), borderRadius: 6, borderSkipped: false }]
      },
      options: { responsive: true, maintainAspectRatio: false, indexAxis: 'y', plugins: { legend: { display: false } }, scales: { x: { grid: { color: 'rgba(0,0,0,0.06)' }, ticks: { color: '#64748b' } }, y: { grid: { display: false }, ticks: { color: '#334155', font: { size: 11 } } } } }
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

watch(activeMainTab, async (tab) => {
  if (tab === 'reporting') {
    await loadChartJs();
    await nextTick();
    renderCharts();
  }
});

watch([trackedLabelRows, topHandoverReasons], () => {
  if (activeMainTab.value === 'reporting') {
    nextTick(() => renderCharts());
  }
});

onMounted(() => {
  fetchPaymentReviewCases();
  fetchBlockedInboxes();
  store.dispatch('inboxes/get');
  emitter.on(
    'ai_control_panel:refresh_live_conversations',
    onRefreshLiveConversations
  );
  // Fetch happens after the first filter event
});

onBeforeUnmount(() => {
  emitter.off(
    'ai_control_panel:refresh_live_conversations',
    onRefreshLiveConversations
  );
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

      <div class="pb-6">
        <!-- Main Tabs Switcher -->
        <div class="flex items-center justify-center mb-6">
          <div
            class="inline-flex items-center rounded-xl bg-n-solid-2 p-1 border border-n-slate-3 shadow-sm"
          >
            <button
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
          </div>
        </div>

        <!-- TAB: VẬN HÀNH -->
        <template v-if="activeMainTab === 'operations'">
          <div class="flex flex-col gap-6">
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
              <div class="overflow-x-auto">
                <table class="min-w-full divide-y divide-n-slate-3">
                  <thead class="bg-n-solid-2/50 backdrop-blur-sm">
                    <tr
                      class="text-left text-xs font-semibold uppercase tracking-wider text-n-slate-11"
                    >
                      <th class="px-6 py-3">Khách hàng</th>
                      <th class="px-6 py-3">Hạng mục mua</th>
                      <th class="px-6 py-3">Số item</th>
                      <th class="px-6 py-3">Giá trị dự kiến</th>
                      <th class="px-6 py-3">Ghi chú</th>
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
                        v-for="item in paymentReviewCases"
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
                          <span
                            class="inline-flex items-center rounded-full bg-n-amber-3 px-2.5 py-1 text-xs font-semibold text-n-amber-12 ring-1 ring-inset ring-n-amber-5"
                          >
                            {{ item.review_status || 'payment_review_pending' }}
                          </span>
                        </td>
                        <td class="px-6 py-4 text-right">
                          <Button
                            color="teal"
                            size="sm"
                            class="h-8 shadow-sm transition-transform active:scale-95"
                            label="Xác nhận"
                            :is-loading="isPaymentCaseActionLoading(item.id)"
                            @click.stop="confirmPaymentCase(item)"
                          />
                        </td>
                      </tr>
                    </template>
                  </tbody>
                </table>
              </div>
              <div
                class="px-6 py-4 border-t border-n-slate-3 bg-n-solid-2/50 text-xs font-medium text-n-slate-11"
              >
                Hiển thị {{ paymentReviewCount.toLocaleString() }} bản ghi.
              </div>
            </div>

            <!-- ===== SECTION 2: Hội thoại (CHÍNH) + Sidebar tools ===== -->
            <div class="grid gap-6 lg:grid-cols-12 lg:items-start">
              <!-- ConversationView — chiếm 8/12 cột -->
              <div
                class="lg:col-span-8 xl:col-span-9 self-start rounded-2xl outline outline-1 outline-n-slate-4 bg-n-solid-1 shadow-sm overflow-hidden"
              >
                <div class="h-[52rem] bg-n-solid-2">
                  <ConversationView
                    :inbox-id="0"
                    :conversation-id="aiControlConversationId"
                  />
                </div>
              </div>

              <!-- Sidebar tools — 4/12 cột -->
              <div class="lg:col-span-4 xl:col-span-3 flex flex-col gap-5">
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
                      class="rounded-xl outline outline-1 outline-n-teal-4 bg-n-teal-2/50 px-4 py-3 text-xs text-n-slate-12 shadow-sm"
                    >
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
                  </div>
                </div>
              </div>
            </div>
          </div>
        </template>

        <!-- TAB: BÁO CÁO -->
        <template v-else-if="activeMainTab === 'reporting'">
          <div class="flex flex-col gap-6">
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
              <router-link
                class="rounded-2xl outline outline-1 outline-n-blue-4 bg-gradient-to-br from-n-blue-2 to-n-blue-3 shadow-sm p-5 transition-all hover:-translate-y-0.5 hover:shadow-md"
                :to="labelRoute(BOOKING_CONFIRMED_LABEL)"
              >
                <div class="text-[10px] font-bold uppercase tracking-wider text-n-blue-11">Tổng lưu lượng</div>
                <div class="mt-1 text-2xl font-bold text-n-blue-12">{{ trafficConversationCountText }}</div>
                <div class="mt-2 text-[10px] text-n-blue-11/70">Click xem chi tiết →</div>
              </router-link>

              <router-link
                class="rounded-2xl outline outline-1 outline-n-teal-4 bg-gradient-to-br from-n-teal-2 to-n-teal-3 shadow-sm p-5 transition-all hover:-translate-y-0.5 hover:shadow-md"
                :to="labelRoute(BOOKING_CONFIRMED_LABEL)"
              >
                <div class="text-[10px] font-bold uppercase tracking-wider text-n-teal-11">AI tự xử lý</div>
                <div class="mt-1 text-2xl font-bold text-n-teal-12">{{ aiAutomationText }}</div>
                <div class="mt-2 text-[10px] text-n-teal-11/70">Nhãn #{{ BOOKING_CONFIRMED_LABEL }} →</div>
              </router-link>

              <router-link
                class="rounded-2xl outline outline-1 outline-n-ruby-4 bg-gradient-to-br from-n-ruby-2 to-n-ruby-3 shadow-sm p-5 transition-all hover:-translate-y-0.5 hover:shadow-md"
                :to="labelRoute('ai_handoff')"
              >
                <div class="text-[10px] font-bold uppercase tracking-wider text-n-ruby-11">Chuyển nhân viên</div>
                <div class="mt-1 text-2xl font-bold text-n-ruby-12">{{ aiHandoffText }}</div>
                <div class="mt-2 text-[10px] text-n-ruby-11/70">Nhãn #ai_handoff →</div>
              </router-link>

              <div
                class="rounded-2xl outline outline-1 outline-n-amber-4 bg-gradient-to-br from-n-amber-2 to-n-amber-3 shadow-sm p-5 cursor-pointer transition-all hover:-translate-y-0.5 hover:shadow-md"
                @click="activeMainTab = 'operations'"
              >
                <div class="text-[10px] font-bold uppercase tracking-wider text-n-amber-11">Chờ thanh toán</div>
                <div class="mt-1 text-2xl font-bold text-n-amber-12">{{ paymentTotalAmountText }}</div>
                <div class="mt-2 text-[10px] text-n-amber-11/70">{{ paymentReviewTotal }} ca · Xem vận hành →</div>
              </div>

              <div class="rounded-2xl outline outline-1 outline-n-slate-4 bg-gradient-to-br from-n-solid-2 to-n-slate-3 shadow-sm p-5">
                <div class="text-[10px] font-bold uppercase tracking-wider text-n-slate-11">Tin nhắn Bot</div>
                <div class="mt-1 text-2xl font-bold text-n-slate-12">{{ formatCount(botMessageCount) }}</div>
                <div class="mt-2 text-[10px] text-n-slate-11/70">TB {{ averageBotMessagesPerConversation }} / hội thoại</div>
              </div>
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
                <div class="text-sm font-semibold text-n-slate-12 mb-4 flex items-center gap-2">
                  <span class="w-2 h-2 rounded-full bg-n-blue-9 inline-block"></span>
                  Top lý do chuyển nhân viên
                </div>
                <div class="relative h-64">
                  <canvas ref="handoverBarChartRef"></canvas>
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
                <div class="px-5 py-4 border-b border-n-slate-3 bg-n-solid-2">
                  <div class="text-sm font-semibold text-n-slate-12 flex items-center gap-2">
                    <span class="w-2 h-2 rounded-full bg-n-slate-9 inline-block"></span>
                    Chi tiết nhãn AI
                  </div>
                  <div class="mt-0.5 text-[10px] text-n-slate-11">Click vào nhãn để xem hội thoại</div>
                </div>
                <div class="p-4 flex flex-col gap-2 max-h-80 overflow-y-auto">
                  <router-link
                    v-for="row in trackedLabelRows"
                    :key="row.name"
                    class="flex items-center justify-between rounded-xl outline outline-1 outline-n-slate-3 bg-n-solid-2 px-4 py-3 transition-all hover:bg-n-slate-3 hover:outline-n-blue-4 group cursor-pointer"
                    :to="labelRoute(row.name)"
                  >
                    <div class="flex flex-col gap-1 min-w-0 flex-1">
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
                    </div>
                    <div class="ml-3 text-sm font-bold text-n-slate-11 bg-n-slate-3 px-2.5 py-1 rounded-lg">
                      {{ row.conversationsCount.toLocaleString() }}
                    </div>
                  </router-link>
                </div>
              </div>
            </div>
          </div>
        </template>
      </div>
    </div>
  </div>
</template>
