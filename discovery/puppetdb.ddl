metadata    :name        => "puppetdb discovery",
            :description => "PuppetDB based discovery",
            :author      => "Pieter Loubser <ploubser@gmail.com>",
            :license     => "ASL 2.0",
            :version     => "0.3.2",
            :url         => "http://marionette-collective.org/",
            :timeout     => 0

discovery do
    capabilities [:identity, :classes, :facts]
end
