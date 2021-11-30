# FinX API support
# 
# This module provides support for the finX API. The figo API is stated as legacy by finleap.
require_relative 'payment'
require_relative 'strong_customer_authentication'

module FinX
  include FinX::Payment
  include FinX::StrongCustomerAuthentication
end
