#PuppetDB Discovery Plugin

The PuppetDB discovery plugin can be used to facilitate discovery instead of using the standard MCollective discovery method.
This means that instead of querying the network for discovery, the plugin will match hosts based on nodes, classes and facts
stored in PuppetDB.

##Installation

Follow the [basic plugin install guide.](http://projects.puppetlabs.com/projects/mcollective-plugins/wiki/InstalingPlugins)

##Configuration

The PuppetDB discovery plugin can be activated either by specifying it in your client.cfg file

    default_discovery_method = puppetdb

or by using it on the cli

    % mco rpc rpcutil ping --dm puppetdb -F operatingsytem=CentOS

Other configuration settings that can be tuned depending our your PuppetDB installation are :

 * discovery.puppetdb.host - The hostname of the PuppetDB server. Defaults to localhost
 * discovery.puppetdb.port - The unencrpyted HTTP __or__ SSL port your PuppetDB server listens on. Defaults to 8080
 * discovery.puppetdb.use_ssl - Enable using SSL. Defaults to false
 * discovery.puppetdb.use_krb - Enable using Kerberos. Defaults to false
 * discovery.puppetdb.collective_fact - Define a fact to filter all queries with the value of the collective thus avoiding to fetch all the nodes registered in puppetdb each time. Defaults to false

The following settings should only be configured if you are using SSL communications. They will all be disabled by default.

 * discovery.puppetdb.ssl_ca - The CA certificate
 * discovery.puppetdb.ssl_cert - The client node's certificate file
 * discovery.puppetdb.ssl_private_key - The client node's private key

###Example configurations

Connect to a remote PuppetDB server using unencrypted http traffic.

     default_discovery_method = puppetdb

     plugin.discovery.puppetdb.host = puppetdb.your.com
     plugin.discovery.puppetdb.port = 8080

Connect to a remote PuppetDB server using SSL

     default_discovery_method = puppetdb

     plugin.discovery.puppetdb.host = puppetdb.your.com
     plugin.discovery.puppetdb.port = 8081
     plugin.discovery.puppetdb.use_ssl = 1
     plugin.discovery.puppetdb.ssl_ca = /etc/mcollective/puppetdb/ca.pem
     plugin.discovery.puppetdb.ssl_cert = /etc/mcollective/puppetdb/host1.your.com.cert.pem
     plugin.discovery.puppetdb.ssl_private_key = /etc/mcollective/puppetdb/host1.your.com.pem

Connect to a remote PuppetDB server using Kerberos

     default_discovery_method = puppetdb

     plugin.discovery.puppetdb.host = puppetdb.your.com
     plugin.discovery.puppetdb.port = 8082
     plugin.discovery.puppetdb.use_krb = 1
     plugin.discovery.puppetdb.ssl_ca = /etc/mcollective/puppetdb/ca.pem
     plugin.discovery.puppetdb.ssl_cert = /etc/mcollective/puppetdb/host1.your.com.cert.pem
     plugin.discovery.puppetdb.ssl_private_key = /etc/mcollective/puppetdb/host1.your.com.pem

Filter all queries using the hostgroup_0 fact

     plugin.discovery.puppetdb.collective_fact = hostgroup_0

The effect would be equivalent to -F hostgroup_0=<collective> in the command line

