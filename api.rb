require 'grape'
require 'json'
require 'mongo'
require 'bson'
require 'time'
require 'net/http'
require 'uri'

module Democratech
	class API < Grape::API
		prefix 'api'
		version 'v1'
		class << self
			attr_accessor :db
		end

		helpers do
			def slack_notification(msg,channel="#supporteurs",icon=":ghost:",from="democratech")
				uri = URI.parse(SLCKHOST)
				http = Net::HTTP.new(uri.host, uri.port)
				http.use_ssl = true
				http.verify_mode = OpenSSL::SSL::VERIFY_NONE
				request = Net::HTTP::Post.new(SLCKPATH)
				request.body = "payload="+JSON.dump({
					"channel"=> channel,
					"username"=> from,
					"text"=> msg,
					"icon_emoji"=>icon
				})
				http.request(request)
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
				# DOES NOT WORK because we lack the subscriber ID in the params :( 
				if params["data"]["merges"]["CITY"].empty? and not params["data"]["merges"]["ZIPCODE"].empty? then
					zip=params["data"]["merges"]["ZIPCODE"].strip.gsub(/\s+/,"")
					if not zip.match('^[0-9]{5}(?:-[0-9]{4})?$').nil? then
						commune=API.db[:communes].find({:postalCode=>zip}).first
						if not commune.nil? then
							uri = URI.parse(MCURL)
							http = Net::HTTP.new(uri.host, uri.port)
							http.use_ssl = true
							http.verify_mode = OpenSSL::SSL::VERIFY_NONE
							request = Net::HTTP::Patch.new("/3.0/lists/"+MCLIST+"/members/"+params["data"]["id"])
							request.basic_auth 'hello',MCKEY
							request.add_field('Content-Type', 'application/json')
							request.body = JSON.dump({'merge_fields'=>{'CITY'=>commune}})
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
			post 'supporter' do
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
					commune=API.db[:communes].find({:postalCode=>doc[:postalCode]}).first
					doc[:city]=commune['name'] unless commune.nil?
				end
				begin
					res=API.db[:supporteurs].insert_one(doc)
					raise Exception.new(res.inspect) unless res.n==1
					slack_notification(
						"Nouveau supporteur ! %s %s (%s, %s, %s) : %s" % [doc[:firstName],doc[:lastName],doc[:postalCode],doc[:city],doc[:country],doc[:reason]],
						"#supporteurs",
						":thumbsup:"
					)
				rescue Exception=>e
					slack_notification(
						"Erreur lors de l'enregistrement d'un nouveau supporteur: %s ! %s %s (%s, %s, %s) : %s\nError msg: %s\nError trace: %s" % [doc[:email],doc[:firstName],doc[:lastName],doc[:postalCode],doc[:city],doc[:country],doc[:reason],e.message,e.backtrace.inspect[0..200]],
						"@thibauld",
						":scream:"
					)
				end
			end
			post 'contributor' do
				error!('401 Unauthorized', 401) unless authorized
				email=params["Field2"].downcase
				note=params["Field211"]
				tags=[]
				tags.push("ambassadeur") unless params["Field213"].empty?
				tags.push("event") unless params["Field214"].empty?
				tags.push("visibility") unless params["Field215"].empty?
				tags.push("presse") unless (params["Field314"].empty? and params["Field315"].empty?)
				tags.push("creatif graphique") unless params["Field415"].empty?
				tags.push("creatif video") unless params["Field416"].empty?
				tags.push("content") unless params["Field417"].empty?
				tags.push("seo") unless params["Field418"].empty?
				tags.push("donateur") unless params["Field516"].empty?
				tags.push("fundraiser") unless params["Field517"].empty?
				tags.push("fundraiser") unless params["Field517"].empty?
				tags.push("elu") unless (params["Field617"].empty? and params["Field618"].empty?)
				tags.push("candidat") unless (params["Field10"].empty? and params["Field11"].empty?)
				tags.push("beta-testeur") unless params["Field110"].empty?
				tags.push("developer") unless (params["Field112"].empty? and params["Field113"].empty?)
				tags.push("android") unless params["Field114"].empty?
				tags.push("ios") unless params["Field115"].empty?
				update={
					:contributeur=>1,
					:dispo=>params["Field3"],
					:tags=>tags,
					:lastUpdated=>Time.now.utc
				}
				begin
					res=API.db[:supporteurs].find({:email=>email}).update_one({'$set'=>update})
					if res.n==0 then
						update[:email]=email
						update[:created]=Time.now.utc
						res=API.db[:supporteurs].insert_one(update)
						raise Exception.new(res.inspect) unless res.n==1
					end
					slack_notification(
						"Nouveau contributeur !\nDispo: %s\nTags: %s\nNote: %s" % [update[:dispo],tags.inspect,note],
						"#supporteurs",
						":muscle:"
					)
				rescue Exception=>e
					slack_notification(
						"Erreur lors de l'enregistrement d'un nouveau contributeur !\nEmail: %s\nDispo: %s\nTags: %s\nError msg: %s\nError trace: %s" % [email,update[:dispo],tags.inspect,e.message,e.backtrace.inspect[0..200]+"..."],
						"@thibauld",
						":fearful:"
					)
				end
			end
		end
	end
end
