<script setup>
import { onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import AiControlAPI from 'dashboard/api/aiControl';
import Switch from 'next/switch/Switch.vue';
import SectionLayout from './SectionLayout.vue';

const { t } = useI18n();

const isEnabled = ref(false);
const replayAfterMinutes = ref(60);
const activeWindowHours = ref(24);
const isLoading = ref(false);

const syncConfig = data => {
  const config = data && typeof data === 'object' ? data : {};
  isEnabled.value = Boolean(config.enabled);
  replayAfterMinutes.value = Number(config.replay_after_minutes || 60);
  activeWindowHours.value = Number(config.active_window_hours || 24);
};

const fetchConfig = async () => {
  isLoading.value = true;
  try {
    const response = await AiControlAPI.getChatwootReplyReplayConfig();
    syncConfig(response?.data || {});
  } catch (error) {
    useAlert(t('GENERAL_SETTINGS.FORM.CHATWOOT_REPLY_REPLAY.API.ERROR'));
  } finally {
    isLoading.value = false;
  }
};

const toggleReplyReplay = async () => {
  try {
    const response = await AiControlAPI.updateChatwootReplyReplayConfig({
      enabled: isEnabled.value,
    });
    syncConfig(response?.data || {});
    useAlert(t('GENERAL_SETTINGS.FORM.CHATWOOT_REPLY_REPLAY.API.SUCCESS'));
  } catch (error) {
    useAlert(t('GENERAL_SETTINGS.FORM.CHATWOOT_REPLY_REPLAY.API.ERROR'));
  }
};

onMounted(fetchConfig);
</script>

<template>
  <SectionLayout
    :title="$t('GENERAL_SETTINGS.FORM.CHATWOOT_REPLY_REPLAY.TITLE')"
    :description="$t('GENERAL_SETTINGS.FORM.CHATWOOT_REPLY_REPLAY.NOTE')"
    with-border
  >
    <template #headerActions>
      <div class="flex justify-end">
        <Switch
          v-model="isEnabled"
          :disabled="isLoading"
          @change="toggleReplyReplay"
        />
      </div>
    </template>

    <div class="flex flex-wrap gap-2 text-sm">
      <span class="rounded-md bg-n-alpha-2 px-2 py-1 text-n-slate-12">
        {{
          $t(
            'GENERAL_SETTINGS.FORM.CHATWOOT_REPLY_REPLAY.STATUS.REPEAT_INTERVAL',
            {
              minutes: replayAfterMinutes,
            }
          )
        }}
      </span>
      <span class="rounded-md bg-n-alpha-2 px-2 py-1 text-n-slate-12">
        {{
          $t(
            'GENERAL_SETTINGS.FORM.CHATWOOT_REPLY_REPLAY.STATUS.ACTIVE_WINDOW',
            {
              hours: activeWindowHours,
            }
          )
        }}
      </span>
    </div>
  </SectionLayout>
</template>
