require 'rails_helper'

describe Whatsapp::Baileys::RichMessageParser do
  def parse(msg)
    described_class.new(msg).parse
  end

  def text_for(msg)
    described_class.to_text(described_class.new(msg).parse)
  end

  describe '.rich?' do
    it 'detects every rich/response key' do
      %i[interactiveMessage templateMessage buttonsMessage listMessage
         buttonsResponseMessage listResponseMessage templateButtonReplyMessage interactiveResponseMessage].each do |key|
        expect(described_class.rich?({ key => {} })).to be(true)
      end
    end

    it 'is false for a plain text message' do
      expect(described_class.rich?({ conversation: 'hi' })).to be(false)
    end
  end

  describe 'templateMessage' do
    it 'renders the body only (real hydratedTemplate shape)' do
      msg = { templateMessage: { hydratedTemplate: { hydratedTitleText: '', hydratedContentText: 'Your plan expires soon' } } }

      expect(parse(msg)).to eq(type: 'template', body: 'Your plan expires soon')
      expect(text_for(msg)).to eq('Your plan expires soon')
    end

    it 'renders body + footer + quick-reply button (real shape)' do
      msg = { templateMessage: { hydratedTemplate: {
        hydratedContentText: 'Renew?', hydratedFooterText: 'Acme',
        hydratedButtons: [{ quickReplyButton: { displayText: 'Renew now!', id: 'renew' }, index: 0 }]
      } } }

      expect(text_for(msg)).to eq("Renew?\n\nAcme\n\n▸ Renew now!")
    end

    it 'includes the url and phone of url/call buttons (hydratedFourRowTemplate)' do
      msg = { templateMessage: { hydratedFourRowTemplate: {
        hydratedContentText: 'Invoice',
        hydratedButtons: [
          { urlButton: { displayText: 'Pay now', url: 'https://acme.io/pay' } },
          { callButton: { displayText: 'Call us', phoneNumber: '+5511999999999' } }
        ]
      } } }

      expect(parse(msg)[:buttons]).to eq(
        [{ text: 'Pay now', url: 'https://acme.io/pay' }, { text: 'Call us', phone: '+5511999999999' }]
      )
      expect(text_for(msg)).to eq("Invoice\n\n▸ Pay now: https://acme.io/pay\n\n▸ Call us: +5511999999999")
    end

    it 'returns nil for an empty template (only media header / no text)' do
      expect(parse({ templateMessage: { hydratedTemplate: { templateId: '1' } } })).to be_nil
    end
  end

  describe 'interactiveMessage (nativeFlow)' do
    it 'parses a cta_url button from the snake_case JSON string' do
      msg = { interactiveMessage: {
        body: { text: 'Pick one' },
        nativeFlowMessage: { buttons: [{ name: 'cta_url', buttonParamsJson: '{"display_text":"Buy","url":"https://b.io"}' }] }
      } }

      expect(parse(msg)).to eq(type: 'interactive', body: 'Pick one', buttons: [{ text: 'Buy', url: 'https://b.io' }])
      expect(text_for(msg)).to eq("Pick one\n\n▸ Buy: https://b.io")
    end

    it 'parses a cta_call button phone number' do
      msg = { interactiveMessage: {
        nativeFlowMessage: { buttons: [{ name: 'cta_call', buttonParamsJson: '{"display_text":"Call","phone_number":"+551130000000"}' }] }
      } }

      expect(parse(msg)[:buttons]).to eq([{ text: 'Call', phone: '+551130000000' }])
    end

    it 'degrades to the body when buttonParamsJson is malformed' do
      msg = { interactiveMessage: {
        body: { text: 'Pick' },
        nativeFlowMessage: { buttons: [{ name: 'cta_url', buttonParamsJson: 'not-json' }] }
      } }

      expect(parse(msg)).to eq(type: 'interactive', body: 'Pick')
      expect(text_for(msg)).to eq('Pick')
    end
  end

  describe 'buttonsMessage' do
    it 'renders content + button labels' do
      msg = { buttonsMessage: {
        contentText: 'Choose', footerText: 'footer',
        buttons: [{ buttonText: { displayText: 'Yes' } }, { buttonText: { displayText: 'No' } }]
      } }

      expect(text_for(msg)).to eq("Choose\n\nfooter\n\n▸ Yes\n\n▸ No")
    end
  end

  describe 'listMessage' do
    it 'renders title/description + section rows' do
      msg = { listMessage: {
        title: 'Menu', description: 'Pick one', buttonText: 'Open',
        sections: [{ title: 'Drinks', rows: [{ title: 'Coke', rowId: 'c' }, { title: 'Water', rowId: 'w' }] }]
      } }

      expect(parse(msg)[:buttons]).to eq([{ text: 'Coke' }, { text: 'Water' }])
      expect(text_for(msg)).to eq("Menu\n\nPick one\n\n▸ Coke\n\n▸ Water")
    end
  end

  describe 'response variants' do
    it 'reads the selected text of each response shape' do
      expect(text_for({ buttonsResponseMessage: { selectedDisplayText: 'Yes' } })).to eq('Yes')
      expect(text_for({ listResponseMessage: { title: 'Coke', singleSelectReply: { selectedRowId: 'c' } } })).to eq('Coke')
      expect(text_for({ templateButtonReplyMessage: { selectedDisplayText: 'Pay now' } })).to eq('Pay now')
      expect(text_for({ interactiveResponseMessage: { body: { text: 'Done' } } })).to eq('Done')
    end
  end

  describe 'unknown / empty rich shapes' do
    it 'returns nil so the caller marks the message unsupported' do
      expect(parse({ interactiveMessage: {} })).to be_nil
      expect(parse({ buttonsResponseMessage: {} })).to be_nil
      expect(described_class.to_text(nil)).to be_nil
    end
  end

  describe '#context_info' do
    it 'returns the contextInfo of the rich subtype (for externalAdReply)' do
      ctx = { externalAdReply: { title: 'Ad' } }
      expect(described_class.new({ templateMessage: { contextInfo: ctx } }).context_info).to eq(ctx)
      expect(described_class.new({ interactiveMessage: { contextInfo: ctx } }).context_info).to eq(ctx)
    end
  end
end
