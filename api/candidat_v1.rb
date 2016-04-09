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
	class CandidatV1 < Grape::API
		version ['v1','v2']
		format :json

		get do
			# DO NOT DELETE used to test the api is live
			return {"api_version"=>"v1"}
		end

		resource :candidat do
			helpers do
				def authorized
					params['HandshakeKey']==WUFHS
				end
			end

			get do
				# DO NOT DELETE used to test the api is live
				return {"api_version"=>"candidat/v1"}
			end

			post 'share' do
				error!('401 Unauthorized', 401) unless authorized
				email=params["Field1"]
				candidate_id=params["Field3"]
				return if email.match(/\A[^@\s]+@([^@\s]+\.)+[^@\s]+\z/).nil?
				notifs=[]
				email=email.downcase
				message= {  
					:from_name=> "LaPrimaire.org",  
					:subject=> "Pour un vrai choix de candidats en 2017  !",  
					:to=>[  
						{  
							:email=> "email_dest",
						}  
					],
					:merge_vars=>[
						{
							:vars=>[
								{
									:name=>"CANDIDATE",
									:content=>"john"
								},
								{
									:name=>"CANDIDATE_ID",
									:content=>"doe"
								},
								{
									:name=>"NB_SOUTIENS",
									:content=>"doe"
								},
							]
						}
					]
				}
				get_candidate="SELECT c.candidate_id,c.name, count(*) as nb_soutiens FROM candidates as c INNER JOIN supporters as s ON (s.candidate_id=c.candidate_id) WHERE s.candidate_id=$1 GROUP BY c.candidate_id,c.name"
				res=API.pg.exec_params(get_candidate,[candidate_id])
				if not res.num_tuples.zero? then
					candidate=res[0]
					email={
						"TO"=>email,
						"CANDIDATE"=>candidate['name'],
						"CANDIDATE_ID"=>candidate_id,
						"NB_SOUTIENS"=>candidate['nb_soutiens']
					}
					msg=message
					msg[:subject]="Soutenez la candidature citoyenne de #{candidate['name']} sur LaPrimaire.org"
					msg[:to][0][:email]=email
					msg[:merge_vars][0][:rcpt]=email
					msg[:merge_vars][0][:vars][0][:content]=candidate["name"]
					msg[:merge_vars][0][:vars][1][:content]=candidate["candidate_id"]
					msg[:merge_vars][0][:vars][2][:content]=candidate["nb_soutiens"]
					begin
						result=API.mandrill.messages.send_template("laprimaire-org-support-candidate",[],msg)
						notifs.push([
							"Nouveau email de support pour #{candidate['name']} demandé !",
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
end
