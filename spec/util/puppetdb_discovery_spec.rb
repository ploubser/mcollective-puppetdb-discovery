#!/usr/bin/env ruby

require 'spec_helper'
require File.join(File.dirname(__FILE__), '../../', 'util', 'puppetdb_discovery')

module MCollective
  module Util
    describe PuppetdbDiscovery do

      module Net;class HTTP;end;end
      module OpenSSL;module SSL;VERIFY_PEER=nil;end;module X509;class Certificate;end;end;class PKey;class RSA;end;end;end

      let(:config) { mock }
      let(:http) { mock }

      before do
        PuppetdbDiscovery.any_instance.stubs('require')
        config.stubs(:pluginconf).returns({})
      end

      describe '#initialize' do
        it 'should set the default configuration values and create an http object' do
          PuppetdbDiscovery.any_instance.expects(:create_http)

        result = PuppetdbDiscovery.new(config)
        result.config[:ssl].should == 'n'
        result.config[:host].should == 'localhost'
        result.config[:port].should == 8080
        result.config[:ssl_ca].should == nil
        result.config[:ssl_cert].should == nil
        result.config[:ssl_key].should == nil
      end

        it 'should set custom configuration values and create an http object' do
          PuppetdbDiscovery.any_instance.expects(:create_http)
          pluginconf = { 'discovery.puppetdb.use_ssl' => 'y',
                           'discovery.puppetdb.host' => 'host.your.com',
                           'discovery.puppetdb.port' => '8081',
                           'discovery.puppetdb.ssl_ca' => 'rspec/ca.pem',
                           'discovery.puppetdb.ssl_cert' => 'rspec/host.your.com.cert.pem',
                           'discovery.puppetdb.ssl_private_key' => 'rspec/host.your.com.pem' }

          config.stubs(:pluginconf).returns(pluginconf)

          result = PuppetdbDiscovery.new(config)
          result.config[:ssl].should == 'y'
          result.config[:host].should == 'host.your.com'
          result.config[:port].should == '8081'
          result.config[:ssl_ca].should == 'rspec/ca.pem'
          result.config[:ssl_cert].should == 'rspec/host.your.com.cert.pem'
          result.config[:ssl_key].should == 'rspec/host.your.com.pem'
        end
      end

      describe '#discover' do
        let(:filter) do
          {'fact' => [],
              'cf_class' => [],
              'identity' => []}
        end

        before do
          PuppetdbDiscovery.any_instance.stubs(:create_http)
          @plugin = PuppetdbDiscovery.new(config)
        end

        it 'should look up all the registered nodes if no filters are supplied' do
          @plugin.expects(:node_search).returns(['host.your.com'])
          @plugin.discover(filter).should == ['host.your.com']
        end

        it 'should do a fact search unless the fact filter is empty' do
          filter['fact'] = [{:fact => 'rspec', :value => 'rspec'}]
          @plugin.expects(:fact_search).with([{:fact => 'rspec', :value => 'rspec'}]).returns([])
          @plugin.expects(:class_search).never
          @plugin.expects(:identity_search).never

          @plugin.discover(filter)
        end

        it 'should do a class search unless the class filter is empty' do
          filter['cf_class'] = ['rspec']
          @plugin.expects(:class_search).with(['rspec']).returns([])
          @plugin.expects(:identity_search).never
          @plugin.expects(:fact_search).never

          @plugin.discover(filter)
        end

        it 'should do a identity search unless the identity filter is empty' do
          filter['identity'] = ['host.your.com']
          @plugin.expects(:identity_search).with(['host.your.com']).returns([])
          @plugin.expects(:class_search).never
          @plugin.expects(:fact_search).never

          @plugin.discover(filter)
        end

        it 'should return a array containing the union of the results' do
          filter = { 'fact' => [{:fact => 'rspec', :value => 'rspec'}],
                       'cf_class' => ['rspec'],
                       'identity' => ['host.your.com'] }

          @plugin.stubs(:fact_search).returns(['host1', 'host2'])
          @plugin.stubs(:class_search).returns(['host1'])
          @plugin.stubs(:identity_search).returns(['host1', 'host2'])

          result = @plugin.discover(filter)
          result.should == ['host1']
        end
      end

      describe '#create_http' do
        before do
          PuppetdbDiscovery.any_instance.stubs(:create_http)
          @plugin = PuppetdbDiscovery.new(config)
          PuppetdbDiscovery.any_instance.unstub(:create_http)
          Net::HTTP.stubs(:new).with('localhost', 8080).returns(http)
        end

        it 'should create an http object' do
          @plugin.expects(:configure_ssl).never
          @plugin.create_http.should == http
        end

        it 'should enable ssl if configured' do
          @plugin.config[:ssl] = '1'
          @plugin.expects(:configure_ssl)
          @plugin.create_http.should == http
        end
      end

      describe '#configure_ssl' do
        before do
          PuppetdbDiscovery.any_instance.stubs(:create_http).returns(http)
          @plugin = PuppetdbDiscovery.new(config)
        end

        it 'should fail if a ca was not set' do
          expect{
            @plugin.configure_ssl(http)
          }.to raise_error
        end

        it 'should fail if a cert was not configured' do
          @plugin.config[:ssl_ca] = 'rspec/ca.pem'

          expect{
            @plugin.configure_ssl(http)
          }.to raise_error
        end

        it 'should fail if a private key was not configured' do
          @plugin.config[:ssl_ca] = 'rspec/ca.pem'
          @plugin.config[:ssl_cert] = 'rspec/host.your.com.cert.pem'

          expect{
            @plugin.configure_ssl(http)
          }.to raise_error
        end

        it 'should configure the http object to use ssl' do
          @plugin.config[:ssl_ca] = 'rspec/ca.pem'
          @plugin.config[:ssl_cert] = 'rspec/host.your.com.cert.pem'
          @plugin.config[:ssl_key] = 'rspec/host.your.com.pem'
          cert = mock
          private_key = mock

          File.stubs(:read).with('rspec/host.your.com.cert.pem').returns('cert')
          File.stubs(:read).with('rspec/host.your.com.pem').returns('private_key')
          OpenSSL::X509::Certificate.stubs(:new).with('cert').returns(cert)
          OpenSSL::PKey::RSA.stubs(:new).with('private_key').returns(private_key)
          http.expects(:use_ssl=).with(true)
          http.expects(:verify_mode=).with(OpenSSL::SSL::VERIFY_PEER)
          http.expects(:cert=).with(cert)
          http.expects(:ca_file=).with('rspec/ca.pem')
          http.expects(:key=).with(private_key)
          @plugin.configure_ssl(http)
        end
      end

      describe '#fact_search' do
        it 'should make a node request for a given fact' do
          PuppetdbDiscovery.any_instance.stubs(:create_http).returns(http)
          @plugin = PuppetdbDiscovery.new(config)
          response = "[{\"name\":\"host1.your.com\"},{\"name\":\"host2.your.com\"}]"
          @plugin.stubs(:make_request).returns(response)

          query = [['=', ['fact', 'rspec'], 'testvalue']]
          @plugin.stubs(:transform_query).with(query, 'node')
          @plugin.fact_search([{:fact => 'rspec', :value => 'testvalue', :operator => '=='}]).should == ['host1.your.com', 'host2.your.com']
        end
      end

      describe '#class_search' do
        it 'should make a resource request for a given class' do
          PuppetdbDiscovery.any_instance.stubs(:create_http).returns(http)
          @plugin = PuppetdbDiscovery.new(config)
          @plugin.stubs(:make_request)
          JSON.stubs(:parse).returns([{'certname' => 'host1.your.com', 'title' => 'Rspec::Config'}])

          query = [['and', ['=', 'type', 'Class'], ['=', 'title', 'Rspec::Config']]]
          @plugin.stubs(:transform_query).with(query, 'klass')
          @plugin.class_search(['Rspec::Config']).should == ['host1.your.com']
        end
      end

      describe '#identity_search' do

        before do
          PuppetdbDiscovery.any_instance.stubs(:create_http).returns(http)
          @plugin = PuppetdbDiscovery.new(config)
          response = ['host1.your.com', 'host2.your.com']
          @plugin.stubs(:node_search).returns(response)
        end

        it 'should return an array of nodes matching the filter' do
          @plugin.identity_search(['host1.your.com']).should == ['host1.your.com']
        end

        it 'should return an array of nodes matching a regex filter' do
          @plugin.identity_search(['/host/']).should == ['host1.your.com', 'host2.your.com']
        end
      end

      describe '#node_search' do
        it 'should look up all the nodes registered in puppetdb' do
          PuppetdbDiscovery.any_instance.stubs(:create_http).returns(http)
          @plugin = PuppetdbDiscovery.new(config)
          response = "[{\"name\":\"host1.your.com\"},{\"name\":\"host2.your.com\"}]"
          @plugin.stubs(:make_request).returns(response)
          @plugin.node_search.should == ['host1.your.com', 'host2.your.com']
        end
      end

      describe '#make_request' do
        let(:response) { mock }

        before do
          PuppetdbDiscovery.any_instance.stubs(:create_http).returns(http)
          @plugin = PuppetdbDiscovery.new(config)
        end

        it 'should make a request and return the response data' do
          response.stubs(:code).returns('200')
          response.stubs(:message).returns('success')
          http.expects(:get).with('/v2/nodes?query=query_string', {'accept' => 'application/json'}).returns([response, 'success'])
          @plugin.make_request('nodes', 'query_string').should == 'success'
        end

        it 'should fail if the request fails' do
          response.stubs(:code).returns('400')
          response.stubs(:message).returns('failure')
          http.expects(:get).with('/v2/nodes?query=query_string', {'accept' => 'application/json'}).returns([response, 'failure'])
          expect{
            @plugin.make_request('nodes', 'query_string').should == 'success'
          }.to raise_error
        end
      end

      describe '#transform_query' do
        before do
          PuppetdbDiscovery.any_instance.stubs(:create_http).returns(http)
          @plugin = PuppetdbDiscovery.new(config)
        end

        it 'should return the query if the array size is 1' do
          query = [['=', ['fact', 'rspec'], 'testvalue']]
          @plugin.transform_query(query).should == query[0]
        end

        it 'should transform a fact query' do
          query = [ ['=', ['fact', 'rspec1'], 'testvalue1'],
            ['=', ['fact', 'rspec2'], 'testvalue2'] ]

          result = ['and',
            ['=', ['fact', 'rspec1'], 'testvalue1'],
            ['=', ['fact', 'rspec2'], 'testvalue2']
          ]

          @plugin.transform_query(query, 'node').should == result
        end

        it 'should transform a class query' do
          query = [ ['and', ['=', 'type', 'Class'], ['=', 'title', 'rspec1']],
            ['and', ['=', 'type', 'Class'], ['=', 'title', 'rspec2']] ]

          result = [ 'or',
            ['and', ['=', 'type', 'Class'], ['=', 'title', 'rspec1']],
            ['and', ['=', 'type', 'Class'], ['=', 'title', 'rspec2']]
          ]

          @plugin.transform_query(query, 'klass').should == result
        end
      end

      describe '#translate_value' do
        before do
          PuppetdbDiscovery.any_instance.stubs(:create_http).returns(http)
          @plugin = PuppetdbDiscovery.new(config)
        end

        it 'should correctly translate a regular expression value pair' do
          @plugin.translate_value('/rspec/', '=').should == ['~', 'rspec']
        end

        it 'should correctly translate a equality operator' do
          @plugin.translate_value('Rspec::Config', '==').should == ['=', 'Rspec::Config']
        end

        it 'should return the operator and value unchanged if its not a special case' do
          @plugin.translate_value('value', '>=').should == ['>=', 'value']
        end
      end
    end
  end
end
