require 'httparty'
require 'multi_json'

module Customerio
  class Client
    include HTTParty
    base_uri 'https://track.customer.io'
    default_timeout 10

    class MissingIdAttributeError < RuntimeError; end
    class InvalidResponse < RuntimeError
      attr_reader :response

      def initialize(message, response)
        @message = message
        @response = response
      end
    end

    def initialize(site_id, secret_key, options = {})
      @auth = { :username => site_id, :password => secret_key }
      if options[:json].nil?
        warn "[DEPRECATION] Customerio::Client: JSON encoding will be the default in the next release. We recommend switching to JSON. To continue to use form-encoding, you must specify `:json => false` in your initializer."
      end
      @json = options[:json]
    end

    def identify(attributes)
      create_or_update(attributes)
    end

    def delete(customer_id)
      verify_response(self.class.delete(customer_path(customer_id), options))
    end

    def track(*args)
      attributes = extract_attributes(args)

      if args.length == 1
        # Only passed in an event name, create an anonymous event
        event_name = args.first
        create_anonymous_event(event_name, attributes)
      else
        # Passed in a customer id and an event name.
        # Track the event for the given customer
        customer_id, event_name = args

        create_customer_event(customer_id, event_name, attributes)
      end
    end

    private

    def create_or_update(attributes = {})
      attributes = Hash[attributes.map { |(k,v)| [ k.to_sym, v ] }]

      raise MissingIdAttributeError.new("Must provide a customer id") unless attributes[:id]

      url = customer_path(attributes[:id])

      if @json
        verify_response(self.class.put(url, options.merge(:body => MultiJson.dump(attributes), :headers => {'Content-Type' => 'application/json'})))
      else
        verify_response(self.class.put(url, options.merge(:body => attributes)))
      end
    end

    def create_customer_event(customer_id, event_name, attributes = {})
      create_event("#{customer_path(customer_id)}/events", event_name, attributes)
    end

    def create_anonymous_event(event_name, attributes = {})
      create_event("/api/v1/events", event_name, attributes)
    end

    def create_event(url, event_name, attributes = {})
      body = { :name => event_name, :data => attributes }
      body[:timestamp] = attributes[:timestamp] if valid_timestamp?(attributes[:timestamp])
      if @json
        verify_response(self.class.post(url, options.merge(:body => MultiJson.dump(body), :headers => {'Content-Type' => 'application/json'})))
      else
        verify_response(self.class.post(url, options.merge(:body => body)))
      end
    end

    def customer_path(id)
      "/api/v1/customers/#{id}"
    end

    def valid_timestamp?(timestamp)
      timestamp && timestamp.is_a?(Integer) && timestamp > 999999999 && timestamp < 100000000000
    end


    def verify_response(response)
      if response.code >= 200 && response.code < 300
        response
      else
        raise InvalidResponse.new("Customer.io API returned an invalid response: #{response.code}", response)
      end
    end

    def extract_attributes(args)
      hash = args.last.is_a?(Hash) ? args.pop : {}
      hash.inject({}){ |hash, (k,v)| hash[k.to_sym] = v; hash }
    end

    def options
      
      #overriden for Http proxy for Market place AMI

      if ENV['SAAS_ENV'].eql?('false') && ENV["http_proxy"].present? && ENV["http_proxy"].match(/@/).present?
        username, password = ENV["http_proxy"].split('@').first.split("//").last.split(":")
        ip, port = ENV["http_proxy"].split('@').last.split(":")
        { :basic_auth => @auth, :http_proxyaddr => ip, :http_proxyport => port.to_i, :http_proxyuser => username, :http_proxypass=> password}
      else
        { :basic_auth => @auth }
      end
    end
  end
end
