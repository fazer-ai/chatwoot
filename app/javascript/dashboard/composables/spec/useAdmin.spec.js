import { ref } from 'vue';
import { useAdmin } from '../useAdmin';
import { useStoreGetters } from 'dashboard/composables/store';

vi.mock('dashboard/composables/store');

describe('useAdmin', () => {
  it('returns true if the current user is an administrator', () => {
    useStoreGetters.mockReturnValue({
      getCurrentRole: ref('administrator'),
    });

    const { isAdmin } = useAdmin();
    expect(isAdmin.value).toBe(true);
  });

  it('returns false if the current user is not an administrator', () => {
    useStoreGetters.mockReturnValue({
      getCurrentRole: ref('user'),
    });

    const { isAdmin } = useAdmin();
    expect(isAdmin.value).toBe(false);
  });

  it('returns false if the current user role is null', () => {
    useStoreGetters.mockReturnValue({
      getCurrentRole: ref(null),
    });

    const { isAdmin } = useAdmin();
    expect(isAdmin.value).toBe(false);
  });

  it('returns false if the current user role is undefined', () => {
    useStoreGetters.mockReturnValue({
      getCurrentRole: ref(undefined),
    });

    const { isAdmin } = useAdmin();
    expect(isAdmin.value).toBe(false);
  });

  it('returns false if the current user role is an empty string', () => {
    useStoreGetters.mockReturnValue({
      getCurrentRole: ref(''),
    });

    const { isAdmin } = useAdmin();
    expect(isAdmin.value).toBe(false);
  });

  it('returns isManager true only when the current user is a manager', () => {
    useStoreGetters.mockReturnValue({
      getCurrentRole: ref('manager'),
    });

    const { isAdmin, isManager } = useAdmin();
    expect(isManager.value).toBe(true);
    expect(isAdmin.value).toBe(false);
  });

  it('returns isManager false for non-manager roles', () => {
    useStoreGetters.mockReturnValue({
      getCurrentRole: ref('agent'),
    });

    const { isManager } = useAdmin();
    expect(isManager.value).toBe(false);
  });
});
