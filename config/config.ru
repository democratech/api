APP_ROOT = File.expand_path(File.dirname(File.dirname(__FILE__))) unless defined? APP_ROOT
require APP_ROOT+'/config/keys.local.rb'
require APP_ROOT+'/api.rb'
require 'unicorn'

Mongo::Logger.logger.level = Logger::WARN
Democratech::API.db=Mongo::Client.new(DBURL)

run Democratech::API
