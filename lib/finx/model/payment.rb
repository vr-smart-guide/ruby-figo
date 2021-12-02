module FinX
  module Model
    class Payment

      EXCLUDED_KEYS = %w(access_method resolutions)

      def initialize(session, hash)
        @session = session
        from_hash(hash)
      end

      def from_hash(hash, parent = nil)
        unless hash.nil?
          hash.keys.each do |key|
            next if EXCLUDED_KEYS.include? key
            if hash[key].is_a? Hash
              from_hash(hash[key], key)
            else
              parent ? send("#{parent}_#{key}=", hash[key]) : send("#{key}=", hash[key])
            end
          end
        end
      end

      def to_h
        {}.tap do |hash|
          self.instance_variables.each do |var|
            var = var[1..-1]
            value = send(var)
            hash[var] = value
          end
        end
      end

      attr_accessor :debtor_iban, :creditor_iban, :creditor_name, :creditor_name, :amount_value,
                    :amount_currency, :provider_id, :provider_name, :provider_country, :provider_bank_code,
                    :provider_bic, :icon_url, :provider_is_supported

      # Internal figo Connect account ID
      # @return [String]
      attr_accessor :account_id

      # Internal figo Connect payment ID
      # @return [String]
      attr_accessor :payment_id

      # IBAN of creditor
      # @return [String]
      attr_accessor :iban

      # Three-character currency code
      # @return [String]
      attr_accessor :currency

      # Name of creditor or debtor
      # @return [String]
      attr_accessor :name

      # Payment type
      # @return [String]
      attr_accessor :type

      # Account number of creditor or debtor
      # @return [String]
      attr_accessor :account_number

      # Purpose text
      # @return [String]
      attr_accessor :purpose

      # Icon of creditor or debtor bank
      # @return [String]
      attr_accessor :bank_icon

      # Icon of the creditor or debtor bank in other resolutions
      # @return [Hash]
      attr_accessor :bank_additional_icons

      # Timestamp of submission to the bank server
      # @return [DateTime]
      attr_accessor :submitted_at
      attr_accessor :submission_timestamp

      # Internal creation timestamp on the figo Connect server
      # @return [DateTime]
      attr_accessor :created_at
      attr_accessor :creation_timestamp

      # Internal modification timestamp on the figo Connect server
      # @return [DateTime]
      attr_accessor :modified_at
      attr_accessor :modification_timestamp

      # ID of the transaction corresponding to this payment.
      # This field is only set if the payment has been matched to a transaction
      # @return [String]
      attr_accessor :transaction_id
    end
  end
end
