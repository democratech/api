require File.expand_path('../config/environment', __FILE__)

use Rack::Cors do
	allow do
		origins '*'
		resource '*', headers: :any, methods: :get
	end
end

Mongo::Logger.logger.level = Logger::WARN
Democratech::API.mg_client=Mailgun::Client.new(MGUNKEY)
Democratech::API.mandrill=Mandrill::API.new(MANDRILLKEY)
Democratech::API.db=Mongo::Client.new(DBURL)
Stripe.api_key=STRLIVE

run Democratech::API
