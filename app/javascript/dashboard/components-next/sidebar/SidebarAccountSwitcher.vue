<script setup>
import { computed, ref, watch } from 'vue';
import { useAccount } from 'dashboard/composables/useAccount';
import { useMapGetter } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import ButtonNext from 'next/button/Button.vue';
import Icon from 'next/icon/Icon.vue';
import Logo from 'next/icon/Logo.vue';

import {
  DropdownContainer,
  DropdownBody,
  DropdownSection,
  DropdownItem,
} from 'next/dropdown-menu/base';

defineProps({
  isCollapsed: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['showCreateAccountModal']);

const { t } = useI18n();
const { accountId, currentAccount } = useAccount();
const currentUser = useMapGetter('getCurrentUser');
const globalConfig = useMapGetter('globalConfig/get');

const userAccounts = useMapGetter('getUserAccounts');

// Surface the search input only when the operator actually has more
// accounts than they can comfortably scan; below that the input would
// just be visual noise above a 2- or 3-row list.
const SEARCH_THRESHOLD = 5;

const searchQuery = ref('');
const searchInputRef = ref(null);

const showAccountSwitcher = computed(
  () => userAccounts.value.length > 1 && currentAccount.value.name
);

const sortedCurrentUserAccounts = computed(() => {
  return [...(currentUser.value.accounts || [])].sort((a, b) =>
    a.name.localeCompare(b.name)
  );
});

const showSearch = computed(
  () => sortedCurrentUserAccounts.value.length >= SEARCH_THRESHOLD
);

const filteredAccounts = computed(() => {
  const query = searchQuery.value.trim().toLowerCase();
  if (!query) return sortedCurrentUserAccounts.value;
  return sortedCurrentUserAccounts.value.filter(account =>
    account.name.toLowerCase().includes(query)
  );
});

const onChangeAccount = newId => {
  const accountUrl = `/app/accounts/${newId}/dashboard`;
  window.location.href = accountUrl;
};

const emitNewAccount = () => {
  emit('showCreateAccountModal');
};

watch(showSearch, value => {
  if (!value) searchQuery.value = '';
});
</script>

<template>
  <DropdownContainer @close="searchQuery = ''">
    <template #trigger="{ toggle, isOpen }">
      <!-- Collapsed view: Logo trigger -->
      <button
        v-if="isCollapsed"
        class="grid flex-shrink-0 place-content-center p-2 rounded-lg cursor-pointer hover:bg-n-alpha-1"
        :class="{ 'bg-n-alpha-1': isOpen }"
        :title="currentAccount.name"
        @click="toggle"
      >
        <Logo class="size-7" />
      </button>
      <!-- Expanded view: Account name trigger -->
      <button
        v-else
        id="sidebar-account-switcher"
        :data-account-id="accountId"
        aria-haspopup="listbox"
        aria-controls="account-options"
        class="flex items-center gap-2 justify-between w-full rounded-lg px-2"
        :class="[
          isOpen && 'bg-n-alpha-1',
          showAccountSwitcher
            ? 'hover:bg-n-alpha-1 cursor-pointer'
            : 'cursor-default',
        ]"
        @click="() => showAccountSwitcher && toggle()"
      >
        <span
          class="text-sm font-medium leading-5 text-n-slate-12 truncate"
          aria-live="polite"
        >
          {{ currentAccount.name }}
        </span>

        <span
          v-if="showAccountSwitcher"
          aria-hidden="true"
          class="i-lucide-chevron-down size-4 text-n-slate-10 flex-shrink-0"
        />
      </button>
    </template>
    <DropdownBody
      v-if="showAccountSwitcher || isCollapsed"
      class="min-w-80 z-50 max-h-[80vh] overflow-y-auto"
    >
      <DropdownSection :title="t('SIDEBAR_ITEMS.SWITCH_ACCOUNT')">
        <div v-if="showSearch" class="px-2 pt-1 pb-2">
          <div class="relative">
            <span
              aria-hidden="true"
              class="i-lucide-search size-4 text-n-slate-10 absolute top-1/2 -translate-y-1/2 ltr:left-2 rtl:right-2"
            />
            <input
              ref="searchInputRef"
              v-model="searchQuery"
              type="text"
              autofocus
              :placeholder="
                t('SIDEBAR_ITEMS.ACCOUNT_SWITCHER_SEARCH_PLACEHOLDER')
              "
              :aria-label="
                t('SIDEBAR_ITEMS.ACCOUNT_SWITCHER_SEARCH_PLACEHOLDER')
              "
              class="w-full text-sm bg-n-alpha-1 text-n-slate-12 placeholder:text-n-slate-10 border border-n-strong focus:border-n-brand rounded-md py-1.5 ltr:pl-8 rtl:pr-8 ltr:pr-2 rtl:pl-2 outline-none"
              @keydown.esc.stop="searchQuery = ''"
            />
          </div>
        </div>
        <div
          v-if="showSearch && filteredAccounts.length === 0"
          class="px-3 py-3 text-sm text-n-slate-11 text-center"
        >
          {{ t('SIDEBAR_ITEMS.ACCOUNT_SWITCHER_NO_RESULTS') }}
        </div>
        <DropdownItem
          v-for="account in filteredAccounts"
          :id="`account-${account.id}`"
          :key="account.id"
          class="cursor-pointer"
          @click="onChangeAccount(account.id)"
        >
          <template #label>
            <div
              :for="account.name"
              class="text-left rtl:text-right flex gap-2 items-center"
            >
              <span
                class="text-n-slate-12 max-w-36 truncate min-w-0"
                :title="account.name"
              >
                {{ account.name }}
              </span>
              <div class="flex-shrink-0 w-px h-3 bg-n-strong" />
              <span
                class="text-n-slate-11 max-w-24 truncate capitalize"
                :title="account.name"
              >
                {{
                  account.custom_role_id
                    ? account.custom_role.name
                    : account.role
                }}
              </span>
            </div>
            <Icon
              v-show="account.id === accountId"
              icon="i-lucide-check"
              class="text-n-teal-11 size-5"
            />
          </template>
        </DropdownItem>
      </DropdownSection>
      <DropdownItem v-if="globalConfig.createNewAccountFromDashboard">
        <ButtonNext
          color="slate"
          variant="faded"
          class="w-full"
          size="sm"
          @click="emitNewAccount"
        >
          {{ t('CREATE_ACCOUNT.NEW_ACCOUNT') }}
        </ButtonNext>
      </DropdownItem>
    </DropdownBody>
  </DropdownContainer>
</template>
