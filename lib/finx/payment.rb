# This module provides methods regarding payments via the finX API instead
# with the legacy figo API
require_relative 'model/payment'
module FinX
  module Payment
    # Create a new payment on finleap side via finX API
    def create_finx_payment(data)
      query_api_json_object(FinX::Model::Payment, "/rest/payments", data, 'POST')
    end

    # Initiate a payment on finleap side via finX API
    def initiate_finx_payment(payment_id, data)
      params = data.delete_if { |_k, v| v.nil? }
      query_api_json("/rest/payments/#{payment_id}/init", params, 'POST')
    end

    # Get a existing payment via finX API
    # Note: This endpoint can only be called with user_auth !
    def get_finx_payment(account_id, payment_id, cents = false)
      query_api_object FinX::Model::Payment, "/rest/accounts/#{account_id}/payments/#{payment_id}?cents=#{cents}"
    end

    # Get payment status via finX API
    def get_finx_payment_initiation_status(payment_id, init_id)
      query_api_json("/rest/payments/#{payment_id}/init/#{init_id}", nil, 'GET')
    end
  end
end
