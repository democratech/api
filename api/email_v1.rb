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
	class EmailV1 < Grape::API
		prefix 'api'
		version ['v1','v2']
		format :json

		get do
			# DO NOT DELETE used to test the api is live
			return {"api_version"=>"v1"}
		end

		resource :email do
			helpers do
				def authorized
					params['HandshakeKey']==WUFHS
				end
			end

			get do
				# DO NOT DELETE used to test the api is live
				return {"api_version"=>"email/v1"}
			end

			post 'share' do
				error!('401 Unauthorized', 401) unless authorized
				email=params["Field1"]
				return if email.match(/\A[^@\s]+@([^@\s]+\.)+[^@\s]+\z/).nil?
				notifs=[]
				email=email.downcase
				message= {  
					:subject=> "LaPrimaire.org, pour un VRAI choix de candidats en 2017 !",  
					:from_name=> "LaPrimaire.org",  
					:text=>"",  
					:to=>[  
						{  
							:email=> email
						}  
					],  
					:from_email=>"hello@democratech.co"
				}
				begin
					result=API.mandrill.messages.send_template("laprimaire-org-share-email",[],message)
					notifs.push([
						"Nouveau partage email demandé !",
						"social_media",
						":email:",
						"wufoo"
					])
				rescue Mandrill::Error => e
					msg="A mandrill error occurred: #{e.class} - #{e.message}"
					notifs.push([
						"Erreur lors de l'envoi d'un email : %s" % [msg],
						"errors",
						":see_no_evil:",
						"wufoo"
					])
				end
				slack_notifications(notifs) if not notifs.empty?
			end
		end
	end
end
