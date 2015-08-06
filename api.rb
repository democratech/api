require 'grape'
require 'mongo'
require 'bson'
require 'time'

Mongo::Logger.logger.level = Logger::WARN

DBURL = ENV['DBURL']
MCKEY = ENV['MCKEY']
MCURL = ENV['MCURL']
MCLIST = ENV['MCLIST']
MCFHS = ENV['MCFHS']
WUFHS = ENV['WUFHS']

$db=Mongo::Client.new(DBURL)
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
			helpers do
				def authorized
					params['HandshakeKey']==WUFHS
				end
			end

			get 'subscriber' do
				# only required for mailchimp url validator
			end

			post 'subscriber' do
				# update the city of a subscriber when a subscriber is added
				if params["data[merges][CITY]"].empty? and not params["data[merges][ZIPCODE]"].empty? then
					zip=params["data[merges][ZIPCODE]"].strip.gsub(/\s+/,"")
					if not zip.match('^[0-9]{5}(?:-[0-9]{4})?$').nil? then
						commune=$communes.find({"postalCode"=>zip}).first
						if not commune.nil? then
							uri = URI.parse(MCURL)
							http = Net::HTTP.new(uri.host, uri.port)
							http.use_ssl = true
							http.verify_mode = OpenSSL::SSL::VERIFY_NONE
							request = Net::HTTP::Patch.new("/3.0/lists/"+MCLIST+"/members/"+id)
							request.basic_auth 'hello',MCKEY
							request.add_field('Content-Type', 'application/json')
							request.body = member
							http.request(request)
						end
					end
				end
			end
		end

		resource :wufoo do
			helpers do
				def authorized
					params['HandshakeKey']==WUFHS
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
