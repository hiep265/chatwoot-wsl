<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import AiControlAPI from 'dashboard/api/aiControl';
import NextButton from 'dashboard/components-next/button/Button.vue';
import NextInput from 'next/input/Input.vue';
import SectionLayout from './SectionLayout.vue';

const { t } = useI18n();

const faqTrainingDays = ref(7);
const isFaqTrainingLoading = ref(false);
const faqTrainingReport = ref(null);

const runFaqTraining = async () => {
  const days = Number(faqTrainingDays.value || 0);
  if (!Number.isFinite(days) || days < 1 || days > 365) {
    useAlert(t('GENERAL_SETTINGS.FORM.FAQ_TRAINING.API.INVALID_DAYS'));
    return;
  }

  isFaqTrainingLoading.value = true;
  try {
    const response = await AiControlAPI.trainFaq({
      days,
      dryRun: false,
      conversationsPerBatch: 20,
    });
    faqTrainingReport.value = response?.data?.report || response?.data || null;
    useAlert(t('GENERAL_SETTINGS.FORM.FAQ_TRAINING.API.SUCCESS'));
  } catch (error) {
    useAlert(t('GENERAL_SETTINGS.FORM.FAQ_TRAINING.API.ERROR'));
  } finally {
    isFaqTrainingLoading.value = false;
  }
};
</script>

<template>
  <SectionLayout
    :title="$t('GENERAL_SETTINGS.FORM.FAQ_TRAINING.TITLE')"
    :description="$t('GENERAL_SETTINGS.FORM.FAQ_TRAINING.NOTE')"
    with-border
  >
    <div class="grid gap-3">
      <label class="grid gap-2 text-sm text-n-slate-12">
        <span>{{ $t('GENERAL_SETTINGS.FORM.FAQ_TRAINING.DAYS_LABEL') }}</span>
        <NextInput
          v-model.number="faqTrainingDays"
          data-testid="days-input"
          type="number"
          min="1"
          max="365"
          class="w-full"
        />
      </label>

      <div class="flex items-center gap-3">
        <NextButton
          data-testid="run-training"
          blue
          :is-loading="isFaqTrainingLoading"
          @click="runFaqTraining"
        >
          {{ $t('GENERAL_SETTINGS.FORM.FAQ_TRAINING.RUN_BUTTON') }}
        </NextButton>
      </div>

      <div
        v-if="faqTrainingReport"
        class="grid gap-2 rounded-md border border-n-weak bg-n-alpha-1 px-3 py-3 text-sm text-n-slate-12"
      >
        <div class="flex items-center justify-between gap-3">
          <span>{{
            $t('GENERAL_SETTINGS.FORM.FAQ_TRAINING.REPORT.CREATED')
          }}</span>
          <span>{{
            Number(faqTrainingReport.published_count || 0).toLocaleString()
          }}</span>
        </div>
        <div class="flex items-center justify-between gap-3">
          <span>{{
            $t('GENERAL_SETTINGS.FORM.FAQ_TRAINING.REPORT.DUPLICATES')
          }}</span>
          <span>{{
            Number(faqTrainingReport.duplicate_count || 0).toLocaleString()
          }}</span>
        </div>
        <div class="flex items-center justify-between gap-3">
          <span>{{
            $t('GENERAL_SETTINGS.FORM.FAQ_TRAINING.REPORT.CONFLICTS')
          }}</span>
          <span>{{
            Number(faqTrainingReport.conflict_count || 0).toLocaleString()
          }}</span>
        </div>
        <div class="flex items-center justify-between gap-3">
          <span>{{
            $t('GENERAL_SETTINGS.FORM.FAQ_TRAINING.REPORT.ERRORS')
          }}</span>
          <span>{{
            Number(faqTrainingReport.error_count || 0).toLocaleString()
          }}</span>
        </div>
      </div>
    </div>
  </SectionLayout>
</template>
