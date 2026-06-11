<script setup>
import { onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import AiControlAPI from 'dashboard/api/aiControl';
import NextButton from 'dashboard/components-next/button/Button.vue';
import NextInput from 'next/input/Input.vue';
import Switch from 'next/switch/Switch.vue';
import SectionLayout from './SectionLayout.vue';

const { t } = useI18n();

const wikiLearningEnabled = ref(false);
const wikiLearningTimeOfDay = ref('03:00');
const wikiLearningTimezoneName = ref('Asia/Bangkok');
const isWikiLearningScheduleLoading = ref(false);
const isWikiLearningScheduleSaving = ref(false);
const isWikiLearningNowRunning = ref(false);

const syncWikiLearningScheduleState = schedule => {
  const normalized = schedule && typeof schedule === 'object' ? schedule : {};
  wikiLearningEnabled.value = Boolean(normalized.enabled);
  wikiLearningTimeOfDay.value =
    String(normalized.time_of_day || normalized.timeOfDay || '03:00').trim() ||
    '03:00';
  wikiLearningTimezoneName.value =
    String(
      normalized.timezone_name || normalized.timezoneName || 'Asia/Bangkok'
    ).trim() || 'Asia/Bangkok';
};

const fetchWikiLearningSchedule = async () => {
  isWikiLearningScheduleLoading.value = true;
  try {
    const response = await AiControlAPI.getWikiLearningSchedule();
    syncWikiLearningScheduleState(response?.data || {});
  } catch (error) {
    useAlert(t('GENERAL_SETTINGS.FORM.WIKI_LEARNING.API.LOAD_ERROR'));
  } finally {
    isWikiLearningScheduleLoading.value = false;
  }
};

const saveWikiLearningSchedule = async () => {
  if (isWikiLearningScheduleSaving.value) return;

  isWikiLearningScheduleSaving.value = true;
  try {
    const response = await AiControlAPI.updateWikiLearningSchedule({
      enabled: wikiLearningEnabled.value,
      timeOfDay: wikiLearningTimeOfDay.value,
      timezoneName: wikiLearningTimezoneName.value,
    });
    syncWikiLearningScheduleState(response?.data || {});
    useAlert(t('GENERAL_SETTINGS.FORM.WIKI_LEARNING.API.SUCCESS'));
  } catch (error) {
    useAlert(t('GENERAL_SETTINGS.FORM.WIKI_LEARNING.API.ERROR'));
  } finally {
    isWikiLearningScheduleSaving.value = false;
  }
};

const runWikiLearningNow = async () => {
  if (isWikiLearningNowRunning.value) return;

  isWikiLearningNowRunning.value = true;
  try {
    const response = await AiControlAPI.runWikiLearningNow();
    const schedule = response?.data?.schedule;
    if (schedule && typeof schedule === 'object') {
      syncWikiLearningScheduleState(schedule);
    } else {
      await fetchWikiLearningSchedule();
    }
    useAlert(t('GENERAL_SETTINGS.FORM.WIKI_LEARNING.API.RUN_NOW_SUCCESS'));
  } catch (error) {
    useAlert(t('GENERAL_SETTINGS.FORM.WIKI_LEARNING.API.RUN_NOW_ERROR'));
  } finally {
    isWikiLearningNowRunning.value = false;
  }
};

onMounted(fetchWikiLearningSchedule);
</script>

<template>
  <SectionLayout
    :title="$t('GENERAL_SETTINGS.FORM.WIKI_LEARNING.TITLE')"
    :description="$t('GENERAL_SETTINGS.FORM.WIKI_LEARNING.NOTE')"
    with-border
  >
    <div class="grid gap-3">
      <label
        class="flex items-center justify-between gap-3 rounded-md border border-n-weak px-3 py-2 text-sm text-n-slate-12"
      >
        <span>{{
          $t('GENERAL_SETTINGS.FORM.WIKI_LEARNING.ENABLED_LABEL')
        }}</span>
        <Switch
          v-model="wikiLearningEnabled"
          data-testid="wiki-enabled"
          :disabled="isWikiLearningScheduleLoading"
        />
      </label>

      <label class="grid gap-2 text-sm text-n-slate-12">
        <span>{{ $t('GENERAL_SETTINGS.FORM.WIKI_LEARNING.TIME_LABEL') }}</span>
        <NextInput
          v-model="wikiLearningTimeOfDay"
          data-testid="wiki-time"
          type="time"
          class="w-full"
        />
      </label>

      <label class="grid gap-2 text-sm text-n-slate-12">
        <span>{{
          $t('GENERAL_SETTINGS.FORM.WIKI_LEARNING.TIMEZONE_LABEL')
        }}</span>
        <NextInput
          v-model="wikiLearningTimezoneName"
          data-testid="wiki-timezone"
          type="text"
          class="w-full"
        />
      </label>

      <div class="flex flex-wrap items-center gap-3">
        <NextButton
          data-testid="wiki-save"
          blue
          :is-loading="isWikiLearningScheduleSaving"
          @click="saveWikiLearningSchedule"
        >
          {{ $t('GENERAL_SETTINGS.FORM.WIKI_LEARNING.SAVE_BUTTON') }}
        </NextButton>
        <NextButton
          data-testid="wiki-run-now"
          slate
          :is-loading="isWikiLearningNowRunning"
          @click="runWikiLearningNow"
        >
          {{ $t('GENERAL_SETTINGS.FORM.WIKI_LEARNING.RUN_NOW_BUTTON') }}
        </NextButton>
      </div>
    </div>
  </SectionLayout>
</template>
