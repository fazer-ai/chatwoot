import { generateFileName } from '../downloadHelper';

describe('#generateFileName', () => {
  it('should generate the correct file name', () => {
    expect(generateFileName({ type: 'csat', to: 1652812199 })).toEqual(
      'csat-report-17-05-2022.csv'
    );

    expect(
      generateFileName({ type: 'csat', to: 1652812199, businessHours: true })
    ).toEqual('csat-report-17-05-2022-business-hours.csv');
  });

  it('should append the filter it was narrowed to', () => {
    expect(
      generateFileName({
        type: 'agent',
        to: 1652812199,
        filteredBy: 'SAC - WhatsApp Cobrança',
      })
    ).toEqual('agent-report-17-05-2022-sac-whatsapp-cobranca.csv');

    expect(
      generateFileName({
        type: 'agent',
        to: 1652812199,
        businessHours: true,
        filteredBy: 'SAC Email',
      })
    ).toEqual('agent-report-17-05-2022-sac-email-business-hours.csv');
  });
});
