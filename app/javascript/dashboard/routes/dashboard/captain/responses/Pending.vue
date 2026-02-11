<script setup>
import { computed, onMounted, ref, nextTick } from 'vue';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';
import { useRouter, useRoute } from 'vue-router';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { debounce } from '@chatwoot/utils';
import { useAccount } from 'dashboard/composables/useAccount';
import CaptainResponsesAPI from 'dashboard/api/captain/response';

import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import BulkSelectBar from 'dashboard/components-next/captain/assistant/BulkSelectBar.vue';
import DeleteDialog from 'dashboard/components-next/captain/pageComponents/DeleteDialog.vue';
import BulkDeleteDialog from 'dashboard/components-next/captain/pageComponents/BulkDeleteDialog.vue';
import PageLayout from 'dashboard/components-next/captain/PageLayout.vue';
import CaptainPaywall from 'dashboard/components-next/captain/pageComponents/Paywall.vue';
import ResponseCard from 'dashboard/components-next/captain/assistant/ResponseCard.vue';
import CreateResponseDialog from 'dashboard/components-next/captain/pageComponents/response/CreateResponseDialog.vue';
import ResponsePageEmptyState from 'dashboard/components-next/captain/pageComponents/emptyStates/ResponsePageEmptyState.vue';
import FeatureSpotlightPopover from 'dashboard/components-next/feature-spotlight/FeatureSpotlightPopover.vue';
import LimitBanner from 'dashboard/components-next/captain/pageComponents/response/LimitBanner.vue';

const router = useRouter();
const route = useRoute();
const store = useStore();
const { isOnChatwootCloud } = useAccount();
const uiFlags = useMapGetter('captainResponses/getUIFlags');
const responseMeta = useMapGetter('captainResponses/getMeta');
const responses = useMapGetter('captainResponses/getRecords');
const isFetching = computed(() => uiFlags.value.fetchingList);

const selectedResponse = ref(null);
const deleteDialog = ref(null);
const bulkDeleteDialog = ref(null);

const selectedAssistantId = computed(() => route.params.assistantId);
const dialogType = ref('');
const searchQuery = ref('');
const { t } = useI18n();

const createDialog = ref(null);

const backUrl = computed(() => ({
  name: 'captain_assistants_responses_index',
  params: {
    accountId: route.params.accountId,
    assistantId: selectedAssistantId.value,
  },
}));

// Filter out approved responses in pending view
const filteredResponses = computed(() =>
  responses.value.filter(response => response.status !== 'approved')
);

const handleDelete = () => {
  deleteDialog.value.dialogRef.open();
};

const handleAccept = async () => {
  try {
    await store.dispatch('captainResponses/update', {
      id: selectedResponse.value.id,
      status: 'approved',
    });
    useAlert(t(`CAPTAIN.RESPONSES.EDIT.APPROVE_SUCCESS_MESSAGE`));
  } catch (error) {
    const errorMessage =
      error?.message || t(`CAPTAIN.RESPONSES.EDIT.ERROR_MESSAGE`);
    useAlert(errorMessage);
  } finally {
    selectedResponse.value = null;
  }
};

const handleEdit = () => {
  dialogType.value = 'edit';
  nextTick(() => createDialog.value.dialogRef.open());
};

// Scan answer cho một FAQ từ conversation gốc
const isScanningOne = ref(null); // Changed to store ID or null
const handleScanAnswer = async responseId => {
  const currentId = Number(responseId || selectedResponse.value?.id);
  if (!currentId) return;
  console.log('[Captain Pending] scanAnswer start', currentId);

  isScanningOne.value = currentId;
  try {
    const response = await CaptainResponsesAPI.scanAnswer(currentId);
    const { suggested_question, suggested_answer } = response.data;

    if (suggested_answer && !suggested_answer.includes('[Không tìm thấy')) {
      // Cập nhật question + answer và approve luôn
      const payload = {
        id: currentId,
        answer: suggested_answer,
        status: 'approved',
      };
      const questionText = String(suggested_question || '').trim();
      if (questionText) {
        payload.question = questionText;
      }

      await store.dispatch('captainResponses/update', payload);
      useAlert('Đã cập nhật cả câu hỏi và câu trả lời thành công!');
      fetchResponses(responseMeta.value?.page);
    } else {
      useAlert('Không tìm thấy câu trả lời phù hợp từ conversation');
    }
  } catch (error) {
    useAlert(error?.response?.data?.error || 'Lỗi khi scan answer');
  } finally {
    isScanningOne.value = null;
    selectedResponse.value = null;
  }
};

// Scan tất cả pending FAQs
const isScanningAll = ref(false);
const handleScanAllPending = async () => {
  isScanningAll.value = true;
  try {
    const response = await CaptainResponsesAPI.scanAllPending({
      assistantId: selectedAssistantId.value,
    });
    const { processed, success, failed } = response.data;
    useAlert(`Đã scan ${processed} FAQ: ${success} thành công, ${failed} thất bại`);
    fetchResponses(1);
  } catch (error) {
    useAlert(error?.response?.data?.error || 'Lỗi khi scan all');
  } finally {
    isScanningAll.value = false;
  }
};

const handleAction = ({ action, id }) => {
  console.warn('[Captain Pending] handleAction', { action, id });
  const responseId = Number(id);
  selectedResponse.value = filteredResponses.value.find(
    response => Number(response.id) === responseId
  );

  if (action === 'scan_answer') {
    handleScanAnswer(responseId);
    return;
  }

  nextTick(() => {
    if (action === 'delete') {
      handleDelete();
    }
    if (action === 'edit') {
      handleEdit();
    }
    if (action === 'approve') {
      handleAccept();
    }
  });
};

const handleNavigationAction = ({ id, type }) => {
  if (type === 'Conversation') {
    router.push({
      name: 'inbox_conversation',
      params: { conversation_id: id },
    });
  }
};

const handleCreateClose = () => {
  dialogType.value = '';
  selectedResponse.value = null;
};

const updateURLWithFilters = (page, search) => {
  const query = {
    page: page || 1,
  };

  if (search) {
    query.search = search;
  }

  router.replace({ query });
};

const fetchResponses = (page = 1) => {
  const filterParams = { page, status: 'pending' };

  if (selectedAssistantId.value) {
    filterParams.assistantId = selectedAssistantId.value;
  }
  if (searchQuery.value) {
    filterParams.search = searchQuery.value;
  }

  // Update URL with current filters
  updateURLWithFilters(page, searchQuery.value);

  store.dispatch('captainResponses/get', filterParams);
};

// Bulk action
const bulkSelectedIds = ref(new Set());
const hoveredCard = ref(null);

const hasBulkSelection = computed(() => bulkSelectedIds.value.size > 0);

const buildSelectedCountLabel = computed(() => {
  const count = filteredResponses.value?.length || 0;
  const isAllSelected = bulkSelectedIds.value.size === count && count > 0;
  return isAllSelected
    ? t('CAPTAIN.RESPONSES.UNSELECT_ALL', { count })
    : t('CAPTAIN.RESPONSES.SELECT_ALL', { count });
});

const selectedCountLabel = computed(() => {
  return t('CAPTAIN.RESPONSES.SELECTED', {
    count: bulkSelectedIds.value.size,
  });
});

const handleCardHover = (isHovered, id) => {
  hoveredCard.value = isHovered ? id : null;
};

const handleCardSelect = id => {
  const selected = new Set(bulkSelectedIds.value);
  selected[selected.has(id) ? 'delete' : 'add'](id);
  bulkSelectedIds.value = selected;
};

const fetchResponseAfterBulkAction = () => {
  const hasNoResponsesLeft = filteredResponses.value?.length === 0;
  const currentPage = responseMeta.value?.page;

  if (hasNoResponsesLeft) {
    const pageToFetch = currentPage > 1 ? currentPage - 1 : currentPage;
    fetchResponses(pageToFetch);
  } else {
    fetchResponses(currentPage);
  }

  bulkSelectedIds.value = new Set();
};

const handleBulkApprove = async () => {
  try {
    await store.dispatch(
      'captainBulkActions/handleBulkApprove',
      Array.from(bulkSelectedIds.value)
    );

    fetchResponseAfterBulkAction();
    useAlert(t('CAPTAIN.RESPONSES.BULK_APPROVE.SUCCESS_MESSAGE'));
  } catch (error) {
    useAlert(
      error?.message || t('CAPTAIN.RESPONSES.BULK_APPROVE.ERROR_MESSAGE')
    );
  }
};

const onPageChange = page => {
  const hadSelection = bulkSelectedIds.value.size > 0;

  fetchResponses(page);

  if (hadSelection) {
    bulkSelectedIds.value = new Set();
  }
};

const onDeleteSuccess = () => {
  if (filteredResponses.value?.length === 0 && responseMeta.value?.page > 1) {
    onPageChange(responseMeta.value.page - 1);
  }
};

const onBulkDeleteSuccess = () => {
  fetchResponseAfterBulkAction();
};

const debouncedSearch = debounce(async () => {
  fetchResponses(1);
}, 500);

const hasActiveFilters = computed(() => {
  return Boolean(searchQuery.value);
});

const clearFilters = () => {
  searchQuery.value = '';
  fetchResponses(1);
};

const initializeFromURL = () => {
  if (route.query.search) {
    searchQuery.value = route.query.search;
  }
  const pageFromURL = parseInt(route.query.page, 10) || 1;
  fetchResponses(pageFromURL);
};

onMounted(() => {
  initializeFromURL();
});
</script>

<template>
  <PageLayout
    :total-count="responseMeta.totalCount"
    :current-page="responseMeta.page"
    :header-title="$t('CAPTAIN.RESPONSES.PENDING_FAQS')"
    :is-fetching="isFetching"
    :is-empty="!filteredResponses.length"
    :show-pagination-footer="!isFetching && !!filteredResponses.length"
    :show-know-more="false"
    :feature-flag="FEATURE_FLAGS.CAPTAIN"
    :back-url="backUrl"
    @update:current-page="onPageChange"
  >
    <template #knowMore>
      <FeatureSpotlightPopover
        :button-label="$t('CAPTAIN.HEADER_KNOW_MORE')"
        :title="$t('CAPTAIN.RESPONSES.EMPTY_STATE.FEATURE_SPOTLIGHT.TITLE')"
        :note="$t('CAPTAIN.RESPONSES.EMPTY_STATE.FEATURE_SPOTLIGHT.NOTE')"
        :hide-actions="!isOnChatwootCloud"
        fallback-thumbnail="/assets/images/dashboard/captain/faqs-popover-light.svg"
        fallback-thumbnail-dark="/assets/images/dashboard/captain/faqs-popover-dark.svg"
        learn-more-url="https://chwt.app/captain-faq"
      />
    </template>

    <template #search>
      <div
        v-if="!hasBulkSelection"
        class="flex gap-3 justify-between w-full items-center"
      >
        <Input
          v-model="searchQuery"
          :placeholder="$t('CAPTAIN.RESPONSES.SEARCH_PLACEHOLDER')"
          class="w-64"
          size="sm"
          type="search"
          autofocus
          @input="debouncedSearch"
        />
        <Button
          label="Scan All Pending"
          sm
          outline
          icon="i-lucide-search"
          :is-loading="isScanningAll"
          @click="handleScanAllPending"
        />
      </div>
    </template>

    <template #subHeader>
      <BulkSelectBar
        v-model="bulkSelectedIds"
        :all-items="filteredResponses"
        :select-all-label="buildSelectedCountLabel"
        :selected-count-label="selectedCountLabel"
        :delete-label="$t('CAPTAIN.RESPONSES.BULK_DELETE_BUTTON')"
        class="w-fit"
        :class="{
          'mb-2': bulkSelectedIds.size > 0,
        }"
        @bulk-delete="bulkDeleteDialog.dialogRef.open()"
      >
        <template #secondary-actions>
          <Button
            :label="$t('CAPTAIN.RESPONSES.BULK_APPROVE_BUTTON')"
            sm
            ghost
            icon="i-lucide-check"
            class="!px-1.5"
            @click="handleBulkApprove"
          />
        </template>
      </BulkSelectBar>
    </template>

    <template #emptyState>
      <ResponsePageEmptyState
        variant="pending"
        :has-active-filters="hasActiveFilters"
        @clear-filters="clearFilters"
      />
    </template>

    <template #paywall>
      <CaptainPaywall />
    </template>

    <template #body>
      <LimitBanner class="mb-5" />

      <div class="flex flex-col gap-4">
        <ResponseCard
          v-for="response in filteredResponses"
          :id="response.id"
          :key="response.id"
          :question="response.question"
          :answer="response.answer"
          :assistant="response.assistant"
          :documentable="response.documentable"
          :status="response.status"
          :created-at="response.created_at"
          :updated-at="response.updated_at"
          :is-selected="bulkSelectedIds.has(response.id)"
          :selectable="hoveredCard === response.id || bulkSelectedIds.size > 0"
          :show-menu="false"
          :show-actions="!bulkSelectedIds.has(response.id)"
          :is-scanning="isScanningOne === response.id"
          @action="handleAction"
          @navigate="handleNavigationAction"
          @select="handleCardSelect"
          @hover="isHovered => handleCardHover(isHovered, response.id)"
        />
      </div>
    </template>

    <DeleteDialog
      v-if="selectedResponse"
      ref="deleteDialog"
      :entity="selectedResponse"
      type="Responses"
      translation-key="RESPONSES"
      @delete-success="onDeleteSuccess"
    />

    <BulkDeleteDialog
      v-if="bulkSelectedIds"
      ref="bulkDeleteDialog"
      :bulk-ids="bulkSelectedIds"
      type="Responses"
      @delete-success="onBulkDeleteSuccess"
    />

    <CreateResponseDialog
      v-if="dialogType"
      ref="createDialog"
      :type="dialogType"
      :selected-response="selectedResponse"
      @close="handleCreateClose"
    />
  </PageLayout>
</template>
