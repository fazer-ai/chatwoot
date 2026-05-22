import { createStore } from 'vuex';

import agent from 'simulator/store/modules/agent';
import appConfig from 'simulator/store/modules/appConfig';
import contacts from 'simulator/store/modules/contacts';
import conversation from 'simulator/store/modules/conversation';
import conversationAttributes from 'simulator/store/modules/conversationAttributes';
import conversationLabels from 'simulator/store/modules/conversationLabels';
import events from 'simulator/store/modules/events';
import globalConfig from 'shared/store/globalConfig';
import message from 'simulator/store/modules/message';
import campaign from 'simulator/store/modules/campaign';
import article from 'simulator/store/modules/articles';

export default createStore({
  modules: {
    agent,
    appConfig,
    contacts,
    conversation,
    conversationAttributes,
    conversationLabels,
    events,
    globalConfig,
    message,
    campaign,
    article,
  },
});
