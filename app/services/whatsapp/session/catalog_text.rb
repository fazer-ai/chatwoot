# The text a catalog product or order is stored as: what the conversation list, search and
# notifications show, and what an agent reads where the card is not drawn. Written in the
# caller's locale, which the writer sets to the account's, from the amounts in thousandths
# the connector sends. A price WhatsApp did not send is left out, never written as zero.
module Whatsapp::Session::CatalogText
  SYMBOLS = { 'BRL' => 'R$', 'USD' => 'US$', 'EUR' => '€', 'GBP' => '£' }.freeze

  class << self
    def product(product)
      return t('product_unreadable') unless product.readable?

      [product.title, price(product.current_price_1000, product.currency), product.description].compact_blank.join("\n\n")
    end

    def order(order, note: nil)
      summary = [t('order_title', id: order.id), totals(order)].compact_blank.join("\n")
      [summary, note, items(order)].compact_blank.join("\n\n")
    end

    def price(amount_1000, currency)
      return if amount_1000.nil? || currency.blank?

      number = ActiveSupport::NumberHelper.number_to_rounded(
        BigDecimal(amount_1000) / 1000, precision: 2, separator: t('separator'), delimiter: t('delimiter')
      )
      t('price', unit: SYMBOLS.fetch(currency, currency), number: number)
    end

    private

    def totals(order)
      total = price(order.total_1000, order.currency)
      [
        (t('item_count', count: order.item_count) unless order.item_count.nil?),
        (t('estimated_total', total: total) if total)
      ].compact.join(' · ')
    end

    def items(order)
      Array(order.items).map do |item|
        line = "• #{item.name} × #{item.quantity}"
        amount = price(item.price_1000, item.currency.presence || order.currency)
        amount ? "#{line} · #{amount}" : line
      end.join("\n")
    end

    def t(key, **) = I18n.t("whatsapp_catalog.#{key}", **)
  end
end
