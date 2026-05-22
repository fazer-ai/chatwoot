import endPoints from 'simulator/api/endPoints';
import { API } from 'simulator/helpers/axios';

export const getMostReadArticles = async (slug, locale) => {
  const urlData = endPoints.getMostReadArticles(slug, locale);
  return API.get(urlData.url, { params: urlData.params });
};
