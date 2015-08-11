require './keys.local.rb'
require './api.rb'
require 'unicorn'

#DBURL = ENV['DBURL']
#MCKEY = ENV['MCKEY']
#MCURL = ENV['MCURL']
#MCLIST = ENV['MCLIST']
#MCFHS = ENV['MCFHS']
#WUFHS = ENV['WUFHS']
#SLCKHOST = ENV['SLCKHOST']
#SLCKPATH = ENV['SLCKPATH']

Mongo::Logger.logger.level = Logger::WARN
Democratech::API.db=Mongo::Client.new(DBURL)

run Democratech::API
