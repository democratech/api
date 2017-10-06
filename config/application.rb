$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'api'))
$LOAD_PATH.unshift(File.dirname(__FILE__))

require 'boot'

Bundler.require :default, ENV['RACK_ENV']
require File.expand_path('../../api/mailer.rb', __FILE__)
Dir[File.expand_path('../../api/*_v*.rb', __FILE__)].each do |f|
	require f
end

require 'api'
