module MCollective
  module Util
    class PuppetdbDiscovery
      attr_accessor :config, :http

      def initialize(config)
        require 'net/http'

        @config = {}
        @config[:ssl] = config.pluginconf.fetch('discovery.puppetdb.use_ssl', 'n')
        @config[:host] = config.pluginconf.fetch('discovery.puppetdb.host', 'localhost')
        @config[:port] = config.pluginconf.fetch('discovery.puppetdb.port', 8080)
        @config[:ssl_ca] = config.pluginconf.fetch('discovery.puppetdb.ssl_ca', nil)
        @config[:ssl_cert] = config.pluginconf.fetch('discovery.puppetdb.ssl_cert', nil)
        @config[:ssl_key] = config.pluginconf.fetch('discovery.puppetdb.ssl_private_key', nil)
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
        http = Net::HTTP.new(@config[:host], @config[:port])
        configure_ssl(http) if @config[:ssl] =~ /^1|y|t/
          http
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
          query << [op, ['fact', fact[:fact]], value]
        end

        query = transform_query(query, 'node')
        JSON.parse(make_request('nodes', URI.encode(query.to_json))).map { |node| node['name'] }
      end

      # Retrieves the list hosts by querying the puppetdb resource endpoint,
      # combining all supplied classes into one complex or query.
      # The results from the or query are then grouped and their union
      # calculated to simulate an and query.
      def class_search(filter)
        query = []
        query_results = {}
        filter.map! { |f| f.split("::").map { |i| i.capitalize }.join("::") }
        filter.each { |f| query_results[f] = [] }

        filter.each do |klass|
          op, value = translate_value(klass, '=')
          query << ['and', ['=', 'type', 'Class'], [op, 'title', value]]
        end

        query = transform_query(query, 'klass')

        JSON.parse(make_request('resources', URI.encode(query.to_json))).each do |result|
          query_results[result['title']] << result['certname']
        end

        host_arrays = query_results.values
        host_arrays.inject(host_arrays[0]) { |x,y| x & y }
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
        request = "/v2/%s" % endpoint
        request += "?query=%s" % query if query

        resp = @http.get(request, {'accept' => 'application/json'})
        raise 'Failed to make request to PuppetDB: %s: %s' % [resp.code, resp.message] unless resp.code == '200'
        resp.body
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
      # Regular expressions will have the '/' characters removed
      # and the correct op value will be set
      def translate_value(value, op)
        if value =~ /^\//
          value = value.gsub('/', '')
          op = '~'
        end

        op = '=' if op == '=='

        return op, value
      end
    end
  end
end
