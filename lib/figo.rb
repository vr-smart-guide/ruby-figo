#
# Copyright (c) 2013 figo GmbH
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
# 

require "json"
require "net/http/persistent"
require "digest/sha1"
require_relative "models.rb"


# Ruby bindings for the figo Connect API: http://developer.figo.me
module Figo

  $api_endpoint = "api.leanbank.com"

  $valid_fingerprints = ["A6:FE:08:F4:A8:86:F9:C1:BF:4E:70:0A:BD:72:AE:B8:8E:B7:78:52",
                         "AD:A0:E3:2B:1F:CE:E8:44:F2:83:BA:AE:E4:7D:F2:AD:44:48:7F:1E"]

  # Base class for all errors transported via the figo Connect API.
  class Error < RuntimeError

    # Initialize error object.
    #
    # @param error [String] the error code
    # @param error_description [String] the error description
    def initialize(error, error_description)
      @error = error
      @error_description = error_description
    end

    # Convert error object to string.
    #
    # @return [String] the error description
    def to_s
      return @error_description
    end

  end

  # HTTPS class with certificate authentication and enhanced error handling.
  class HTTPS < Net::HTTP::Persistent

    # Overwrite `initialize` method from `Net::HTTP::Persistent`.
    #
    # Verify fingerprints of server SSL/TLS certificates.
    def initialize(name = nil, proxy = nil)
      super(name, proxy)

      # Attribute ca_file must be set, otherwise verify_callback would never be called.
      @ca_file = "lib/cacert.pem"
      @verify_callback = proc do |preverify_ok, store_context|
        if preverify_ok and store_context.error == 0
          certificate = OpenSSL::X509::Certificate.new(store_context.chain[0])
          fingerprint = Digest::SHA1.hexdigest(certificate.to_der).upcase.scan(/../).join(":")
          $valid_fingerprints.include?(fingerprint)
        else
          false
        end
      end
    end

    # Overwrite `request` method from `Net::HTTP::Persistent`.
    #
    # Raise error when a REST API error is returned.
    def request(uri, req = nil, &block)
      response = super(uri, req, &block)

      # Evaluate HTTP response.
      case response
        when Net::HTTPSuccess
          return response
        when Net::HTTPBadRequest
          hash = JSON.parse(response.body)
          raise Error.new(hash["error"], hash["error_description"])
        when Net::HTTPUnauthorized
          raise Error.new("unauthorized", "Missing, invalid or expired access token.")
        when Net::HTTPForbidden
          raise Error.new("forbidden", "Insufficient permission.")
        when Net::HTTPNotFound
          return nil
        when Net::HTTPMethodNotAllowed
          raise Error.new("method_not_allowed", "Unexpected request method.")
        when Net::HTTPServiceUnavailable
          raise Error.new("service_unavailable", "Exceeded rate limit.")
        else
          raise Error.new("internal_server_error", "We are very sorry, but something went wrong.")
      end
    end

  end

  # Represents a non user-bound connection to the figo Connect API.
  #
  # It's main purpose is to let user login via OAuth 2.0.
  class Connection

    # Create connection object with client credentials.
    #
    # @param client_id [String] the client ID
    # @param client_secret [String] the client secret
    # @param redirect_uri [String] optional redirect URI
    def initialize(client_id, client_secret, redirect_uri = nil)
      @client_id = client_id
      @client_secret = client_secret
      @redirect_uri = redirect_uri
      @https = HTTPS.new("figo-#{client_id}")
    end

    # Helper method for making a OAuth 2.0 request.
    #
    # @param path [String] the URL path on the server
    # @param data [Hash] this optional object will be used as url-encoded POST content.
    # @return [Hash] JSON response
    def query_api(path, data = nil)
      uri = URI("https://#{$api_endpoint}#{path}")

      # Setup HTTP request.
      request = Net::HTTP::Post.new(path)
      request.basic_auth(@client_id, @client_secret)
      request["Accept"] = "application/json"
      request["Content-Type"] = "application/x-www-form-urlencoded"
      request["User-Agent"] =  "ruby-figo"
      request.body = URI.encode_www_form(data) unless data.nil?

      # Send HTTP request.
      response = @https.request(uri, request)

      # Evaluate HTTP response.
      return response.body == "" ? {} : JSON.parse(response.body)
    end


    # Get the URL a user should open in the web browser to start the login process.
    #
    # When the process is completed, the user is redirected to the URL provided to 
    # the constructor and passes on an authentication code. This code can be converted 
    # into an access token for data access.
    #
    # @param state [String] this string will be passed on through the complete login 
    #        process and to the redirect target at the end. It should be used to 
    #        validated the authenticity of the call to the redirect URL
    # @param scope [String] optional scope of data access to ask the user for, 
    #        e.g. `accounts=ro`
    # @return [String] the URL to be opened by the user.
    def login_url(state, scope = nil)
      data = { "response_type" => "code", "client_id" => @client_id, "state" => state }
      data["redirect_uri"] = @redirect_uri unless @redirect_uri.nil?
      data["scope"] = scope unless scope.nil?
      return "https://#{$api_endpoint}/auth/code?" + URI.encode_www_form(data) 
    end


    # Exchange authorization code or refresh token for access token.
    #
    # @param authorization_code_or_refresh_token [String] either the authorization 
    #        code received as part of the call to the redirect URL at the end of the 
    #        logon process, or a refresh token
    # @param scope [String] optional scope of data access to ask the user for, 
    #        e.g. `accounts=ro`
    # @return [Hash] object with the keys `access_token`, `refresh_token` and 
    #        `expires,` as documented in the figo Connect API specification.
    def obtain_access_token(authorization_code_or_refresh_token, scope = nil)
      # Authorization codes always start with "O" and refresh tokens always start with "R".
      if authorization_code_or_refresh_token[0] == "O"
        data = { "grant_type" => "authorization_code", "code" => authorization_code_or_refresh_token }
        data["redirect_uri"] = @redirect_uri unless @redirect_uri.nil?
      elsif authorization_code_or_refresh_token[0] == "R"
        data = { "grant_type" => "refresh_token", "refresh_token" => authorization_code_or_refresh_token }
        data["scope"] = scope unless scope.nil?
      end
      return query_api("/auth/token", data)
    end

    # Revoke refresh token or access token.
    #
    # @note this action has immediate effect, i.e. you will not be able use that token anymore after this call.
    #
    # @param refresh_token_or_access_token [String] access or refresh token to be revoked
    # @return [nil]
    def revoke_token(refresh_token_or_access_token)
      data = { "token" => refresh_token_or_access_token }
      query_api("/auth/revoke?" + URI.encode_www_form(data))
      return nil
    end

  end

  # Represents a user-bound connection to the figo Connect API and allows access to the user's data.
  class Session

    # Create session object with access token.
    #
    # @param access_token [String] the access token
    def initialize(access_token)
      @access_token = access_token
      @https = HTTPS.new("figo-#{access_token}")
    end

    # Helper method for making a REST request.
    #
    # @param path [String] the URL path on the server
    # @param data [hash] this optional object will be used as JSON-encoded POST content.
    # @return [Hash] JSON response
    def query_api(path, data=nil, method="GET") # :nodoc:
      uri = URI("https://#{$api_endpoint}#{path}")

      # Setup HTTP request.
      request = case method
        when "POST"
          Net::HTTP::Post.new(path)
        when "PUT"
          Net::HTTP::Put.new(path)
        when "DELETE"
          Net::HTTP::Delete.new(path)
        else
          Net::HTTP::Get.new(path)
      end

      request["Authorization"] = "Bearer #{@access_token}"
      request["Accept"] = "application/json"
      request["Content-Type"] = "application/json"
      request["User-Agent"] =  "ruby-figo"
      request.body = JSON.generate(data) unless data.nil?

      # Send HTTP request.
      response = @https.request(uri, request)

      # Evaluate HTTP response.
      if response.nil?
        return nil
      elsif response.body.nil?
        return nil
      else
        return response.body == "" ? nil : JSON.parse(response.body)
      end
    end

    # Request list of accounts.
    #
    # @return [Array] an array of `Account` objects, one for each account the user has granted the app access
    def accounts
      response = query_api("/rest/accounts")
      return response["accounts"].map {|account| Account.new(self, account)}
    end

    # Request specific account.
    #
    # @param account_id [String] ID of the account to be retrieved.
    # @return [Account] account object
    def get_account(account_id)
      response = query_api("/rest/accounts/#{account_id}")
      return Account.new(self, response)
    end

    # Request list of transactions.
    #
    # @param since [String, Date] this parameter can either be a transaction ID or a date
    # @param start_id [String] do only return transactions which were booked after the start transaction ID
    # @param count [Intger] limit the number of returned transactions
    # @param include_pending [Boolean] this flag indicates whether pending transactions should be included 
    #        in the response; pending transactions are always included as a complete set, regardless of 
    #        the `since` parameter
    # @return [Array] an array of `Transaction` objects, one for each transaction of the user
    def transactions(since = nil, start_id = nil, count = 1000, include_pending = false)
      data = {}
      data["since"] = (since.is_a?(Date) ? since.to_s : since) unless since.nil?
      data["start_id"] = start_id unless start_id.nil?
      data["count"] = count.to_s
      data["include_pending"] = include_pending ? "1" : "0"
      response = query_api("/rest/transactions?" + URI.encode_www_form(data)) 
      return response["transactions"].map {|transaction| Transaction.new(self, transaction)}
    end

    # Request the URL a user should open in the web browser to start the synchronization process.
    #
    # @param redirect_uri [String] URI the user is redirected to after the process completes
    # @param state [String] this string will be passed on through the complete synchronization process 
    #        and to the redirect target at the end. It should be used to validated the authenticity of 
    #        the call to the redirect URL
    # @param disable_notifications [Booleon] this flag indicates whether notifications should be sent
    # @param if_not_synced_since [Integer] if this parameter is set, only those accounts will be 
    #        synchronized, which have not been synchronized within the specified number of minutes.
    # @return [String] the URL to be opened by the user.
    def sync_url(redirect_uri, state, disable_notifications = false, if_not_synced_since = 0)
      data = { "redirect_uri" => redirect_uri, "state" => state, "disable_notifications" => disable_notifications, "if_not_synced_since" => if_not_synced_since }
      response = query_api("/rest/sync", data, "POST")
      return "https://#{$api_endpoint}/task/start?id=#{response["task_token"]}"
    end

    # Request list of registered notifications.
    #
    # @return [Notification] an array of `Notification` objects, one for each registered notification
    def notifications
      response = query_api("/rest/notifications")
      return response["notifications"].map {|notification| Notification.new(self, notification)}
    end

    # Request specific notification.
    #
    # @param notification_id [String] ID of the notification to be retrieved
    # @return [Notification] `Notification` object for the respective notification
    def get_notification(notification_id)
      response = query_api("/rest/notifications/#{notification_id}")
      return response.nil? ? nil : Notification.new(self, response)
    end

    # Register notification.
    #
    # @param observe_key [String] one of the notification keys specified in the figo Connect API 
    #        specification
    # @param notify_uri [String] notification messages will be sent to this URL
    # @param state [String] any kind of string that will be forwarded in the notification message
    # @return [Notification] newly created `Notification` object
    def add_notification(observe_key, notify_uri, state)
      data = { "observe_key" => observe_key, "notify_uri" => notify_uri, "state" => state }
      response = query_api("/rest/notifications", data, "POST")
      return Notification.new(self, response)
    end

    # Modify a notification.
    #
    # @param notification [Notification] modified notification object
    # @return [nil]
    def modify_notification(notification)
      data = { "observe_key" => notification.observe_key, "notify_uri" => notification.notify_uri, "state" => notification.state }
      response = query_api("/rest/notifications/#{notification.notification_id}", data, "PUT")
      return nil
    end

    # Unregister notification.
    #
    # @param notification [Notification] notification object which should be deleted
    # @return [nil]
    def remove_notification(notification)
      query_api("/rest/notifications/#{notification.notification_id}", nil, "DELETE")
      return nil
    end

  end

end
