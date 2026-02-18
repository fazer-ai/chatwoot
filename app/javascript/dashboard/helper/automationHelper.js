import {
  OPERATOR_TYPES_1,
  OPERATOR_TYPES_3,
  OPERATOR_TYPES_4,
} from 'dashboard/routes/dashboard/settings/automation/operators';
import {
  DEFAULT_MESSAGE_CREATED_CONDITION,
  DEFAULT_CONVERSATION_CONDITION,
  DEFAULT_OTHER_CONDITION,
  DEFAULT_KANBAN_CONDITION,
  DEFAULT_ACTIONS,
} from 'dashboard/constants/automation';
import filterQueryGenerator from './filterQueryGenerator';
import actionQueryGenerator from './actionQueryGenerator';

export const KANBAN_EVENTS = [
  'kanban_task_created',
  'kanban_task_updated',
  'kanban_task_completed',
  'kanban_task_cancelled',
];

/**
 * Extracts board ID from various value formats used in automation conditions.
 * Values can be: object with id, array of objects/ids, or primitive.
 * @param {*} values - The values from a condition
 * @returns {string|number|null} The extracted board ID or null
 */
export const extractBoardIdFromValues = values => {
  if (!values) return null;
  if (typeof values === 'object' && values !== null && !Array.isArray(values)) {
    return values.id;
  }
  if (Array.isArray(values)) {
    if (values.length === 0) return null;
    return values[0]?.id ?? values[0];
  }
  return values;
};

/**
 * Gets steps from a board, handling both API response formats.
 * @param {Object} board - The board object
 * @returns {Array} The steps array or empty array
 */
export const getBoardSteps = board => {
  return board?.steps || board?.steps_summary || [];
};

/**
 * Finds the selected board ID from automation conditions.
 * @param {Array} conditions - The automation conditions
 * @returns {string|number|null} The board ID or null
 */
export const getSelectedBoardId = conditions => {
  const boardCondition = (conditions || []).find(
    c => c.attribute_key === 'kanban_board_id'
  );
  return extractBoardIdFromValues(boardCondition?.values);
};

/**
 * Finds the selected board ID from automation actions (assign_to_board action).
 * @param {Array} actions - The automation actions
 * @returns {string|number|null} The board ID or null
 */
export const getSelectedBoardIdFromActions = actions => {
  const boardAction = (actions || []).find(
    a => a.action_name === 'assign_to_board'
  );
  if (!boardAction?.action_params) return null;

  const param = Array.isArray(boardAction.action_params)
    ? boardAction.action_params[0]
    : boardAction.action_params;

  return extractBoardIdFromValues(param);
};

export const getCustomAttributeInputType = key => {
  const customAttributeMap = {
    date: 'date',
    text: 'plain_text',
    list: 'search_select',
    checkbox: 'search_select',
  };

  return customAttributeMap[key] || 'plain_text';
};

export const isACustomAttribute = (customAttributes, key) => {
  return customAttributes.find(attr => {
    return attr.attribute_key === key;
  });
};

export const getCustomAttributeListDropdownValues = (
  customAttributes,
  type
) => {
  return customAttributes
    .find(attr => attr.attribute_key === type)
    .attribute_values.map(item => {
      return {
        id: item,
        name: item,
      };
    });
};

export const isCustomAttributeCheckbox = (customAttributes, key) => {
  return customAttributes.find(attr => {
    return (
      attr.attribute_key === key && attr.attribute_display_type === 'checkbox'
    );
  });
};

export const isCustomAttributeList = (customAttributes, type) => {
  return customAttributes.find(attr => {
    return (
      attr.attribute_key === type && attr.attribute_display_type === 'list'
    );
  });
};

export const getOperatorTypes = key => {
  const operatorMap = {
    list: OPERATOR_TYPES_1,
    text: OPERATOR_TYPES_3,
    number: OPERATOR_TYPES_1,
    link: OPERATOR_TYPES_1,
    date: OPERATOR_TYPES_4,
    checkbox: OPERATOR_TYPES_1,
  };

  return operatorMap[key] || OPERATOR_TYPES_1;
};

export const generateCustomAttributeTypes = (customAttributes, type) => {
  return customAttributes.map(attr => {
    return {
      key: attr.attribute_key,
      name: attr.attribute_display_name,
      inputType: getCustomAttributeInputType(attr.attribute_display_type),
      filterOperators: getOperatorTypes(attr.attribute_display_type),
      customAttributeType: type,
    };
  });
};

export const generateConditionOptions = (options, key = 'id') => {
  if (!options || !Array.isArray(options)) return [];
  return options.map(i => {
    return {
      id: i[key],
      name: i.title,
    };
  });
};

/**
 * Finds the selected board object from conditions.
 * @param {Array} kanbanBoards - List of kanban boards
 * @param {Array} conditions - Automation conditions
 * @returns {Object|null} The selected board or null
 */
const findSelectedBoardFromConditions = (kanbanBoards, conditions) => {
  const selectedBoardId = getSelectedBoardId(conditions);
  if (!selectedBoardId) return null;

  return (kanbanBoards || []).find(
    b => b.id === Number(selectedBoardId) || b.id === selectedBoardId
  );
};

/**
 * Finds the selected board object from actions (assign_to_board action).
 * @param {Array} kanbanBoards - List of kanban boards
 * @param {Array} actions - Automation actions
 * @returns {Object|null} The selected board or null
 */
const findSelectedBoardFromActions = (kanbanBoards, actions) => {
  const selectedBoardId = getSelectedBoardIdFromActions(actions);
  if (!selectedBoardId) return null;

  return (kanbanBoards || []).find(
    b => b.id === Number(selectedBoardId) || b.id === selectedBoardId
  );
};

/**
 * Finds the selected board - checks conditions first (for kanban events),
 * then falls back to actions (for conversation events with assign_to_board).
 * @param {Array} kanbanBoards - List of kanban boards
 * @param {Array} conditions - Automation conditions
 * @param {Array} actions - Automation actions
 * @returns {Object|null} The selected board or null
 */
const findSelectedBoard = (kanbanBoards, conditions, actions) => {
  const boardFromConditions = findSelectedBoardFromConditions(
    kanbanBoards,
    conditions
  );
  if (boardFromConditions) return boardFromConditions;

  return findSelectedBoardFromActions(kanbanBoards, actions);
};

/**
 * Gets step options from a board for dropdowns.
 * For move_to_step action, prioritizes the assign_to_board target board
 * to enable moving tasks to steps on a different board.
 * @param {Array} kanbanBoards - List of kanban boards
 * @param {Array} conditions - Automation conditions to find selected board
 * @param {Array} actions - Automation actions to find selected board
 * @returns {Array} Formatted step options for dropdown
 */
const getKanbanStepOptions = (kanbanBoards, conditions, actions) => {
  // Prioritize assign_to_board action's target board for move_to_step
  const boardFromActions = findSelectedBoardFromActions(kanbanBoards, actions);
  const board =
    boardFromActions ||
    findSelectedBoardFromConditions(kanbanBoards, conditions);
  if (!board) return [];

  const steps = getBoardSteps(board);

  return steps
    .filter(step => !step.cancelled)
    .map(step => ({ id: step.id, name: step.name }));
};

export const getActionOptions = ({
  agents,
  teams,
  labels,
  slaPolicies,
  kanbanBoards,
  type,
  addNoneToListFn,
  priorityOptions,
  conditions,
  actions,
}) => {
  const kanbanStepOptions =
    type === 'move_to_step'
      ? getKanbanStepOptions(kanbanBoards, conditions, actions)
      : [];

  const kanbanBoardOptions = (kanbanBoards || []).map(board => ({
    id: board.id,
    name: board.name,
  }));

  const selectedBoard = findSelectedBoard(kanbanBoards, conditions, actions);
  const boardAgents = selectedBoard?.assigned_agents || agents;

  const actionsMap = {
    assign_agent: addNoneToListFn ? addNoneToListFn(boardAgents) : boardAgents,
    assign_team: addNoneToListFn ? addNoneToListFn(teams) : teams,
    send_email_to_team: teams,
    add_label: generateConditionOptions(labels, 'title'),
    remove_label: generateConditionOptions(labels, 'title'),
    change_priority: priorityOptions,
    add_sla: slaPolicies,
    move_to_step: kanbanStepOptions,
    assign_to_board: kanbanBoardOptions,
  };
  return actionsMap[type];
};

export const getConditionOptions = ({
  agents,
  booleanFilterOptions,
  campaigns,
  contacts,
  countries,
  customAttributes,
  inboxes,
  languages,
  labels,
  statusFilterOptions,
  teams,
  kanbanBoards,
  type,
  priorityOptions,
  messageTypeOptions,
  conditions,
}) => {
  if (isCustomAttributeCheckbox(customAttributes, type)) {
    return booleanFilterOptions;
  }

  if (isCustomAttributeList(customAttributes, type)) {
    return getCustomAttributeListDropdownValues(customAttributes, type);
  }

  const kanbanBoardOptions = (kanbanBoards || []).map(board => ({
    id: board.id,
    name: board.name,
  }));

  const kanbanStepOptions =
    type === 'kanban_step_id'
      ? getKanbanStepOptions(kanbanBoards, conditions, [])
      : [];

  const selectedBoard = findSelectedBoardFromConditions(
    kanbanBoards,
    conditions
  );
  const boardAgents = selectedBoard?.assigned_agents || agents;
  const boardInboxes = selectedBoard?.assigned_inboxes || inboxes;

  const conditionFilterMaps = {
    status: statusFilterOptions,
    assignee_id: boardAgents,
    contact: contacts,
    inbox_id: boardInboxes,
    team_id: teams,
    campaigns: generateConditionOptions(campaigns),
    browser_language: languages,
    conversation_language: languages,
    country_code: countries,
    message_type: messageTypeOptions,
    priority: priorityOptions,
    labels: generateConditionOptions(labels, 'title'),
    kanban_board_id: kanbanBoardOptions,
    kanban_step_id: kanbanStepOptions,
  };

  return conditionFilterMaps[type];
};

export const getFileName = (action, files = []) => {
  const scheduledParams = Array.isArray(action.action_params)
    ? action.action_params[0]
    : action.action_params;
  const blobId =
    action.action_name === 'create_scheduled_message'
      ? scheduledParams?.blob_id
      : action.action_params?.[0];
  if (!blobId) return '';
  if (
    action.action_name === 'send_attachment' ||
    action.action_name === 'create_scheduled_message'
  ) {
    const file = files.find(
      item => item.blob_id?.toString() === blobId.toString()
    );
    if (file) return file.filename.toString();
  }
  return '';
};

export const getDefaultConditions = eventName => {
  if (eventName === 'message_created') {
    return structuredClone(DEFAULT_MESSAGE_CREATED_CONDITION);
  }
  if (
    eventName === 'conversation_opened' ||
    eventName === 'conversation_resolved'
  ) {
    return structuredClone(DEFAULT_CONVERSATION_CONDITION);
  }
  if (KANBAN_EVENTS.includes(eventName)) {
    return structuredClone(DEFAULT_KANBAN_CONDITION);
  }
  return structuredClone(DEFAULT_OTHER_CONDITION);
};

export const getDefaultActions = () => {
  return structuredClone(DEFAULT_ACTIONS);
};

export const filterCustomAttributes = customAttributes => {
  return customAttributes.map(attr => {
    return {
      key: attr.attribute_key,
      name: attr.attribute_display_name,
      type: attr.attribute_display_type,
    };
  });
};

export const getStandardAttributeInputType = (automationTypes, event, key) => {
  return automationTypes[event].conditions.find(item => item.key === key)
    .inputType;
};

export const generateAutomationPayload = payload => {
  const automation = JSON.parse(JSON.stringify(payload));
  automation.conditions[automation.conditions.length - 1].query_operator = null;
  automation.conditions = filterQueryGenerator(automation.conditions).payload;
  automation.actions = actionQueryGenerator(automation.actions);
  return automation;
};

export const isCustomAttribute = (attrs, key) => {
  return attrs.find(attr => attr.key === key);
};

export const generateCustomAttributes = (
  // eslint-disable-next-line default-param-last
  conversationAttributes = [],
  // eslint-disable-next-line default-param-last
  contactAttributes = [],
  conversationlabel,
  contactlabel
) => {
  const customAttributes = [];
  if (conversationAttributes.length) {
    customAttributes.push(
      {
        key: `conversation_custom_attribute`,
        name: conversationlabel,
        disabled: true,
      },
      ...conversationAttributes
    );
  }
  if (contactAttributes.length) {
    customAttributes.push(
      {
        key: `contact_custom_attribute`,
        name: contactlabel,
        disabled: true,
      },
      ...contactAttributes
    );
  }
  return customAttributes;
};

/**
 * Get attributes for a given key from automation types.
 * @param {Object} automationTypes - Object containing automation types.
 * @param {string} key - The key to get attributes for.
 * @returns {Array} Array of condition objects for the given key.
 */
export const getAttributes = (automationTypes, key) => {
  return automationTypes[key].conditions;
};

/**
 * Get the automation type for a given key.
 * @param {Object} automationTypes - Object containing automation types.
 * @param {Object} automation - The automation object.
 * @param {string} key - The key to get the automation type for.
 * @returns {Object} The automation type object.
 */
export const getAutomationType = (automationTypes, automation, key) => {
  return automationTypes[automation.event_name].conditions.find(
    condition => condition.key === key
  );
};

/**
 * Get the input type for a given key.
 * @param {Array} allCustomAttributes - Array of all custom attributes.
 * @param {Object} automationTypes - Object containing automation types.
 * @param {Object} automation - The automation object.
 * @param {string} key - The key to get the input type for.
 * @returns {string} The input type.
 */
export const getInputType = (
  allCustomAttributes,
  automationTypes,
  automation,
  key
) => {
  const customAttribute = isACustomAttribute(allCustomAttributes, key);
  if (customAttribute) {
    return getCustomAttributeInputType(customAttribute.attribute_display_type);
  }
  const type = getAutomationType(automationTypes, automation, key);
  return type?.inputType ?? '';
};

/**
 * Get operators for a given key.
 * @param {Array} allCustomAttributes - Array of all custom attributes.
 * @param {Object} automationTypes - Object containing automation types.
 * @param {Object} automation - The automation object.
 * @param {string} mode - The mode ('edit' or other).
 * @param {string} key - The key to get operators for.
 * @returns {Array} Array of operators.
 */
export const getOperators = (
  allCustomAttributes,
  automationTypes,
  automation,
  mode,
  key
) => {
  if (mode === 'edit') {
    const customAttribute = isACustomAttribute(allCustomAttributes, key);
    if (customAttribute) {
      return getOperatorTypes(customAttribute.attribute_display_type);
    }
  }
  const type = getAutomationType(automationTypes, automation, key);
  return type?.filterOperators ?? [];
};

/**
 * Get the custom attribute type for a given key.
 * @param {Object} automationTypes - Object containing automation types.
 * @param {Object} automation - The automation object.
 * @param {string} key - The key to get the custom attribute type for.
 * @returns {string} The custom attribute type.
 */
export const getCustomAttributeType = (automationTypes, automation, key) => {
  return (
    automationTypes[automation.event_name].conditions.find(i => i.key === key)
      ?.customAttributeType ?? ''
  );
};

/**
 * Determine if an action input should be shown.
 * @param {Array} automationActionTypes - Array of automation action type objects.
 * @param {string} action - The action to check.
 * @returns {boolean} True if the action input should be shown, false otherwise.
 */
export const showActionInput = (automationActionTypes, action) => {
  if (
    action === 'send_email_to_team' ||
    action === 'send_message' ||
    action === 'create_scheduled_message'
  )
    return false;
  const type = automationActionTypes.find(i => i.key === action)?.inputType;
  return !!type;
};
