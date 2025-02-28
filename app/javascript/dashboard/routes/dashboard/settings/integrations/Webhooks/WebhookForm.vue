<script>
import { useVuelidate } from '@vuelidate/core';
import { required, url, minLength } from '@vuelidate/validators';
import wootConstants from 'dashboard/constants/globals';
import { getI18nKey } from 'dashboard/routes/dashboard/settings/helper/settingsHelper';
import MultiselectDropdown from 'shared/components/ui/MultiselectDropdown.vue';
import { useMapGetter } from 'dashboard/composables/store';

const { EXAMPLE_WEBHOOK_URL } = wootConstants;

const SUPPORTED_WEBHOOK_EVENTS = [
  'conversation_created',
  'conversation_status_changed',
  'conversation_updated',
  'message_created',
  'message_updated',
  'webwidget_triggered',
  'contact_created',
  'contact_updated',
];

export default {
  components: {
    MultiselectDropdown,
  },
  props: {
    value: {
      type: Object,
      default: () => ({}),
    },
    isSubmitting: {
      type: Boolean,
      default: false,
    },
    submitLabel: {
      type: String,
      required: true,
    },
    isEditing: {
      type: Boolean,
      default: false,
    },
  },
  emits: ['submit', 'cancel'],
  setup() {
    return {
      v$: useVuelidate(),
      inboxes: useMapGetter('inboxes/getInboxes'),
    };
  },
  validations: {
    url: {
      required,
      minLength: minLength(7),
      url,
    },
    subscriptions: {
      required,
    },
  },
  data() {
    return {
      url: this.value.url || '',
      name: this.value.name || '',
      inboxId: this.value.inboxId || '',
      subscriptions: this.value.subscriptions || [],
      supportedWebhookEvents: SUPPORTED_WEBHOOK_EVENTS,
      selectedInbox: this.value.inbox || null,
    };
  },
  computed: {
    inboxesList() {
      if (this.selectedInbox?.id) {
        return [
          {
            id: 0,
            name: this.$t(
              'INTEGRATION_SETTINGS.WEBHOOK.FORM.INBOX.PLACEHOLDER'
            ),
          },
          ...this.inboxes,
        ];
      }
      return this.inboxes;
    },
    webhookURLInputPlaceholder() {
      return this.$t(
        'INTEGRATION_SETTINGS.WEBHOOK.FORM.END_POINT.PLACEHOLDER',
        {
          webhookExampleURL: EXAMPLE_WEBHOOK_URL,
        }
      );
    },
    webhookNameInputPlaceholder() {
      return this.$t('INTEGRATION_SETTINGS.WEBHOOK.FORM.NAME.PLACEHOLDER');
    },
  },
  methods: {
    onSubmit() {
      this.$emit('submit', {
        url: this.url,
        name: this.name,
        inbox_id: this.inboxId || null,
        subscriptions: this.subscriptions,
      });
    },
    onClickAssignInbox(inbox) {
      this.selectedInbox = inbox;
      this.inboxId = inbox.id;
    },
    getI18nKey,
  },
};
</script>

<template>
  <form class="flex flex-col w-full" @submit.prevent="onSubmit">
    <label :class="{ error: v$.url.$error }">
      {{ $t('INTEGRATION_SETTINGS.WEBHOOK.FORM.END_POINT.LABEL') }}
      <input
        v-model="url"
        type="text"
        name="url"
        :disabled="isEditing"
        :placeholder="webhookURLInputPlaceholder"
        @input="v$.url.$touch"
      />
      <span v-if="v$.url.$error" class="message">
        {{ $t('INTEGRATION_SETTINGS.WEBHOOK.FORM.END_POINT.ERROR') }}
      </span>
    </label>
    <label>
      {{ $t('INTEGRATION_SETTINGS.WEBHOOK.FORM.INBOX.LABEL') }}
      <div class="multiselect-wrap--small">
        <MultiselectDropdown
          :options="inboxesList"
          :selected-item="selectedInbox"
          :multiselector-title="
            $t('INTEGRATION_SETTINGS.WEBHOOK.FORM.INBOX.TITLE')
          "
          :multiselector-placeholder="
            $t('INTEGRATION_SETTINGS.WEBHOOK.FORM.INBOX.PLACEHOLDER')
          "
          :no-search-result="
            $t('INTEGRATION_SETTINGS.WEBHOOK.FORM.INBOX.NO_RESULTS')
          "
          :input-placeholder="
            $t('INTEGRATION_SETTINGS.WEBHOOK.FORM.INBOX.INPUT_PLACEHOLDER')
          "
          :disabled="isEditing"
          button-variant="secondary"
          @select="onClickAssignInbox"
        />
      </div>
    </label>
    <label>
      {{ $t('INTEGRATION_SETTINGS.WEBHOOK.FORM.NAME.LABEL') }}
      <input
        v-model="name"
        type="text"
        name="name"
        :placeholder="webhookNameInputPlaceholder"
      />
    </label>
    <label :class="{ error: v$.url.$error }" class="mb-2">
      {{ $t('INTEGRATION_SETTINGS.WEBHOOK.FORM.SUBSCRIPTIONS.LABEL') }}
    </label>
    <div class="flex flex-col gap-2.5 mb-4">
      <div
        v-for="event in supportedWebhookEvents"
        :key="event"
        class="flex items-center"
      >
        <input
          :id="event"
          v-model="subscriptions"
          type="checkbox"
          :value="event"
          name="subscriptions"
          class="mr-2"
        />
        <label :for="event" class="text-sm">
          {{
            `${$t(
              getI18nKey(
                'INTEGRATION_SETTINGS.WEBHOOK.FORM.SUBSCRIPTIONS.EVENTS',
                event
              )
            )} (${event})`
          }}
        </label>
      </div>
    </div>

    <div class="flex flex-row justify-end w-full gap-2 px-0 py-2">
      <div class="w-full">
        <woot-button
          :disabled="v$.$invalid || isSubmitting"
          :is-loading="isSubmitting"
        >
          {{ submitLabel }}
        </woot-button>
        <woot-button class="button clear" @click.prevent="$emit('cancel')">
          {{ $t('INTEGRATION_SETTINGS.WEBHOOK.FORM.CANCEL') }}
        </woot-button>
      </div>
    </div>
  </form>
</template>
