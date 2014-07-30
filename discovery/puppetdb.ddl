metadata    :name        => "puppetdb discovery",
            :description => "PuppetDB based discovery",
            :author      => "R.I.Pienaar <rip@devco.net>",
            :license     => "ASL 2.0",
            :version     => "0.2",
            :url         => "http://marionette-collective.org/",
            :timeout     => 0

discovery do
    capabilities [:identity, :classes, :facts]
end
