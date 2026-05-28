import wootConstants from 'dashboard/constants/globals';
import { ASSIGNEE_TYPE_TAB_PERMISSIONS } from 'dashboard/constants/permissions';

export const hasPermissions = (
  requiredPermissions = [],
  availablePermissions = []
) => {
  return requiredPermissions.some(permission =>
    availablePermissions.includes(permission)
  );
};

export const getCurrentAccount = ({ accounts } = {}, accountId = null) => {
  return accounts.find(account => Number(account.id) === Number(accountId));
};

export const getUserPermissions = (user, accountId) => {
  const currentAccount = getCurrentAccount(user, accountId) || {};
  return currentAccount.permissions || [];
};

export const getUserRole = (user, accountId) => {
  const currentAccount = getCurrentAccount(user, accountId) || {};
  if (currentAccount.custom_role_id) {
    return 'custom_role';
  }

  return currentAccount.role || 'agent';
};

/**
 * Filters and transforms items based on user permissions.
 *
 * @param {Object} items - An object containing items to be filtered.
 * @param {Array} userPermissions - Array of permissions the user has.
 * @param {Function} getPermissions - Function to extract required permissions from an item.
 * @param {Function} [transformItem] - Optional function to transform each item after filtering.
 * @returns {Array} Filtered and transformed items.
 */
export const filterItemsByPermission = (
  items,
  userPermissions,
  getPermissions,
  transformItem = (key, item) => ({ key, ...item })
) => {
  // Helper function to check if an item has the required permissions
  const hasRequiredPermissions = item => {
    const requiredPermissions = getPermissions(item);
    return (
      requiredPermissions.length === 0 ||
      hasPermissions(requiredPermissions, userPermissions)
    );
  };

  return Object.entries(items)
    .filter(([, item]) => hasRequiredPermissions(item)) // Keep only items with required permissions
    .map(([key, item]) => transformItem(key, item)); // Transform each remaining item
};

/**
 * Resolves which conversation assignee tabs (Mine/Unassigned/All) a user may
 * see, applying the account-level hide-tabs toggles for basic agents.
 *
 * Mention/Participating views are scoped to conversations the user can already
 * see, so the toggles must not apply there: hiding Unassigned/All would strand
 * chats not assigned to the agent under an unreachable tab. Admins and custom
 * roles are never affected.
 *
 * @param {Object} params
 * @param {String} params.conversationType - Current view type (mention/participating/...).
 * @param {String} params.userRole - Resolved user role for the account.
 * @param {Object} [params.accountSettings] - Account settings holding the toggles.
 * @returns {Object} The visible subset of ASSIGNEE_TYPE_TAB_PERMISSIONS.
 */
export const getVisibleAssigneeTabPermissions = ({
  conversationType,
  userRole,
  accountSettings = {},
} = {}) => {
  const { MENTION, PARTICIPATING } = wootConstants.CONVERSATION_TYPE;
  const isPersonalScopeView = [MENTION, PARTICIPATING].includes(
    conversationType
  );

  if (isPersonalScopeView || userRole !== 'agent') {
    return ASSIGNEE_TYPE_TAB_PERMISSIONS;
  }

  const hideUnassigned = Boolean(accountSettings.hide_agent_unassigned_tab);
  const hideAll = hideUnassigned || Boolean(accountSettings.hide_agent_all_tab);

  if (!hideUnassigned && !hideAll) return ASSIGNEE_TYPE_TAB_PERMISSIONS;

  const { unassigned, all, ...rest } = ASSIGNEE_TYPE_TAB_PERMISSIONS;
  return {
    ...rest,
    ...(hideUnassigned ? {} : { unassigned }),
    ...(hideAll ? {} : { all }),
  };
};
