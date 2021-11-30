module FinX
  module StrongCustomerAuthentication
    # Solve payment challenge
    #
    # @param payment_id [String] figo ID of the payment.
    # @param init_d [String] figo ID of the payment initation.
    # @param challenge_id [String] figo ID of the challenge.
    # @return [Object]
    def solve_finx_payment_challenge(payment_id, init_id, challenge_id, data)
      path = "/rest/payments/#{payment_id}/init/#{init_id}/challenges/#{challenge_id}/response"
      query_api(path, data, 'POST')
    end
  end
end
