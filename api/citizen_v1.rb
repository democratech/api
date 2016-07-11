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
		end
	end
end
