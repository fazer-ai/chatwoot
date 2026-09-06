import { flushPromises, shallowMount } from '@vue/test-utils';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import Response from '../Response.vue';
import { getSurveyDetails, updateSurvey } from 'survey/api/survey';

vi.mock('survey/api/survey', () => ({
  getSurveyDetails: vi.fn(),
  updateSurvey: vi.fn(),
}));

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

const UUID = 'a555eb24-7462-4221-9cdb-b758711b4fcb';

describe('Response', () => {
  let originalLocation;

  const setUrl = search => {
    delete window.location;
    window.location = new URL(
      `https://support.example.com/survey/responses/${UUID}${search}`
    );
  };

  const surveyPayload = (csatSurveyResponse = null) => ({
    data: {
      id: 1,
      csat_survey_response: csatSurveyResponse,
      display_type: 'emoji',
      content: 'How did we do?',
      inbox_avatar_url: '',
      inbox_name: 'Support',
      locale: 'en',
    },
  });

  const buildWrapper = () =>
    shallowMount(Response, {
      global: {
        mocks: { $t: key => key },
        directives: { 'dompurify-html': () => {} },
        stubs: { Branding: true, Spinner: true, CustomButton: true },
        config: { globalProperties: { $root: { $i18n: { locale: 'en' } } } },
      },
    });

  beforeEach(() => {
    originalLocation = window.location;
    getSurveyDetails.mockResolvedValue(surveyPayload());
    updateSurvey.mockResolvedValue();
  });

  afterEach(() => {
    window.location = originalLocation;
    vi.clearAllMocks();
  });

  it('reads the uuid from the path, ignoring the rating query string', async () => {
    setUrl('?rating=4');
    buildWrapper();
    await flushPromises();

    expect(getSurveyDetails).toHaveBeenCalledWith({ uuid: UUID });
  });

  // The rating links live in an email, and security gateways detonate every URL in a
  // sandboxed browser that runs JavaScript. Writing on load would let a scanner walk all
  // five links and settle the response before the recipient ever opened the message.
  it('never writes on load, only pre-selects what the link carries', async () => {
    setUrl('?rating=4');
    const wrapper = buildWrapper();
    await flushPromises();

    expect(updateSurvey).not.toHaveBeenCalled();
    expect(wrapper.vm.selectedRating).toBe(4);
    expect(wrapper.vm.isPendingConfirmation).toBe(true);
  });

  it('writes the pre-selected rating once it is confirmed', async () => {
    setUrl('?rating=4');
    const wrapper = buildWrapper();
    await flushPromises();

    wrapper.vm.confirmRating();
    await flushPromises();

    expect(updateSurvey).toHaveBeenCalledTimes(1);
    expect(
      updateSurvey.mock.calls[0][0].data.message.submitted_values
        .csat_survey_response.rating
    ).toBe(4);
    expect(wrapper.vm.isPendingConfirmation).toBe(false);
  });

  it.each([['?rating=9'], ['?rating=abc'], ['']])(
    'ignores a rating the scale does not offer: %s',
    async search => {
      setUrl(search);
      const wrapper = buildWrapper();
      await flushPromises();

      expect(wrapper.vm.isPendingConfirmation).toBe(false);
      expect(updateSurvey).not.toHaveBeenCalled();
    }
  );

  it('leaves the page alone when the link repeats the rating already stored', async () => {
    getSurveyDetails.mockResolvedValue(surveyPayload({ rating: 4 }));
    setUrl('?rating=4');
    const wrapper = buildWrapper();
    await flushPromises();

    expect(wrapper.vm.isPendingConfirmation).toBe(false);
    expect(wrapper.vm.enableFeedbackForm).toBe(true);
  });

  it('still asks to confirm when the link carries a different rating', async () => {
    getSurveyDetails.mockResolvedValue(surveyPayload({ rating: 2 }));
    setUrl('?rating=5');
    const wrapper = buildWrapper();
    await flushPromises();

    expect(wrapper.vm.isPendingConfirmation).toBe(true);
    expect(updateSurvey).not.toHaveBeenCalled();
    // The stored rating is not the one on screen, so the page must not claim to be done.
    expect(wrapper.vm.shouldShowSuccessMessage).toBe(false);
    expect(wrapper.vm.enableFeedbackForm).toBe(false);
  });

  it('does not reopen a survey whose feedback was already submitted', async () => {
    getSurveyDetails.mockResolvedValue(
      surveyPayload({ rating: 2, feedback_message: 'all good' })
    );
    setUrl('?rating=5');
    const wrapper = buildWrapper();
    await flushPromises();

    expect(wrapper.vm.isPendingConfirmation).toBe(false);
    expect(updateSurvey).not.toHaveBeenCalled();
  });

  // A failed fetch leaves feedbackMessage at its empty initial value, so submitting over
  // it would wipe a comment the contact had already left.
  it('does not submit when the details request failed', async () => {
    getSurveyDetails.mockRejectedValue(new Error('boom'));
    setUrl('?rating=4');
    const wrapper = buildWrapper();
    await flushPromises();

    expect(updateSurvey).not.toHaveBeenCalled();
    expect(wrapper.vm.isPendingConfirmation).toBe(false);
  });

  it('writes immediately when a rating is clicked on the page itself', async () => {
    setUrl('');
    const wrapper = buildWrapper();
    await flushPromises();

    wrapper.vm.selectRating(3);
    await flushPromises();

    expect(updateSurvey).toHaveBeenCalledTimes(1);
  });
});
