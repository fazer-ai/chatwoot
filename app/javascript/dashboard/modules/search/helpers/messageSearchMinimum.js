// MESSAGE_SEARCH_MIN_QUERY_LENGTH: a term shorter than the installation's minimum does not search
// messages (0, the default, means no minimum). Contacts, conversations and articles are not affected.
export const isBelowMessageSearchMinimum = (query, minimum) => {
  const term = (query || '').trim();
  return term.length > 0 && term.length < minimum;
};
