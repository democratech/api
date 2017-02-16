require File.expand_path('../config/environment', __FILE__)

use Rack::Cors do
	allow do
		origins '*'
		resource '*', headers: :any, methods: [:get,:delete,:post,:put]
	end
end

PGPWD=DEBUG ? PGPWD_TEST : PGPWD_LIVE
PGNAME=DEBUG ? PGNAME_TEST : PGNAME_LIVE
PGUSER=DEBUG ? PGUSER_TEST : PGUSER_LIVE
PGHOST=DEBUG ? PGHOST_TEST : PGHOST_LIVE
STR_KEY=DEBUG ? STRTEST : STRLIVE
COCORICO_HOST=DEBUG ? CC_HOST_TEST : CC_HOST
COCORICO_APP_ID=DEBUG ? CC_APP_ID_TEST : CC_APP_ID
COCORICO_SECRET=DEBUG ? CC_SECRET_TEST : CC_SECRET

puts "connect to database : #{PGNAME} with user : #{PGUSER}"
Democratech::API.log=Logger.new(::DEBUG ? STDOUT : STDERR)
Democratech::API.log.level= ::DEBUG ? Logger::DEBUG : Logger::WARN
Algolia.init :application_id=>ALGOLIA_ID, :api_key=>ALGOLIA_KEY
Mongo::Logger.logger.level = Logger::WARN
Democratech::API.twilio = Twilio::REST::LookupsClient.new(TWILIO_ACC_SID,TWILIO_AUTH_TOKEN)
Authy.api_key = AUTHY_API_KEY
Authy.api_uri = AUTHY_API_URI
Democratech::API.mg_client=Mailgun::Client.new(MGUNKEY)
Democratech::API.mandrill=Mandrill::API.new(MANDRILLKEY)
Democratech::API.db=Mongo::Client.new(DBURL)
Democratech::API.aws=Aws::S3::Resource.new(credentials: Aws::Credentials.new(AWS_API_KEY,AWS_API_SECRET),region: AWS_REGION)
Stripe.api_key=STR_KEY

run Democratech::API
