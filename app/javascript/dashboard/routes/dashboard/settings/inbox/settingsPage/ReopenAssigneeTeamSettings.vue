<script setup>
import { ref, computed, watch } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import SettingsToggleSection from 'dashboard/components-next/Settings/SettingsToggleSection.vue';
import Select from 'dashboard/components-next/select/Select.vue';

const props = defineProps({
  inbox: {
    type: Object,
    default: () => ({}),
  },
});

const NO_TEAM = '';

const store = useStore();
const { t } = useI18n();

const teams = computed(() => store.getters['teams/getTeams']);

const teamOptions = computed(() => [
  { value: NO_TEAM, label: t('INBOX_MGMT.ASSIGNMENT.REOPEN_TEAM.NONE') },
  ...teams.value.map(({ id, name }) => ({ value: id, label: name })),
]);

// A deleted team turns the setting off on the server, but the cached inbox can
// still carry its id until the list refetches; show that as "None".
const savedTeamId = () => {
  const id = props.inbox.reopen_assignee_team_id;
  return teams.value.some(team => team.id === id) ? id : NO_TEAM;
};

const selectedTeamId = ref(savedTeamId());

watch(
  [() => props.inbox.id, () => props.inbox.reopen_assignee_team_id, teams],
  () => {
    selectedTeamId.value = savedTeamId();
  }
);

const handleChange = async teamId => {
  try {
    await store.dispatch('inboxes/updateInbox', {
      id: props.inbox.id,
      formData: false,
      reopen_assignee_team_id: teamId === NO_TEAM ? null : teamId,
    });
    useAlert(t('INBOX_MGMT.EDIT.API.SUCCESS_MESSAGE'));
  } catch (error) {
    selectedTeamId.value = savedTeamId();
    useAlert(t('INBOX_MGMT.EDIT.API.ERROR_MESSAGE'));
  }
};
</script>

<template>
  <SettingsToggleSection
    hide-toggle
    compact
    :header="$t('INBOX_MGMT.ASSIGNMENT.REOPEN_TEAM.TITLE')"
    :description="$t('INBOX_MGMT.ASSIGNMENT.REOPEN_TEAM.DESCRIPTION')"
  >
    <template #hiddenToggle>
      <Select
        v-model="selectedTeamId"
        :options="teamOptions"
        :aria-label="$t('INBOX_MGMT.ASSIGNMENT.REOPEN_TEAM.TITLE')"
        @update:model-value="handleChange"
      />
    </template>
  </SettingsToggleSection>
</template>
