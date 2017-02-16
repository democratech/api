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
					puts email
					return nil if email.nil?
					puts email+'A'
					email=email.downcase.gsub(/\A\p{Space}*|\p{Space}*\z/, '')
					puts email+'B'
					return nil if email.match(/\A[^@\s]+@([^@\s]+\.)+[^@\s]+\z/).nil?
					puts email+'C'
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
					if citizen.nil? then #user does not yet exists
						new_user=<<END
INSERT INTO users (email,referer,user_key,referal_code,organization_id,hash)
SELECT $1::text,$2::text,md5(random()::text),substring(md5($1) from 1 for 8),e.organization_id,encode(digest($1,'sha256'),'hex')
FROM (SELECT distinct organization_id FROM elections WHERE hostname=$3) as e
RETURNING *;
END
						hostname=request.host
						hostname='legislatives.laprimaire.org' if ::DEBUG
						res1=API.pg.exec_params(new_user,[email,referer,hostname])
						raise "user not registered" if res1.num_tuples.zero?
						answer['new_user']=true
						email_notification['template']='laprimaire-org-signup';
						email_notification['subject']='Bienvenue sur LaPrimaire.org !';
						citizen=res1[0]
						info="Nouvel inscrit à LaPrimaire.org"
						API.log.info(info)
						notifs.push([
							info,
							"supporteurs",
							":memo:",
							"pg"
						])
					end
					answer['user_key']=citizen['user_key']
					message= {
						:to=>[{ :email=> email }],
						:subject=> email_notification['subject'],
						:merge_vars=>[{
							:rcpt=>email,
							:vars=>[{
								:name=>"USER_KEY",
								:content=>citizen['user_key']
							}]
						}]
					}
					result=API.mandrill.messages.send_template(email_notification['template'],[],message)
					answer['email_sent']=true
				rescue StandardError=>e
					status 403
					answer={"error"=>e.message}
					API.log.error "email/verif error #{e.message}"
				rescue PG::Error=>e
					status 500
					API.log.error "email/verif PG error #{e.message}"
				rescue Mandrill::Error => e
					msg="A mandrill error occurred: #{e.class} - #{e.message}"
					API.log.error(msg)
				ensure
					pg_close()
				end
				slack_notifications(notifs)
				error!(errors.join("\n"),400) unless errors.empty?
				return answer
			end
		end
	end
end
