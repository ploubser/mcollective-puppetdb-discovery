module MCollective
  module Util
    class PuppetdbDiscovery
      attr_accessor :config, :http

      def initialize(config)
        require 'net/http'

        @config = {}
        @config[:ssl] = config.pluginconf.fetch('discovery.puppetdb.use_ssl', 'n')
        @config[:krb] = config.pluginconf.fetch('discovery.puppetdb.use_krb', 'n')
        @config[:host] = config.pluginconf.fetch('discovery.puppetdb.host', 'localhost')
        @config[:port] = config.pluginconf.fetch('discovery.puppetdb.port', 8080)
        @config[:ssl_ca] = config.pluginconf.fetch('discovery.puppetdb.ssl_ca', nil)
        @config[:ssl_cert] = config.pluginconf.fetch('discovery.puppetdb.ssl_cert', nil)
        @config[:ssl_key] = config.pluginconf.fetch('discovery.puppetdb.ssl_private_key', nil)
        @config[:api_version] = config.pluginconf.fetch('discovery.puppetdb.api_version', '3')
        @http = create_http
      end

      def discover(filter)
        found = []

        #if no filters are to be applied, we fetch all the nodes registered in puppetdb
        if filter['fact'].empty? && filter['cf_class'].empty? && filter['identity'].empty?
          found = node_search
        else
          found << fact_search(filter['fact']) unless filter['fact'].empty?
          found << class_search(filter['cf_class']) unless filter['cf_class'].empty?
          found << identity_search(filter['identity']) unless filter['identity'].empty?
          found.inject(found[0]) { |x,y| x & y }
        end
      end

      def create_http
        if @config[:krb] =~ /^1|y|t/
          create_http_krb
        else
          http = Net::HTTP.new(@config[:host], @config[:port])
          configure_ssl(http) if @config[:ssl] =~ /^1|y|t/
          http
        end
      end

      # With HTTPI and curb for Kerberos support 
      def create_http_krb
        require 'rubygems'
        require 'httpi'
        require 'curb'
        req = HTTPI::Request.new()
        req.auth.ssl.verify_mode = :none
        req.auth.gssnegotiate
        HTTPI.log = false
        HTTPI.adapter = :curb
        req
      end

      # Configure the http object to use SSL.
      # To use SSL the client configuation options use_ssl,
      # ssl_ca, ssl_cert and ssl_private_key have to be set.
      def configure_ssl(http)
        require 'net/https'
        raise 'Cannot create SSL connection to PuppetDB. Missing ssl_ca configuration option' unless @config[:ssl_ca]
        raise 'Cannot create SSL connection to PuppetDB. Missing ssl_cert configuration option' unless @config[:ssl_cert]
        raise 'Cannot create SSL connection to PuppetDB. Missing ssl_private_key configuration option' unless @config[:ssl_key]

        http.use_ssl = true
        http.verify_mode = OpenSSL::SSL::VERIFY_PEER
        http.cert = OpenSSL::X509::Certificate.new(File.read(@config[:ssl_cert]))
        http.ca_file = @config[:ssl_ca]
        http.key = OpenSSL::PKey::RSA.new(File.read(@config[:ssl_key]))
      end

      # Retrieves the list of hosts by querying the puppetdb node endpoint,
      # combining all supplied facts into one complex query.
      def fact_search(filter)
        query = []

        filter.each do |fact|
          op, value = translate_value(fact[:value], fact[:operator])
          if @config[:api_version] == '4' && fact[:fact] == 'environment'
            new_query = [op, "facts-environment", URI.encode(value)]
          else
            new_query = [op, ['fact', URI.encode(fact[:fact])], URI.encode(value)]
          end
          new_query = [ "not", new_query ] if fact[:operator] == '!='
          query << new_query
        end

        query = transform_query(query, 'node')
        JSON.parse(make_request('nodes', query.to_json)).map { |node| node['name'] || node['certname'] }
      end

      # Retrieves the list hosts by querying the puppetdb resource endpoint,
      # combining all supplied classes into one complex or query.
      # The results from the or query are then grouped and their union
      # calculated to simulate an and query.
      def class_search(filter)
        query = []
        host_hash = {}

        filter.each do |klass|
          op, value = translate_value(klass, '=')
          value = value.split("::").map { |i| i.capitalize }.join("::")
          query << ['and', ['=', 'type', 'Class'], [op, 'title', URI.encode(value)]]
        end

        query = transform_query(query, 'klass')

        JSON.parse(make_request('resources', query.to_json)).each do |result|
          host_hash[result['certname']] = true
        end

        host_hash.keys
      end

      # Retrieves the list of hosts by querying puppetdb's node endpoint
      def identity_search(filter)
        all_hosts = node_search
        hosts = []

        filter.each do |identity|
          op, value = translate_value(identity, '=')
          if op == '='
            hosts << identity if all_hosts.include?(value)
          elsif op == '~'
            hosts += all_hosts.grep(Regexp.new(value))
          end
        end

        hosts
      end

      # Looks up all the nodes registered in puppetdb without applying any filters
      def node_search
        JSON.parse(make_request('nodes', nil)).map { |node| node['name'] }
      end

      def make_request(endpoint, query)
        if @config[:krb] =~ /^1|y|t/
          make_request_krb(endpoint, query)
        else
          make_request_normal(endpoint, query)
        end
      end

      def make_request_normal(endpoint, query)
        request = Net::HTTP::Get.new("/v#{@config[:api_version]}/%s" % endpoint, {'accept' => 'application/json'})
        request.set_form_data({"query" => query}) if query
        resp, data = @http.request(request)
        data = resp.body if data.nil?
        raise 'Failed to make request to PuppetDB: %s: %s' % [resp.code, resp.message] unless resp.code == '200'
        data
      end

      # With HTTPI and curb for Kerberos support 
      def make_request_krb(endpoint, query)
        require 'cgi'
        @http.url = "https://#{@config[:host]}:#{@config[:port]}/v#{@config[:api_version]}/#{endpoint}" + (query ? "?query=#{CGI.escape(query)}" : '')
        resp = HTTPI.get(@http)
        raise 'Failed to make request to PuppetDB: code %s' % [resp.code] if resp.error?
        resp.raw_body
      end

      # Transforms a list of queries into single, complex query
      def transform_query(query, type = 'node')
        if query.size == 1
          query = query[0]
        elsif query.size > 1
          if type == 'node'
            query.unshift('and')
          elsif type == 'klass'
            query.unshift('or')
          end
        end

        query
      end

      # Translates the op and value used in a query so that the
      # op matches the comparison characters used by PuppetDB.
      # Regular expressions will have the first and last '/'
      # characters removed and the correct op value will be set
      def translate_value(value, op)
        if value =~ /^\/.*\/$/
          value = value.gsub(/^\/|\/$/, '')
          op = '~'
        end

        op = '=' if (op == '==' or op == "!=")

        return op, value
      end
    end
  end
end

