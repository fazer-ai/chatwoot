import { IFrameHelper } from 'simulator/helpers/utils';

export const playNewMessageNotificationInWidget = () => {
  IFrameHelper.sendMessage({ event: 'playAudio' });
};
