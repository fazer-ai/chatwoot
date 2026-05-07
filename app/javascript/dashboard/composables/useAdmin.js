import { computed } from 'vue';
import { useStoreGetters } from 'dashboard/composables/store';

/**
 * Composable to expose role-based flags for the current user.
 */
export function useAdmin() {
  const getters = useStoreGetters();

  const currentUserRole = computed(() => getters.getCurrentRole.value);
  const isAdmin = computed(() => currentUserRole.value === 'administrator');
  const isManager = computed(() => currentUserRole.value === 'manager');

  return {
    isAdmin,
    isManager,
  };
}
