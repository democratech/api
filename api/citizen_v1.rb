# encoding: utf-8

=begin
    democratech API synchronizes the various Web services democratech uses
    Copyright (C) 2015,2016  Thibauld Favre

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU Affero General Public License as published
    by the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU Affero General Public License for more details.

    You should have received a copy of the GNU Affero General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
=end

module Democratech
	class CitizenV1 < Grape::API
		version ['v1','v2']
		format :json

		get do
			# DO NOT DELETE used to test the api is live
			return {"api_version"=>"v1"}
		end

		resource :citizen do
			helpers do
				def authorized
					params['HandshakeKey']==WUFHS
				end

				def upload_image(filename)
					bucket=API.aws.bucket(AWS_BUCKET)
					key=File.basename(filename)
					obj=bucket.object(key)
					if bucket.object(key).exists? then
						STDERR.puts "#{key} already exists in S3 bucket. deleting previous object."
						obj.delete
					end
					content_type=MimeMagic.by_magic(File.open(filename)).type
					obj.upload_file(filename, acl:'public-read',cache_control:'public, max-age=14400', content_type:content_type)
					return key
				end

				def strip_tags(text)
					return text.gsub(/<\/?[^>]*>/, "")
				end

				def fix_wufoo(url)
					url.gsub!(':/','://') if url.match(/https?:\/\//).nil?
					return url
				end
			end

			get do
				# DO NOT DELETE used to test the api is live
				return {"api_version"=>"citizen/v1"}
			end

			post 'city' do
				user_key=params["key"]
				json='{}'
				return "{'error':'key missing'}" if user_key.nil?
				begin
					pg_connect()
					suggestion=params["suggestion"]
					city=suggestion['suggestion']['name'].gsub(/ \d.*/,'') unless suggestion['suggestion']['name'].nil?
					zipcode=suggestion['suggestion']['postcode']
					country=suggestion['suggestion']['country']
					country="ETATS-UNIS" if country=="États-Unis d'Amérique"
					if country.upcase=='FRANCE' then
						villes=Algolia::Index.new("villes")
						v=villes.search(city,{hitsPerPage:1})
						city_id=v["hits"][0]["objectID"]
						city=v["hits"][0]["name"]
						update_city="UPDATE users SET city_id=$2, city=upper($3), zipcode=$4, country=upper($5) WHERE user_key=$1 RETURNING *"
						res=API.pg.exec_params(update_city,[user_key,city_id,city,zipcode,country])
						if res.num_tuples.zero? then
							json="{'error':'update city failed: #{city}/#{zipcode}'}"
						else
							json="{\"city\":\"#{city}\", \"zipcode\":\"#{zipcode}\",\"country\":\"#{country}\"}"
						end
					else
						countries=Algolia::Index.new("countries")
						c=countries.search(country,{hitsPerPage:1})
						country=c["hits"][0]["name"]
						update_city="UPDATE users SET city=upper($2), city_id=null, zipcode=$3, country=upper($4) WHERE user_key=$1 RETURNING *"
						res=API.pg.exec_params(update_city,[user_key,city,zipcode,country])
						if res.num_tuples.zero? then
							json="{'error':'update city failed: #{city}/#{zipcode}/#{country} with key #{user_key}'}"
						else
							json="{\"city\":\"#{city}\", \"zipcode\":\"#{zipcode}\",\"country\":\"#{country}\"}"
						end
					end
				rescue PG::Error=>e
					STDERR.puts "Error updating city: #{e}"
				ensure
					pg_close()
				end
				return json
			end

			post 'add' do
				error!('401 Unauthorized', 401) unless authorized
				errors=[]
				notifs=[]

				# 1. We read the new supporter info from the parameters
				doc={}
				doc[:firstname]=params["Field9"].capitalize.strip unless params["Field9"].nil?
				doc[:lastname]=params["Field10"].upcase.strip unless params["Field10"].nil?
				doc[:referer]=params["Field12"].strip unless params["Field12"].nil?
				doc[:candidate]=params["Field14"].strip unless params["Field14"].nil?
				doc[:email]=params["Field1"].downcase.gsub(/\A\p{Space}*|\p{Space}*\z/, '') unless params["Field1"].nil?
				begin
					pg_connect()
					get_user_by_email=<<END
SELECT z.*,c.slug,c.zipcode,c.departement,c.lat_deg,c.lon_deg FROM users AS z LEFT JOIN cities AS c ON (c.city_id=z.city_id) WHERE z.email=$1
END
					res=API.pg.exec_params(get_user_by_email,[doc[:email]])
					if res.num_tuples.zero? then # user does not yet exists
						new_user=<<END
INSERT INTO users (email,firstname,lastname,user_key,referal_code,referer) VALUES ($1,$2,$3,md5(random()::text),substring(md5($4) from 1 for 8),$5) returning *;
END
						res1=API.pg.exec_params(new_user,[doc[:email],doc[:firstname],doc[:lastname],doc[:email],doc[:referer]])
						raise "New user was not registered" if res1.num_tuples.zero?
						from_candidat=""
						if not (doc[:candidate].nil? or doc[:candidate].empty?) then # user has registered from a candidate page
							new_follower="INSERT INTO followers (candidate_id,email) VALUES ($1,$2)"
							res2=API.pg.exec_params(new_follower,[doc[:candidate],doc[:email]])
							raise "New follower was not registered" if res1.num_tuples.zero?
							from_candidat="à partir d'une page candidat "
						end
						with_referer= (doc[:referer].nil? or doc[:referer].empty?) ? "":"avec referal code "
						notifs.push([
							"Nouvel inscrit à LaPrimaire.org #{from_candidat}#{with_referer}! %s %s" % [doc[:firstname],doc[:lastname]],
							"supporteurs",
							":memo:",
							"pg"
						])
					end
				rescue StandardError => e
					notifs.push([
						"Erreur (PG::Error) lors de l'enregistrement d'un citoyen: %s (%s, %s)\nError message: %s\nError trace: %s" % [doc[:email],doc[:firstname],doc[:lastname],e.message,res.inspect],
						"errors",
						":scream:",
						"pg"
					])
					errors.push('400 Supporter could not be registered')
				rescue PG::Error => e
					notifs.push([
						"Erreur (PG::Error) lors de l'enregistrement d'un citoyen: %s (%s, %s)\nError message: %s\nError trace: %s" % [doc[:email],doc[:firstname],doc[:lastname],e.message,res.inspect],
						"errors",
						":scream:",
						"pg"
					])
					errors.push('400 Supporter could not be registered')
				ensure
					pg_close()
				end
				begin
					message= {
						:to=>[{
							:email=> "#{doc[:email]}",
							:name=> "#{doc[:firstname]} #{doc[:lastname]}"
						}],
						:merge_vars=>[{
							:rcpt=>"#{doc[:email]}"
						}]
					}
					result=API.mandrill.messages.send_template("laprimaire-org-bienvenue",[],message)
				rescue Mandrill::Error => e
					msg="A mandrill error occurred: #{e.class} - #{e.message}"
					STDERR.puts msg
				end

				# 4. We send the notifications and return
				slack_notifications(notifs)
				if not errors.empty? then
					error!(errors.join("\n"),400)
				end
			end
		end
	end
end
