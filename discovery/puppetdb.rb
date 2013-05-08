module MCollective
  class Discovery
    class Puppetdb

      def self.discover(filter, timeout, limit = 0, client = nil)
        require 'mcollective/util/puppetdb_discovery'
        Util::PuppetdbDiscovery.new(Config.instance).discover(filter)
      end
    end
  end
end
