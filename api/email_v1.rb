# encoding: utf-8

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

			get 'share' do
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
