<script>
import { mapGetters } from 'vuex';
import { useVuelidate } from '@vuelidate/core';
import { useAlert } from 'dashboard/composables';
import { required } from '@vuelidate/validators';
import router from '../../../../index';
import NextButton from 'dashboard/components-next/button/Button.vue';

import { isPhoneE164OrEmpty } from 'shared/helpers/Validators';

export default {
  components: {
    NextButton,
  },
  props: {
    mode: {
      type: String,
      default: 'create',
      validator: value => ['create', 'convert'].includes(value),
    },
    inbox: {
      type: Object,
      default: null,
    },
  },
  setup() {
    return { v$: useVuelidate() };
  },
  data() {
    const isConvert = this.mode === 'convert';
    return {
      inboxName: isConvert ? this.inbox?.name || '' : '',
      phoneNumber: isConvert ? this.inbox?.phone_number || '' : '',
      apiKey: '',
    };
  },
  computed: {
    ...mapGetters({ uiFlags: 'inboxes/getUIFlags' }),
    isConvertMode() {
      return this.mode === 'convert';
    },
    submitButtonLabel() {
      return this.isConvertMode
        ? this.$t('INBOX_MGMT.CONVERT.SUBMIT_BUTTON')
        : this.$t('INBOX_MGMT.ADD.WHATSAPP.SUBMIT_BUTTON');
    },
  },
  validations: {
    inboxName: { required },
    phoneNumber: { required, isPhoneE164OrEmpty },
    apiKey: { required },
  },
  methods: {
    async createChannel() {
      this.v$.$touch();
      if (this.v$.$invalid) {
        return;
      }

      try {
        if (this.isConvertMode) {
          await this.$store.dispatch('inboxes/convertProvider', {
            inboxId: this.inbox.id,
            provider: 'default',
            providerConfig: { api_key: this.apiKey },
          });

          useAlert(this.$t('INBOX_MGMT.CONVERT.API.SUCCESS_MESSAGE'));
          router.replace({
            name: 'settings_inbox_show',
            params: {
              accountId: router.currentRoute.value.params.accountId,
              inboxId: this.inbox.id,
            },
          });
          return;
        }

        const whatsappChannel = await this.$store.dispatch(
          'inboxes/createChannel',
          {
            name: this.inboxName?.trim(),
            channel: {
              type: 'whatsapp',
              phone_number: this.phoneNumber,
              provider_config: {
                api_key: this.apiKey,
              },
            },
          }
        );

        router.replace({
          name: 'settings_inboxes_add_agents',
          params: {
            page: 'new',
            inbox_id: whatsappChannel.id,
          },
        });
      } catch (error) {
        useAlert(
          error.message ||
            this.$t(
              this.isConvertMode
                ? 'INBOX_MGMT.CONVERT.API.ERROR_MESSAGE'
                : 'INBOX_MGMT.ADD.WHATSAPP.API.ERROR_MESSAGE'
            )
        );
      }
    },
  },
};
</script>

<template>
  <form class="flex flex-wrap flex-col mx-0" @submit.prevent="createChannel()">
    <div class="flex-shrink-0 flex-grow-0">
      <label :class="{ error: v$.inboxName.$error }">
        {{ $t('INBOX_MGMT.ADD.WHATSAPP.INBOX_NAME.LABEL') }}
        <input
          v-model="inboxName"
          type="text"
          :disabled="isConvertMode"
          :placeholder="$t('INBOX_MGMT.ADD.WHATSAPP.INBOX_NAME.PLACEHOLDER')"
          @blur="v$.inboxName.$touch"
        />
        <span v-if="v$.inboxName.$error" class="message">
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.INBOX_NAME.ERROR') }}
        </span>
      </label>
    </div>

    <div class="flex-shrink-0 flex-grow-0">
      <label :class="{ error: v$.phoneNumber.$error }">
        {{ $t('INBOX_MGMT.ADD.WHATSAPP.PHONE_NUMBER.LABEL') }}
        <input
          v-model="phoneNumber"
          type="text"
          :disabled="isConvertMode"
          :placeholder="$t('INBOX_MGMT.ADD.WHATSAPP.PHONE_NUMBER.PLACEHOLDER')"
          @blur="v$.phoneNumber.$touch"
        />
        <span v-if="v$.phoneNumber.$error" class="message">
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.PHONE_NUMBER.ERROR') }}
        </span>
      </label>
    </div>

    <div class="flex-shrink-0 flex-grow-0">
      <label :class="{ error: v$.apiKey.$error }">
        <span>
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.API_KEY.LABEL') }}
        </span>
        <input
          v-model="apiKey"
          type="text"
          :placeholder="$t('INBOX_MGMT.ADD.WHATSAPP.API_KEY.PLACEHOLDER')"
          @blur="v$.apiKey.$touch"
        />
        <span v-if="v$.apiKey.$error" class="message">
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.API_KEY.ERROR') }}
        </span>
      </label>
    </div>

    <div class="w-full">
      <NextButton
        type="submit"
        :label="submitButtonLabel"
        :is-loading="uiFlags.isCreating || uiFlags.isUpdating"
      />
    </div>
  </form>
</template>
