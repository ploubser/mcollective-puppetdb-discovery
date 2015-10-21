module MCollective
  class Discovery
    class Puppetdb

      def self.discover(filter, timeout, limit = 0, client = nil)
        require 'mcollective/util/puppetdb_discovery'
        options = client.options[:discovery_options]
        Util::PuppetdbDiscovery.new(Config.instance).discover(filter,options)
      end
    end
  end
end
