/**
 * fazer.ai fork translations.
 *
 * Every key under `fazer-ai/locale/<lang>/` belongs to this fork: strings for
 * our own features plus `overrides.json`, which replaces upstream strings.
 * The upstream tree in `../locale/` stays byte-identical to the Chatwoot
 * release we track, so upstream syncs never conflict with our translations.
 *
 * Files are picked up by directory scan, so adding a language means creating
 * one folder and adding a namespace means creating one file. Nothing else
 * changes, which also keeps CE -> Pro merges conflict-free.
 *
 * File naming: a namespace that is entirely ours gets its own file
 * (`kanban.json`, `internalChat.json`); keys we add inside an upstream
 * namespace live in a file named after the upstream file they extend
 * (`conversation.json` extends `../locale/<lang>/conversation.json`).
 */

const isPlainObject = value =>
  typeof value === 'object' && value !== null && !Array.isArray(value);

const deepMerge = (target, source) => {
  const result = { ...target };

  Object.entries(source).forEach(([key, value]) => {
    result[key] =
      isPlainObject(value) && isPlainObject(result[key])
        ? deepMerge(result[key], value)
        : value;
  });

  return result;
};

const buildForkMessages = () => {
  const modules = import.meta.glob('./locale/*/*.json', { eager: true });
  const messages = {};

  // Sorted so `overrides.json` is applied after the file it may collide with,
  // and so the result does not depend on the glob's traversal order.
  Object.keys(modules)
    .sort()
    .forEach(path => {
      const locale = path.split('/')[2];
      const translations = modules[path].default ?? modules[path];
      messages[locale] = deepMerge(messages[locale] ?? {}, translations);
    });

  return messages;
};

export const forkMessages = buildForkMessages();

/**
 * Deep merges the fork translations on top of upstream's, per locale.
 * Locales without a fork folder are returned untouched.
 */
export const withForkMessages = upstreamMessages => {
  const merged = { ...upstreamMessages };

  Object.entries(forkMessages).forEach(([locale, translations]) => {
    merged[locale] = deepMerge(merged[locale] ?? {}, translations);
  });

  return merged;
};

export default withForkMessages;
