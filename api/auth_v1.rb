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
	class AuthV1 < Grape::API
		version ['v1','v2']
		format :json

		get do
			# DO NOT DELETE used to test the api is live
			return {"api_version"=>"v1"}
		end

		resource :auth do
			helpers do
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

				def get_phone(number)
					phone_lookup="SELECT u.email,u.user_key,t.* FROM telephones as t INNER JOIN users as u ON (u.telephone=t.international) WHERE t.international=$1"
					res=API.pg.exec_params(phone_lookup,[number])
					return res.num_tuples.zero? ? nil : res[0]
				end

				def update_phone(infos)
					phone_update="UPDATE telephones SET carrier_name=$2, is_cellphone=$3, is_ported=$4 WHERE international=$1 RETURNING *"
					res=API.pg.exec_params(phone_update,[infos['phone_number'],infos['carrier'],infos['is_cellphone'],infos['is_ported']])
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

			end

			get do
				# DO NOT DELETE used to test the api is live
				return {"api_version"=>"auth/v1"}
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
					elsif phone['user_key']!=user_key then # phone is already used by someone
						API.log.error "phone/lookup phone is already registered by another user"
						return {"error"=>"phone_already_used" }
					end
					answer={"tel"=>"#{phone_number}"}
					dial_code=phone['prefix']
					response = Authy::PhoneVerification.start(via: type, country_code: dial_code, phone_number: national)
					if response.ok? then
						answer["verif_sent"]="yes"
						update_phone({'phone_number'=>phone_number,'carrier'=>response.carrier,'is_cellphone'=>response.is_cellphone,'is_ported'=>response.is_ported})
					end
					API.log.error "phone/lookup phone verification did not start: #{citoyen['email']} / #{phone}" unless response.ok?
				rescue Twilio::REST::RequestError=>e
					status 404
					API.log.error "phone/lookup Twilio error: #{e.message}"
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
						API.log.error "phone/verif wrong code #{code} for #{citoyen['email']}"
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

			get 'init/:user_key' do
			end

			post 'firstname/:user_key' do
			end

			post 'lastname/:user_key' do
				begin
					pg_connect()
					stats_candidates=<<END
SELECT count(case when c.verified then 1 else null end) as nb_candidates, count(c.candidate_id)-count(case when c.verified then 1 else null end) as nb_citizens
FROM candidates as c;
END
					res1=API.pg.exec(stats_candidates)
					nb_candidates=res1[0]['nb_candidates']
					nb_plebiscites=res1[0]['nb_citizens']
					stats_citizens="SELECT count(*) as nb_citizens from users;"
					res2=API.pg.exec(stats_citizens)
					nb_citizens=res2[0]['nb_citizens']
				rescue Error => e
					return {"error"=>e.message}
				ensure
					pg_close()
				end
				return {
					"nb_citizens"=>nb_citizens,
					"nb_candidates"=>nb_candidates,
					"nb_plebiscites"=>nb_plebiscites,
				}
			end
		end
	end
end
