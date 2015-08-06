require 'grape'
require 'mongo'
require 'bson'
require 'time'
Mongo::Logger.logger.level = Logger::WARN

#Field9=thibauld&Field10=favre&Field1=tfa.vre%40gmail.com&Field127=France&Field118=67210&Field130=&Field119=test&CreatedBy=democratech&DateCreated=2015-08-05+19%3A33%3A11&EntryId=43&IP=71.235.37.168&HandshakeKey=

$db=Mongo::Client.new('mongodb://127.0.0.1:27017/democratech')
$supporteurs=$db[:supporteurs]
$communes=$db[:communes]

module Democratech

	class API < Grape::API
		prefix 'api'
		version 'v1'

		resource :front do
			http_basic do |u,p|
				u=='democratech' && p== 'toto'
			end
		end

		resource :mailchimp do
			post 'subscriber' do
				puts params
			end
		end

		resource :wufoo do
			helpers do
				def authorized
					params['HandshakeKey']=='DemocratechForTheWin'
				end
			end
			post 'entry' do
				error!('401 Unauthorized', 401) unless authorized
				doc={
					:firstName=>params["Field9"].capitalize,
					:lastName=>params["Field10"].upcase,
					:email=>params["Field1"].downcase,
					:country=>params["Field127"].upcase,
					:postalCode=>params["Field118"].strip.gsub(/\s+/,""),
					:city=>params["Field130"],
					:reason=>params["Field119"],
					:created=> Time.now.utc
				}
				if doc[:city].empty? and not doc[:postalCode].empty? then
					commune=$communes.find({"postalCode"=>doc[:postalCode]}).first
					doc[:city]=commune['name'] unless commune.nil?
				end
				$db[:supporteurs].insert_one(doc)
			end
		end
	end
end
