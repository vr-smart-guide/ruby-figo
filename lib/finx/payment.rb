# This module provides methods regarding payments via the finX API instead
# with the legacy figo API
module FinX
  module Payment
    # Create a new payment on finleap side via finX API
    def create_finx_payment(data)
      query_api_object(Model::Payment, "/rest/payments", data, 'POST', FINX_API_HOST)
    end

    # Initiate a payment on finleap side via finX API
    def initiate_finx_payment(payment, data)
      params = data.delete_if { |_k, v| v.nil? }
      query_api("/rest/payments/#{payment.payment_id}/init", params, 'POST', FINX_API_HOST)
    end

    # Get payment status via finX API
    def get_finx_payment_initiation_status(payment, init_id)
      query_api("/rest/payments/#{payment.payment_id}/init/#{init_id}", nil, 'GET', FINX_API_HOST)
    end
  end
end
