<script setup>
import { useAttrs } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';

const attrs = useAttrs();
const globalConfig = useMapGetter('globalConfig/get');
</script>

<template>
  <img
    v-if="globalConfig.logoThumbnail"
    v-bind="attrs"
    :src="globalConfig.logoThumbnail"
  />
  <svg
    v-else
    v-once
    v-bind="attrs"
    width="16"
    height="16"
    viewBox="0 0 16 16"
    fill="none"
    xmlns="http://www.w3.org/2000/svg"
  >
    <defs>
      <linearGradient id="ta-tech-mark-gradient" x1="1.5" y1="1" x2="14.5" y2="15">
        <stop offset="0" stop-color="#00D4FF" />
        <stop offset="0.55" stop-color="#3B82F6" />
        <stop offset="1" stop-color="#00F5A0" />
      </linearGradient>
    </defs>
    <path
      d="M8 0.85L13.85 4.23V11.77L8 15.15L2.15 11.77V4.23L8 0.85Z"
      fill="url(#ta-tech-mark-gradient)"
    />
    <path
      d="M4.35 5.05H11.65"
      stroke="white"
      stroke-width="1.45"
      stroke-linecap="round"
    />
    <path
      d="M8 5.05V10.55"
      stroke="white"
      stroke-width="1.45"
      stroke-linecap="round"
    />
    <path
      d="M5.9 10.95L8 8.35L10.1 10.95"
      stroke="#CFFAFE"
      stroke-width="1.15"
      stroke-linecap="round"
      stroke-linejoin="round"
    />
    <circle cx="8" cy="12.3" r="1" fill="#CFFAFE" />
  </svg>
</template>
