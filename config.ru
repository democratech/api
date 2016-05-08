require File.expand_path('../config/environment', __FILE__)

use Rack::Cors do
	allow do
		origins '*'
		resource '*', headers: :any, methods: :get
	end
end

DEBUG=(ENV['RACK_ENV']!='production')
PRODUCTION=(ENV['RACK_ENV']=='production')
PGPWD=DEBUG ? PGPWD_TEST : PGPWD_LIVE
PGNAME=DEBUG ? PGNAME_TEST : PGNAME_LIVE
PGUSER=DEBUG ? PGUSER_TEST : PGUSER_LIVE
PGHOST=DEBUG ? PGHOST_TEST : PGHOST_LIVE
STR_KEY=DEBUG ? STRTEST : STRLIVE
puts "connect to database : #{PGNAME} with user : #{PGUSER}"

Mongo::Logger.logger.level = Logger::WARN
Democratech::API.mg_client=Mailgun::Client.new(MGUNKEY)
Democratech::API.mandrill=Mandrill::API.new(MANDRILLKEY)
Democratech::API.db=Mongo::Client.new(DBURL)
Democratech::API.aws=Aws::S3::Resource.new(credentials: Aws::Credentials.new(AWS_API_KEY,AWS_API_SECRET),region: AWS_REGION)
Stripe.api_key=STR_KEY

run Democratech::API
