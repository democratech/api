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
	class AuthV2 < Grape::API
		version ['v2']
		format :json

		get do
			# DO NOT DELETE used to test the api is live
			return {"api_version"=>"v2"}
		end

		resource :auth do
			helpers do
				def validate_email(email)
					return nil if email.nil?
					email=email.downcase.gsub(/\A\p{Space}*|\p{Space}*\z/, '')
					return nil if email.match(/\A[^@\s]+@([^@\s]+\.)+[^@\s]+\z/).nil?
					domain_lookup="SELECT domain FROM forbidden_domains WHERE domain=$1"
					res=API.pg.exec_params(domain_lookup,[email.split('@')[1]])
					return res.num_tuples.zero? ? email : nil
				end

				def get_citizen_by_email(email)
					user_email_lookup=<<END
SELECT c.telegram_id,c.firstname,c.lastname,c.email,c.reset_code,c.registered,c.country,c.user_key,c.validation_level,c.birthday,t.*,ci.zipcode,ci.name as city,ci.population,ci.departement
FROM users AS c 
LEFT JOIN cities AS ci ON (ci.city_id=c.city_id)
LEFT JOIN telephones AS t ON (t.international=c.telephone)
WHERE c.email=$1
END
					res=API.pg.exec_params(user_email_lookup,[email])
					return res.num_tuples.zero? ? nil : res[0]
				end

				def update_country(country,user_key)
					country_save="UPDATE users as u SET country=$1 FROM countries as c WHERE u.user_key=$2 AND c.name=$1 RETURNING c.name,c.dial_code,u.email"
					res=API.pg.exec_params(country_save,[country,user_key])
					return res.num_tuples.zero? ? nil : res[0]
				end

				def update_city(city,user_key,france=true,num_circonscription=nil,num_commune=nil,code_departement=nil)
					if france then
						city_save="UPDATE users as u SET city=$1, city_id=c.city_id FROM circos as c INNER JOIN cities as ci ON (ci.city_id=c.city_id) WHERE u.user_key=$2 AND c.num_circonscription=$3 AND c.num_commune=$4 AND c.departement=$5 RETURNING u.email, u.city, ci.zipcode, ci.departement"
						params=[city,user_key,num_circonscription,num_commune,code_departement]
					else
						city_save="UPDATE users as u SET city=$1 WHERE u.user_key=$2 RETURNING u.email, u.city, null as circonscription_id, null as zipcode, null as departement" 
						params=[city,user_key]
					end
					res=API.pg.exec_params(city_save,params)
					return res.num_tuples.zero? ? nil : res[0]
				end
			end

			get do
				return {"api_version"=>"auth/v2"} # DO NOT DELETE used to test the api is live
			end

			params do
				requires :email, allow_blank: false, regexp: /\A[^@\s]+@([^@\s]+\.)+[^@\s]+\z/
				optional :referer, type:String
				optional :candidate, type:String
			end
			post 'login' do
				errors=[]
				notifs=[]
				answer={"email_sent"=>false,"new_user"=>false}
				referer=params["referer"]
				candidate=params["candidate"]
				email_notification={
					'template'=>"laprimaire-org-login",
					'subject'=>"Votre lien d'accès à votre espace personnel"
				}
				begin
					pg_connect()
					email=validate_email(params['email'])
					raise "email rejected" if email.nil?
					citizen=get_citizen_by_email(email)
					answer['redirect_url']='https://laprimaire.org/citoyen/verif/'+CGI.escape(email)
					if citizen.nil? then #user does not yet exists
						new_user=<<END
INSERT INTO users (email,referer,user_key,referal_code,hash)
VALUES ($1::text,$2::text,md5(random()::text),substring(md5($1) from 1 for 8),encode(digest($1,'sha256'),'hex'))
RETURNING *
END
						res1=API.pg.exec_params(new_user,[email,referer])
						raise "user not registered" if res1.num_tuples.zero?
						citizen=res1[0]
						register_user_to_organization=<<END
INSERT INTO organizations_users (email,organization_id) VALUES ($1,1) RETURNING *
END
						hostname=request.host
						res2=API.pg.exec_params(register_user_to_organization,[email])
						raise "user not registered to organization" if res2.num_tuples.zero?
						answer['new_user']=true
						answer['redirect_url']+="?newcitizen=1"
						email_notification['template']='laprimaire-org-signup';
						email_notification['subject']='Bienvenue sur LaPrimaire.org !';
						info="Nouvel inscrit à LaPrimaire.org"
						API.log.info(info)
						API.newsletter.subscribe(email: email,'Registered': citizen['registered'], 'Validationlevel'=>citizen['validation_level'].to_s)
						notifs.push([
							info,
							"supporteurs",
							":memo:",
							"pg"
						])
					end
					email={
						'to'=>[email],
						'from'=>'LaPrimaire.org <contact@laprimaire.org>',
						'subject'=>email_notification['subject'],
						'txt'=>''
					}
					template={
						'name'=>email_notification['template'],
						'vars'=>{
							'*|SUBJECT|*'=>email_notification['subject'],
							'*|USER_KEY|*'=>citizen['user_key']
						}
					}
					result=API.mailer.send_email(email,template)
					raise "email could not be sent" if result.nil?
					answer['email_sent']=true
				rescue StandardError=>e
					status 403
					answer={"error"=>e.message}
					API.log.error "auth/login error #{e.message}"
				rescue PG::Error=>e
					status 500
					API.log.error "auth/login PG error #{e.message}"
				ensure
					pg_close()
				end
				slack_notifications(notifs)
				error!(errors.join("\n"),400) unless errors.empty?
				return answer
			end

			params do
				requires :key, allow_blank: false, type:String
				requires :country, allow_blank: false, type:String
			end
			post 'country' do
				begin
					pg_connect()
					country=update_country(params["country"],params["key"])
					API.newsletter.update_subscription(country['email'],'Country'=>country['name']) unless country.nil?
				rescue StandardError=>e
					API.log.error "auth/country error [#{params['country']}]: #{e.message}"
				rescue PG::Error=>e
					API.log.error "auth/country PG error [#{params['country']}]: #{e.message}"
				ensure
					pg_close()
				end
				return country
			end

			params do
				requires :key, allow_blank: false, type:String
				requires :city, allow_blank: false, type:String
				requires :france, allow_blank: false, type:Boolean
				optional :num_circonscription, type:Integer
				optional :num_commune, type:Integer
				optional :code_departement, type:String
			end
			post 'city' do
				begin
					pg_connect()
					city=update_city(params["city"],params["key"],params["france"],params["num_circonscription"],params["num_commune"],params["code_departement"])
					API.newsletter.update_subscription(city['email'],'City'=>city['city'], 'Zipcode'=> city['zipcode'],'Numdepartement'=>city["departement"]) unless city.nil? or city['zipcode'].nil?
				rescue StandardError=>e
					API.log.error "auth/city error [#{params['city']}]: #{e.message}"
				rescue PG::Error=>e
					API.log.error "auth/city PG error [#{params['city']}]: #{e.message}"
				ensure
					pg_close()
				end
				return city
			end
		end
	end
end
