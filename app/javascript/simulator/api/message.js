import authEndPoint from 'simulator/api/endPoints';
import { API } from 'simulator/helpers/axios';

export default {
  update: ({ messageId, email, values }) => {
    const urlData = authEndPoint.updateMessage(messageId);
    return API.patch(urlData.url, {
      contact: { email },
      message: { submitted_values: values },
    });
  },
  toggleReaction: ({ messageId, emoji }) => {
    const urlData = authEndPoint.toggleReaction(messageId, emoji);
    return API.post(urlData.url, urlData.params);
  },
};
