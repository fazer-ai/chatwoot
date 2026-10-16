import { MESSAGE_STATUS, MESSAGE_TYPE } from 'shared/constants/messages';
import { INBOX_TYPES } from 'dashboard/helper/inbox';
import {
  CAPABILITIES,
  hasCapability,
  isSessionProvider,
} from 'dashboard/helper/whatsappSession';

// Mirrors ContactInbox::WHATSAPP_MISSING_RECHECK_AFTER on the server, which is the one
// that decides: asking earlier only costs a request that changes nothing.
export const WHATSAPP_MISSING_RECHECK_AFTER_MS = 6 * 60 * 60 * 1000;

const REACHED_STATUSES = [MESSAGE_STATUS.DELIVERED, MESSAGE_STATUS.READ];

// A reply from the contact, or a receipt from their phone, proves the number has WhatsApp.
// The server clears the flag when either lands; reading the thread too keeps the warning
// from lingering on screen until the next reload catches up.
export const hasReachedContact = (messages = []) =>
  messages.some(
    ({ message_type: type, status }) =>
      type === MESSAGE_TYPE.INCOMING ||
      (type === MESSAGE_TYPE.OUTGOING && REACHED_STATUSES.includes(status))
  );

// When the conversation's number was last found to have no WhatsApp account (unix
// seconds), or null when there is nothing to warn about.
export const whatsappMissingCheckedAt = conversation => {
  const checkedAt = conversation?.whatsapp_missing_checked_at;
  if (!checkedAt || hasReachedContact(conversation.messages)) return null;
  return checkedAt;
};

export const isWhatsappMissingRecheckDue = (checkedAt, now = Date.now()) =>
  !!checkedAt && now - checkedAt * 1000 >= WHATSAPP_MISSING_RECHECK_AFTER_MS;

// Whether the compose form can ask this inbox about a number right now. A session that is
// not open has nobody to answer, and an unanswered check must not read as "no WhatsApp".
// Takes the compose form's inbox, whose keys are camelCased.
export const canCheckWhatsappNumber = inbox =>
  inbox?.channelType === INBOX_TYPES.WHATSAPP &&
  isSessionProvider(inbox.provider) &&
  hasCapability(inbox, CAPABILITIES.CHECK_NUMBER) &&
  inbox.providerConnection?.connection === 'open';
