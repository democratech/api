DEBUG=(ENV['RACK_ENV']!='production')
STDOUT.puts "debug mode : #{DEBUG}"
require File.expand_path('../application', __FILE__)
