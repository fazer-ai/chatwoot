import { describe, it, expect } from 'vitest';
import { validateAutomation } from '../validations';

describe('validateAutomation', () => {
  it('should return no errors for a valid automation', () => {
    const validAutomation = {
      name: 'Test Automation',
      description: 'A test automation',
      event_name: 'message_created',
      conditions: [
        {
          attribute_key: 'content',
          filter_operator: 'contains',
          values: 'hello',
        },
      ],
      actions: [
        { action_name: 'send_message', action_params: ['Hello there!'] },
      ],
    };
    const errors = validateAutomation(validAutomation);
    expect(errors).toEqual({});
  });

  it('should return errors for missing basic fields', () => {
    const invalidAutomation = {
      name: '',
      description: '',
      event_name: '',
      conditions: [],
      actions: [],
    };
    const errors = validateAutomation(invalidAutomation);
    expect(errors).toHaveProperty('name');
    expect(errors).toHaveProperty('description');
    expect(errors).toHaveProperty('event_name');
  });

  it('should return errors for invalid conditions', () => {
    const automationWithInvalidConditions = {
      name: 'Test',
      description: 'Test',
      event_name: 'message_created',
      conditions: [{ attribute_key: '', filter_operator: '', values: '' }],
      actions: [{ action_name: 'send_message', action_params: ['Hello'] }],
    };
    const errors = validateAutomation(automationWithInvalidConditions);
    expect(errors).toHaveProperty('condition_0');
  });

  it('should return errors for invalid actions', () => {
    const automationWithInvalidActions = {
      name: 'Test',
      description: 'Test',
      event_name: 'message_created',
      conditions: [
        {
          attribute_key: 'content',
          filter_operator: 'contains',
          values: 'hello',
        },
      ],
      actions: [{ action_name: 'send_message', action_params: [] }],
    };
    const errors = validateAutomation(automationWithInvalidActions);
    expect(errors).toHaveProperty('action_0');
  });

  it('should not require action params for specific actions', () => {
    const automationWithNoParamAction = {
      name: 'Test',
      description: 'Test',
      event_name: 'message_created',
      conditions: [
        {
          attribute_key: 'content',
          filter_operator: 'contains',
          values: 'hello',
        },
      ],
      actions: [{ action_name: 'mute_conversation' }],
    };
    const errors = validateAutomation(automationWithNoParamAction);
    expect(errors).toEqual({});
  });

  it.each(['enable_ai', 'disable_ai'])(
    'accepts the AI toggle action %s without action_params',
    actionName => {
      const automation = {
        name: 'AI toggle',
        description: 'desc',
        event_name: 'conversation_updated',
        conditions: [
          {
            attribute_key: 'status',
            filter_operator: 'equal_to',
            values: ['open'],
          },
        ],
        actions: [{ action_name: actionName }],
      };
      expect(validateAutomation(automation)).toEqual({});
    }
  );
});
