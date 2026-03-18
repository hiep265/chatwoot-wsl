<script>
import { defineAsyncComponent, ref, computed } from 'vue';

import NextSidebar from 'next/sidebar/Sidebar.vue';
import UpgradePage from 'dashboard/routes/dashboard/upgrade/UpgradePage.vue';

import { useUISettings } from 'dashboard/composables/useUISettings';
import { useAccount } from 'dashboard/composables/useAccount';
import { useWindowSize } from '@vueuse/core';
import { getConversationDisplayPreferencePatch } from 'dashboard/helper/bootstrapHelper';
import { OPEN_COMMAND_BAR } from 'dashboard/helper/commandbar/events';
import { emitter } from 'shared/helpers/mitt';

import wootConstants from 'dashboard/constants/globals';

const AddAccountModal = defineAsyncComponent(
  () => import('dashboard/components/app/AddAccountModal.vue')
);

const CommandBar = defineAsyncComponent(
  () => import('./commands/commandbar.vue')
);

const WootKeyShortcutModal = defineAsyncComponent(
  () => import('dashboard/components/widgets/modal/WootKeyShortcutModal.vue')
);

const FloatingCallWidget = defineAsyncComponent(
  () => import('dashboard/components/widgets/FloatingCallWidget.vue')
);

import CopilotLauncher from 'dashboard/components-next/copilot/CopilotLauncher.vue';

const CopilotContainer = defineAsyncComponent(
  () => import('dashboard/components/copilot/CopilotContainer.vue')
);

import MobileSidebarLauncher from 'dashboard/components-next/sidebar/MobileSidebarLauncher.vue';
import { useCallsStore } from 'dashboard/stores/calls';

export default {
  components: {
    NextSidebar,
    CommandBar,
    WootKeyShortcutModal,
    AddAccountModal,
    UpgradePage,
    CopilotLauncher,
    CopilotContainer,
    FloatingCallWidget,
    MobileSidebarLauncher,
  },
  setup() {
    const upgradePageRef = ref(null);
    const { uiSettings, updateUISettings } = useUISettings();
    const { accountId } = useAccount();
    const { width: windowWidth } = useWindowSize();
    const callsStore = useCallsStore();

    return {
      uiSettings,
      updateUISettings,
      accountId,
      upgradePageRef,
      windowWidth,
      hasActiveCall: computed(() => callsStore.hasActiveCall),
      hasIncomingCall: computed(() => callsStore.hasIncomingCall),
    };
  },
  data() {
    return {
      showAccountModal: false,
      showCreateAccountModal: false,
      showShortcutModal: false,
      isMobileSidebarOpen: false,
      shouldRenderCommandBar: false,
      pendingCommandBarRequest: null,
    };
  },
  computed: {
    isSmallScreen() {
      return this.windowWidth < wootConstants.SMALL_SCREEN_BREAKPOINT;
    },
    showUpgradePage() {
      return this.upgradePageRef?.shouldShowUpgradePage;
    },
    bypassUpgradePage() {
      return [
        'billing_settings_index',
        'settings_inbox_list',
        'general_settings_index',
        'agent_list',
      ].includes(this.$route.name);
    },
    previouslyUsedDisplayType() {
      const {
        previously_used_conversation_display_type: conversationDisplayType,
      } = this.uiSettings;
      return conversationDisplayType;
    },
  },
  watch: {
    isSmallScreen: {
      handler() {
        const { LAYOUT_TYPES } = wootConstants;
        const patch = getConversationDisplayPreferencePatch({
          isSmallScreen:
            window.innerWidth <= wootConstants.SMALL_SCREEN_BREAKPOINT,
          currentDisplayType: this.uiSettings?.conversation_display_type,
          expandedLayoutType: LAYOUT_TYPES.EXPANDED,
          previousDisplayType: this.previouslyUsedDisplayType,
        });

        if (patch) {
          this.updateUISettings(patch);
        }
      },
      immediate: true,
    },
  },
  mounted() {
    emitter.on(OPEN_COMMAND_BAR, this.requestCommandBarOpen);
  },
  unmounted() {
    emitter.off(OPEN_COMMAND_BAR, this.requestCommandBarOpen);
  },
  methods: {
    flushPendingCommandBarOpen() {
      if (!this.pendingCommandBarRequest) {
        return;
      }

      this.$nextTick(() => {
        const ninja = document.querySelector('ninja-keys');

        if (!ninja || !this.pendingCommandBarRequest) {
          return;
        }

        const { options } = this.pendingCommandBarRequest;
        this.pendingCommandBarRequest = null;
        ninja.open(options);
      });
    },
    onCommandBarReady() {
      this.flushPendingCommandBarOpen();
    },
    requestCommandBarOpen(options) {
      this.pendingCommandBarRequest = { options };

      if (!this.shouldRenderCommandBar) {
        this.shouldRenderCommandBar = true;
        return;
      }

      this.flushPendingCommandBarOpen();
    },
    toggleMobileSidebar() {
      this.isMobileSidebarOpen = !this.isMobileSidebarOpen;
    },
    closeMobileSidebar() {
      this.isMobileSidebarOpen = false;
    },
    openCreateAccountModal() {
      this.showAccountModal = false;
      this.showCreateAccountModal = true;
    },
    closeCreateAccountModal() {
      this.showCreateAccountModal = false;
    },
    toggleAccountModal() {
      this.showAccountModal = !this.showAccountModal;
    },
    toggleKeyShortcutModal() {
      this.showShortcutModal = true;
    },
    closeKeyShortcutModal() {
      this.showShortcutModal = false;
    },
  },
};
</script>

<template>
  <div class="flex flex-grow overflow-hidden text-n-slate-12">
    <NextSidebar
      :is-mobile-sidebar-open="isMobileSidebarOpen"
      @toggle-account-modal="toggleAccountModal"
      @open-key-shortcut-modal="toggleKeyShortcutModal"
      @close-key-shortcut-modal="closeKeyShortcutModal"
      @show-create-account-modal="openCreateAccountModal"
      @close-mobile-sidebar="closeMobileSidebar"
    />

    <main class="flex flex-1 h-full w-full min-h-0 px-0 overflow-hidden">
      <UpgradePage
        v-show="showUpgradePage"
        ref="upgradePageRef"
        :bypass-upgrade-page="bypassUpgradePage"
      >
        <MobileSidebarLauncher
          :is-mobile-sidebar-open="isMobileSidebarOpen"
          @toggle="toggleMobileSidebar"
        />
      </UpgradePage>
      <template v-if="!showUpgradePage">
        <router-view />
        <CommandBar v-if="shouldRenderCommandBar" @ready="onCommandBarReady" />
        <CopilotLauncher />
        <MobileSidebarLauncher
          :is-mobile-sidebar-open="isMobileSidebarOpen"
          @toggle="toggleMobileSidebar"
        />
        <CopilotContainer v-if="uiSettings?.is_copilot_panel_open" />
        <FloatingCallWidget v-if="hasActiveCall || hasIncomingCall" />
      </template>
      <AddAccountModal
        v-if="showCreateAccountModal"
        :show="showCreateAccountModal"
        @close-account-create-modal="closeCreateAccountModal"
      />
      <WootKeyShortcutModal
        v-if="showShortcutModal"
        v-model:show="showShortcutModal"
        @close="closeKeyShortcutModal"
        @clickaway="closeKeyShortcutModal"
      />
    </main>
  </div>
</template>
