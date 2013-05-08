#!/usr/bin/env ruby

require 'spec_helper'
require File.join(File.dirname(__FILE__), '../../', 'discovery', 'puppetdb.rb')
require File.join(File.dirname(__FILE__), '../../', 'util', 'puppetdb_discovery.rb')

module MCollective
  class Discovery
    describe Puppetdb do
      describe '#discover' do
        it 'should create a new PuppetDBDiscovery object and call discover' do
          config = mock
          puppetdb_util = mock
          puppetdb_util.expects(:discover).with({})
          Config.stubs(:instance).returns(config)
          Util::PuppetdbDiscovery.stubs(:new).with(config).returns(puppetdb_util)
          Puppetdb.stubs(:require).with('mcollective/util/puppetdb_discovery')

          Puppetdb.discover({}, 10)
        end
      end
    end
  end
end
