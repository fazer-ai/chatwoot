import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { KANBAN_PRIORITIES } from '../constants';

export function useKanban() {
  const { t } = useI18n();

  const priorities = computed(() =>
    KANBAN_PRIORITIES.map(priority => ({
      ...priority,
      name: t(
        `KANBAN.PRIORITY.${priority.id ? priority.id.toUpperCase() : 'NONE'}`
      ),
    }))
  );

  return {
    priorities,
  };
}
