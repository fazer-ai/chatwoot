import {
  processVariable,
  buildWhatsAppProcessedParams,
  findComponentByType,
  COMPONENT_TYPES,
} from '@chatwoot/utils';

// Constants and pure template helpers are shared with the mobile app via
// @chatwoot/utils so the logic lives in one place.
export {
  MEDIA_FORMATS,
  COMPONENT_TYPES,
  findComponentByType,
  processVariable,
  renderTemplatePreview,
} from '@chatwoot/utils';

export const DEFAULT_LANGUAGE = 'en';
export const DEFAULT_CATEGORY = 'UTILITY';

export const allKeysRequired = value => {
  const keys = Object.keys(value);
  return keys.every(key => value[key]);
};

export const replaceTemplateVariables = (templateText, processedParams) => {
  return templateText.replace(/{{([^}]+)}}/g, (match, variable) => {
    const variableKey = processVariable(variable);
    return processedParams.body?.[variableKey] || `{{${variable}}}`;
  });
};

// The media-header flag is derived from the template inside the shared helper;
// the second argument is kept for backwards-compatible call sites.
export const buildTemplateParameters = template => {
  const params = buildWhatsAppProcessedParams(template);

  if (params.header) {
    // Pre-fill with the sample media URL that ships with the template
    // (components[].example.header_handle[0]) so the agent doesn't have to
    // paste it manually. The field stays editable in the parser.
    const headerComponent = findComponentByType(
      template,
      COMPONENT_TYPES.HEADER
    );
    params.header.media_url =
      headerComponent?.example?.header_handle?.[0] || '';
  }

  return params;
};
