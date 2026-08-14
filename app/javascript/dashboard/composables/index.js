import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import analyticsHelper from 'dashboard/helper/AnalyticsHelper/index';

/**
 * Custom hook to track events
 */
export const useTrack = (...args) => {
  try {
    return analyticsHelper.track(...args);
  } catch (error) {
    // Ignore this, tracking is not mission critical
  }

  return null;
};

/**
 * Emits a toast message event using a global emitter.
 * @param {string} message - The message to be displayed in the toast.
 * @param {Object|null} action - Optional callback function or object to execute.
 */
export const useAlert = (message, action = null) => {
  emitter.emit('newToastMessage', { message, action });
};

let pendingAlertCounter = 0;

/**
 * Shows a persistent toast that stays visible until explicitly dismissed.
 * Useful for long-running operations (e.g. "Adding member...").
 * @param {string} message - The message to display while the operation is in progress.
 * @returns {Function} dismiss - Call this function to remove the persistent toast.
 */
export const usePendingAlert = message => {
  pendingAlertCounter += 1;
  const key = `pending-${Date.now()}-${pendingAlertCounter}`;
  emitter.emit('newToastMessage', {
    message,
    action: { persistent: true, key },
  });
  return () => emitter.emit('dismissToastMessage', { key });
};

/**
 * Opens the dialog that tells the agent a conversation is already someone
 * else's. A toast is the wrong surface here: it fades on its own and the agent
 * is about to start working a lead that is not theirs.
 * @param {string} agentName - The agent currently handling the conversation.
 */
export const useAssignmentConflict = agentName => {
  emitter.emit(BUS_EVENTS.ASSIGNMENT_CONFLICT, { agentName });
};

/**
 * Reads the assignment conflict out of a rejected assignment request, if that
 * is what it is. Returns null for any other failure so the caller can fall back
 * to its regular error handling.
 * @param {Object} error - The rejected axios error.
 * @returns {string|null} The agent currently handling the conversation.
 */
export const assignmentConflictAgent = error => {
  if (error?.response?.status !== 409) return null;

  return error.response.data?.agent_name ?? '';
};
