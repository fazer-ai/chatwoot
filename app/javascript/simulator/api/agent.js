import endPoints from 'simulator/api/endPoints';
import { API } from 'simulator/helpers/axios';

export const getAvailableAgents = async websiteToken => {
  const urlData = endPoints.getAvailableAgents(websiteToken);
  return API.get(urlData.url, { params: urlData.params });
};
