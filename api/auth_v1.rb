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

require 'digest'
require 'date'
require 'net/http'

module Democratech
	class AuthV1 < Grape::API
		version ['v1']
		format :json

		get do
			# DO NOT DELETE used to test the api is live
			return {"api_version"=>"v1"}
		end

		resource :auth do
			helpers do
				def strip_tags(text)
					return text.gsub(/<\/?[^>]*>/, "")
				end

				def get_citizen(user_key)
					user_key_lookup=<<END
SELECT c.telegram_id,c.firstname,c.lastname,c.email,c.reset_code,c.registered,c.country,c.user_key,c.validation_level,c.birthday,t.*,ci.zipcode,ci.name as city,ci.population,ci.departement
FROM users AS c 
LEFT JOIN cities AS ci ON (ci.city_id=c.city_id)
LEFT JOIN telephones AS t ON (t.international=c.telephone)
WHERE c.user_key=$1
END
					res=API.pg.exec_params(user_key_lookup,[user_key])
					return res.num_tuples.zero? ? nil : res[0]
				end

				def update_citizen(citoyen,infos)
					update="UPDATE users SET #{infos['key']}=$2 WHERE user_key=$1"
					res=API.pg.exec_params(update,[citoyen['user_key'],infos['val']])
					return res.num_tuples.zero? ? nil : res[0]
				end

				def get_user_agent()
					hash=Digest::SHA256.hexdigest(request.user_agent)
					get_ua="SELECT * FROM user_agents WHERE useragent_hash=$1"
					res=API.pg.exec_params(get_ua,[hash])
					if res.num_tuples.zero? then
						new_ua="INSERT INTO user_agents (useragent_hash,useragent_raw) VALUES ($1,$2) RETURNING *"
						res=API.pg.exec_params(new_ua,[hash,request.user_agent])
					end
					return res.num_tuples.zero? ? nil : res[0]
				end

				def track_step(citoyen,step,ballot_id=nil)
					ua=get_user_agent()
					track_step="INSERT INTO auth_history (email,useragent_id,ballot_id,ip_address,ip_forwarded,step) VALUES ($1,$2,$3,$4,$5,$6) RETURNING *"
					res=API.pg.exec_params(track_step,[citoyen['email'],ua['useragent_id'],ballot_id,request.ip,request.env["HTTP_X_FORWARDED_FOR"],step])
					return res.num_tuples.zero? ? nil : res[0]
				end

				def verify_email(citoyen)
					verify_email="UPDATE users SET validation_level=(validation_level|1) WHERE user_key=$1 AND (validation_level&1)=0 RETURNING *"
					res=API.pg.exec_params(verify_email,[citoyen['user_key']])
					return res.num_tuples.zero? ? nil : res[0]
				end

				def get_phone(number)
					phone_lookup="SELECT u.email,u.user_key,t.* FROM telephones as t LEFT JOIN users as u ON (u.telephone=t.international) WHERE t.international=$1"
					res=API.pg.exec_params(phone_lookup,[number])
					return res.num_tuples.zero? ? nil : res[0]
				end

				def update_phone(infos)
					phone_update="UPDATE telephones SET carrier_name=$2, is_cellphone=$3 WHERE international=$1 RETURNING *"
					res=API.pg.exec_params(phone_update,[infos['phone_number'],infos['carrier'],infos['is_cellphone']])
					return res.num_tuples.zero? ? nil : res[0]
				end

				def register_phone(infos)
					phone_register=<<END
WITH countries AS (SELECT dial_code FROM countries WHERE iso2=$3) INSERT INTO telephones (international,national,country_code,prefix) SELECT $1,$2,$3,countries.dial_code FROM countries RETURNING *
END
					res=API.pg.exec_params(phone_register,[infos['phone_number'],infos['national_format'],infos['country_code']])
					return res.num_tuples.zero? ? nil : res[0]
				end

				def update_user_with_phone(citoyen,number)
					update_tel="UPDATE users SET telephone=$1 WHERE user_key=$2 RETURNING *"
					res=API.pg.exec_params(update_tel,[number,citoyen['user_key']])
					return res.num_tuples.zero? ? nil : res[0]
				end

				def guess_birthdate(val)
					begin
						val=Date.parse(val).strftime("%Y-%m-%d")
						return val
					rescue ArgumentError=>e
						return nil if val.length!=8
						jj=val[0..1]
						mm=val[2..3]
						aaaa=val[4..8]
						return nil if (jj.to_i<1 || jj.to_i>31)
						return nil if (mm.to_i<1 || mm.to_i>12)
						return nil if (aaaa.to_i<1916 || aaaa.to_i>2010)
						return aaaa+'-'+mm+'-'+jj
					end
				end

				def get_geodata(ip)
					uri = URI.parse('https://geoip.maxmind.com')
					http = Net::HTTP.new(uri.host, uri.port)
					http.use_ssl = true
					request = Net::HTTP::Get.new("/geoip/v2.1/city/#{ip}")
					request.basic_auth(MAXMIND_USER,MAXMIND_PWD)
					return http.request(request)
				end
			end

			get do
				return {"api_version"=>"auth/v1"} # DO NOT DELETE used to test the api is live
			end

			get 'step/:user_key' do
				step=params['step']
				steps=["verif_email","firstname","lastname","city","birthday","phone","verif_phone","facebook","ballot_creation"]
				return {"error"=>"missing step"} if step.nil?
				return {"error"=>"unknown step"} if !steps.include?(step)
				pg_connect()
				answer={"step"=>nil}
				begin
					user_key=params['user_key']
					citoyen=get_citizen(user_key)
					if citoyen.nil? then
						status 403 
						return {"error"=>"unknown_user"}
					end
					answer["step"]=step if !track_step(citoyen,step).nil?
				rescue PG::Error=>e
					status 500
					API.log.error "step/#{step} PG error #{e.message}"
				ensure
					pg_close()
				end
				return answer
			end

			get 'email/verif/:user_key' do
				pg_connect()
				answer={"verified"=>"no"}
				begin
					user_key=params['user_key']
					citoyen=get_citizen(user_key)
					return {"info"=>"already_verified"} if (citoyen['validation_level'].to_i&1)==1
					if citoyen.nil? then
						status 403 
						return {"error"=>"unknown_user"}
					end
					updated_citoyen=verify_email(citoyen)
					if updated_citoyen.nil? then
						API.log.error "email/verif unable to verify citizen email #{citoyen['email']}"
						return answer
					end
					answer["verified"]="yes"
				rescue PG::Error=>e
					status 500
					API.log.error "email/verif PG error #{e.message}"
				ensure
					pg_close()
				end
				return answer
			end

			get 'phone/lookup/:user_key' do
				pg_connect()
				answer={"verif_sent"=>"no"}
				begin
					user_key=params['user_key']
					citoyen=get_citizen(user_key)
					if citoyen.nil? then
						status 403 
						return {"error"=>"unknown_user"}
					end
					tel=params['tel']
					type=params['type']
					return {"error"=>"wrong_type"} if (type!="sms" and type!="call")
					lookup=API.twilio.phone_numbers.get(tel)
					phone_number=lookup.phone_number
					national=lookup.national_format
					country_code=lookup.country_code
					phone=get_phone(phone_number)
					if phone.nil? then # first time we see this phone
						phone=register_phone({'phone_number'=>phone_number,'national_format'=>national,'country_code'=>country_code})
						update_user_with_phone(citoyen,phone_number)
					elsif phone['user_key'].nil? then # phone is registered but not associated with any account / email
						API.log.warn "phone/lookup orphan phone #{phone_number} is assigned to user #{citoyen['email']}"
						update_user_with_phone(citoyen,phone_number)
					elsif phone['user_key']!=user_key then # phone is already used by someone
						API.log.error "phone/lookup phone #{phone_number} is already registered by another user"
						return {"error"=>"phone_already_used" }
					end
					answer={"tel"=>"#{phone_number}"}
					dial_code=phone['prefix']
					response = Authy::PhoneVerification.start(via: type, country_code: dial_code, phone_number: national)
					if response.ok? then
						answer["verif_sent"]="yes"
						update_phone({'phone_number'=>phone_number,'carrier'=>response.carrier,'is_cellphone'=>response.is_cellphone})
					end
					API.log.error "phone/lookup phone verification did not start: #{citoyen['email']} / via: #{type}, cc: #{dial_code}, phone: #{national}" unless response.ok?
				rescue Twilio::REST::RequestError=>e
					status 404
					API.log.error "phone/lookup #{tel} Twilio error: #{e.message}"
				rescue PG::Error=>e
					status 500
					API.log.error "phone/lookup PG error #{e.message}"
				ensure
					pg_close()
				end
				return answer
			end

			get 'phone/verif/:user_key' do
				pg_connect()
				answer={"verified"=>"no"}
				begin
					user_key=params['user_key']
					citoyen=get_citizen(user_key)
					if citoyen.nil? then
						status 403 
						return {"error"=>"unknown user"}
					end
					code=params['code']
					response = Authy::PhoneVerification.check(verification_code: code, country_code: citoyen['prefix'], phone_number: citoyen['international'])
					if response.ok? then
						answer["verified"]="yes"
						update_validation="UPDATE users SET validation_level=(validation_level|2) WHERE user_key=$1 RETURNING *"
						res=API.pg.exec_params(update_validation,[user_key])
						API.log.error "phone/verif unable to user validation level for #{citoyen['email']} / #{phone}" if res.num_tuples.zero?
					else
						API.log.error "phone/verif wrong code #{code} for #{citoyen['email']} : country_code #{citoyen['prefix']}, phone : #{citoyen['international']}"
					end
				rescue Twilio::REST::RequestError=>e
					status 404
					API.log.error "phone/verif Twilio error: #{e.message}"
				rescue PG::Error=>e
					status 500
					API.log.error "phone/verif PG error #{e.message}"
				ensure
					pg_close()
				end
				return answer
			end

			get 'update/:user_key' do
				pg_connect()
				answer={}
				key=params['key']
				val=strip_tags(params['val'])
				keys=["firstname","lastname","birthday"]
				return {"error"=>"missing value"} if (val.nil? || val=="")
				return {"error"=>"too large request"} if val.length>25
				return {"error"=>"erroneous request"} if !keys.include?(key)
				begin
					user_key=params['user_key']
					citoyen=get_citizen(user_key)
					if citoyen.nil? then
						status 403 
						return {"error"=>"unknown_user"}
					end
					val=guess_birthdate(val) if key=="birthday"
					update_citizen(citoyen,{"key"=>key,"val"=>val})
					answer[key]=val
				rescue ArgumentError=>e
					status 500
					answer={"error"=>"invalid_date"}
					API.log.error "update/#{key} invalid birthday #{params} #{e.message}"
				rescue PG::Error=>e
					status 500
					API.log.error "update/#{key} PG error #{e.message}"
				ensure
					pg_close()
				end
				return answer
			end

			get 'geodata/lookup' do
				ip=request.ip
				ip='46.101.163.182' if ::DEBUG
				geodata=JSON.parse(get_geodata(ip).body)
				state=nil
				state=(geodata['subdivisions'][0].nil? ? nil : geodata['subdivisions'][0]['iso_code']) unless geodata['subdivisions'].nil?
				city=nil
				city=(geodata['city']['names'].nil? ? nil : geodata['city']['names']['fr']) unless geodata['city'].nil?
				zipcode=nil
				zipcode=geodata['postal']['code'] unless geodata['postal'].nil?
				data=[
					ip,
					city,
					geodata['location']['latitude'],
					geodata['location']['longitude'],
					geodata['location']['accuracy_radius'],
					geodata['continent']['code'],
					geodata['country']['iso_code'],
					state,
					zipcode,
					geodata['location']['time_zone'],
					JSON.dump(geodata),
					geodata['traits']['isp'],
					geodata['traits']['organization']
				]
				answer={"lookup"=>"OK","country"=>geodata['country']['iso_code']}
				pg_connect()
				begin
					query="SELECT * FROM ip_addresses WHERE ip_address=$1"
					res=API.pg.exec_params(query,[ip])
					if res.num_tuples.zero? then
						query="INSERT INTO ip_addresses (ip_address, city_name, lat_deg, lon_deg, accuracy_radius, continent_code, country_code, state_code, zip_code, time_zone, geodata, isp, organization) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13) RETURNING *"
						res=API.pg.exec_params(query,data)
						raise "could not insert ip_address" if res.num_tuples.zero?
					else
						query="UPDATE ip_addresses SET ip_address=CAST($1 AS VARCHAR), city_name=$2, lat_deg=$3, lon_deg=$4, accuracy_radius=$5, continent_code=$6, country_code=$7, state_code=$8, zip_code=$9, time_zone=$10, geodata=$11, isp=$12, organization=$13, updated_at=now() WHERE ip_address=$1 AND now()>(updated_at+interval '15 days') RETURNING *"
						res=API.pg.exec_params(query,data)
					end
				rescue StandardError=>e
					status 500
					answer={"lookup"=>"KO"}
					API.log.error "geodata/lookup Standard Error #{params} #{e.message}"
				rescue ArgumentError=>e
					status 500
					answer={"lookup"=>"KO"}
					API.log.error "geodata/lookup Argument Error #{params} #{e.message}"
				rescue PG::Error=>e
					status 500
					answer={"lookup"=>"KO"}
					API.log.error "geodata/lookup PG error #{e.message}"
				ensure
					pg_close()
				end
				return answer
			end
		end
	end
end
