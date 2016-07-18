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
	class AppV1 < Grape::API
		version ['v1','v2']
		format :json

		get do
			# DO NOT DELETE used to test the api is live
			return {"api_version"=>"v1"}
		end

		resource :app do
			helpers do
				def authorized
					params['HandshakeKey']==WUFHS
				end
			end

			get do
				# DO NOT DELETE used to test the api is live
				return {"api_version"=>"app/v1"}
			end

			get 'stats' do
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

			get 'maires' do
				begin
					pg_connect()
					stats_maires="SELECT count(*) as nb_signatures FROM appel_aux_maires"
					res1=API.pg.exec(stats_maires)
					nb_signatures=res1[0]['nb_signatures']
				rescue Error => e
					return {"error"=>e.message}
				ensure
					pg_close()
				end
				return {
					"nb_maires"=>0,
					"nb_signatures"=>nb_signatures
				}
			end

			post 'maires' do
				error!('401 Unauthorized', 401) unless authorized
				errors=[]
				notifs=[]

				# 1. We read the new supporter info from the parameters
				doc={}
				doc[:firstname]=params["Field9"].capitalize.strip unless params["Field9"].nil?
				doc[:lastname]=params["Field10"].upcase.strip unless params["Field10"].nil?
				doc[:email]=params["Field1"].downcase.strip unless params["Field1"].nil?
				doc[:comment]=params["Field119"] unless params["Field119"].nil?
				new_signature="INSERT INTO appel_aux_maires (firstname,lastname,email,comment) VALUES ($1,$2,$3,$4) RETURNING *;"
				begin
					pg_connect()
					res=API.pg.exec_params(new_signature,[doc[:firstname],doc[:lastname],doc[:email],doc[:comment]])
					if not res.num_tuples.zero? then
						notifs.push([
							"Nouvelle signature pour l'appel aux maires ! %s %s : %s" % [doc[:firstname],doc[:lastname],doc[:comment]],
							"supporteurs",
							":memo:",
							"pg"
						])
						get_user_by_email=<<END
SELECT z.*,c.slug,c.zipcode,c.departement,c.lat_deg,c.lon_deg FROM users AS z LEFT JOIN cities AS c ON (c.city_id=z.city_id) WHERE z.email=$1
END
						res1=API.pg.exec_params(get_user_by_email,[doc[:email]])
						if res1.num_tuples.zero? then # meta user does not yet exists
							insert_meta_user_from_signature=<<END
insert into users (email,firstname,lastname,registered,tags,user_key) select a.email,a.firstname,a.lastname,a.signed as registered,ARRAY['appel_aux_maires']::text[] as tags, md5(random()::text) as user_key from appel_aux_maires as a where a.email=$1 returning *;
END
							res2=API.pg.exec_params(insert_meta_user_from_signature,[doc[:email]])
						else # meta user already exists
							update_meta_user_from_signature=<<END
update users set last_updated=now(),tags=array_append(tags,'appel_aux_maires') where users.email=$1 returning *;
END
							res2=API.pg.exec_params(update_meta_user_from_signature,[doc[:email]])
						end
					else # if the supporter could not be insert in the db
						notifs.push([
							"Erreur lors de l'enregistrement d'une signature pour l'appel aux maires: %s (%s, %s) : %s\nError trace: %s" % [doc[:email],doc[:firstname],doc[:lastname],doc[:comment],res.inspect],
							"errors",
							":scream:",
							"pg"
						])
						errors.push('400 Supporter could not be registered')
					end
				rescue Exception => e
					notifs.push([
						"Erreur lors de l'enregistrement d'une signature pour l'appel aux maires: %s (%s, %s) : %s\nError message: %s\nError trace: %s" % [doc[:email],doc[:firstname],doc[:lastname],doc[:comment],e.message,res.inspect],
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
					result=API.mandrill.messages.send_template("laprimaire-org-appel-aux-maires-merci",[],message)
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

			get 'candidates' do
				begin
					pg_connect()
					stats_candidates="SELECT count(*) as nb_signatures FROM toutes_candidates"
					res1=API.pg.exec(stats_candidates)
					nb_signatures=res1[0]['nb_signatures']
				rescue Error => e
					return {"error"=>e.message}
				ensure
					pg_close()
				end
				return {
					"nb_signatures"=>nb_signatures
				}
			end

			post 'candidates' do
				error!('401 Unauthorized', 401) unless authorized
				errors=[]
				notifs=[]

				# 1. We read the new supporter info from the parameters
				doc={}
				doc[:firstname]=params["Field9"].capitalize.strip unless params["Field9"].nil?
				doc[:lastname]=params["Field10"].upcase.strip unless params["Field10"].nil?
				doc[:email]=params["Field1"].downcase.strip unless params["Field1"].nil?
				doc[:comment]=params["Field119"] unless params["Field119"].nil?
				new_signature="INSERT INTO toutes_candidates (firstname,lastname,email,comment) VALUES ($1,$2,$3,$4) RETURNING *;"
				begin
					pg_connect()
					res=API.pg.exec_params(new_signature,[doc[:firstname],doc[:lastname],doc[:email],doc[:comment]])
					if not res.num_tuples.zero? then
						notifs.push([
							"Nouvelle signature #ToutesCandidates ! %s %s : %s" % [doc[:firstname],doc[:lastname],doc[:comment]],
							"supporteurs",
							":memo:",
							"pg"
						])
						get_user_by_email=<<END
SELECT z.*,c.slug,c.zipcode,c.departement,c.lat_deg,c.lon_deg FROM users AS z LEFT JOIN cities AS c ON (c.city_id=z.city_id) WHERE z.email=$1
END
						res1=API.pg.exec_params(get_user_by_email,[doc[:email]])
						if res1.num_tuples.zero? then # meta user does not yet exists
							insert_meta_user_from_signature=<<END
insert into users (email,firstname,lastname,registered,tags,user_key) select a.email,a.firstname,a.lastname,a.signed as registered,ARRAY['toutes_candidates']::text[] as tags, md5(random()::text) as user_key from toutes_candidates as a where a.email=$1 returning *;
END
							res2=API.pg.exec_params(insert_meta_user_from_signature,[doc[:email]])
						else # meta user already exists
							update_meta_user_from_signature=<<END
update users set last_updated=now(),tags=array_append(tags,'toutes_candidates') where users.email=$1 returning *;
END
							res2=API.pg.exec_params(update_meta_user_from_signature,[doc[:email]])
						end
					else # if the supporter could not be insert in the db
						notifs.push([
							"Erreur lors de l'enregistrement d'une signature pour #ToutesCandidates: %s (%s, %s) : %s\nError trace: %s" % [doc[:email],doc[:firstname],doc[:lastname],doc[:comment],res.inspect],
							"errors",
							":scream:",
							"pg"
						])
						errors.push('400 Supporter could not be registered')
					end
				rescue
					notifs.push([
						"Erreur lors de l'enregistrement d'une signature pour #ToutesCandidates: %s (%s, %s) : %s\nError trace: %s" % [doc[:email],doc[:firstname],doc[:lastname],doc[:comment],res.inspect],
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
					result=API.mandrill.messages.send_template("laprimaire-org-appel-aux-femmes-merci",[],message)
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

			post 'citoyen' do
				error!('401 Unauthorized', 401) unless authorized
				errors=[]
				notifs=[]

				# 1. We read the new supporter info from the parameters
				doc={}
				doc[:firstname]=params["Field9"].capitalize.strip unless params["Field9"].nil?
				doc[:lastname]=params["Field10"].upcase.strip unless params["Field10"].nil?
				doc[:email]=params["Field1"].downcase.gsub(/\A\p{Space}*|\p{Space}*\z/, '') unless params["Field1"].nil?
				new_signature="INSERT INTO nous_president (firstname,lastname,email) VALUES ($1,$2,$3) RETURNING *;"
				begin
					pg_connect()
					res=API.pg.exec_params(new_signature,[doc[:firstname],doc[:lastname],doc[:email]])
					if not res.num_tuples.zero? then
						notifs.push([
							"Nouvel inscrit suite à la campagne #NousPresident  ! %s %s : %s" % [doc[:firstname],doc[:lastname]],
							"supporteurs",
							":memo:",
							"pg"
						])
						get_user_by_email=<<END
SELECT z.*,c.slug,c.zipcode,c.departement,c.lat_deg,c.lon_deg FROM users AS z LEFT JOIN cities AS c ON (c.city_id=z.city_id) WHERE z.email=$1
END
						res1=API.pg.exec_params(get_user_by_email,[doc[:email]])
						if res1.num_tuples.zero? then # meta user does not yet exists
							insert_meta_user_from_signature=<<END
insert into users (email,firstname,lastname,registered,tags,user_key) select a.email,a.firstname,a.lastname,a.signed as registered,ARRAY['nous_president']::text[] as tags, md5(random()::text) as user_key from nous_president as a where a.email=$1 returning *;
END
							res2=API.pg.exec_params(insert_meta_user_from_signature,[doc[:email]])
						else # meta user already exists
							update_meta_user_from_signature=<<END
update users set last_updated=now(),tags=array_append(tags,'nous_president') where users.email=$1 returning *;
END
							res2=API.pg.exec_params(update_meta_user_from_signature,[doc[:email]])
						end
					else # if the supporter could not be insert in the db
						notifs.push([
							"Erreur lors de l'enregistrement d'une signature pour la campagne #NousPresident: %s (%s, %s) : %s\nError trace: %s" % [doc[:email],doc[:firstname],doc[:lastname],res.inspect],
							"errors",
							":scream:",
							"pg"
						])
						errors.push('400 Supporter could not be registered')
					end
				rescue PG::Error => e
					notifs.push([
						"Erreur lors de l'enregistrement d'une signature pour la campagne #NousPresident: %s (%s, %s) : %s\nError message: %s\nError trace: %s" % [doc[:email],doc[:firstname],doc[:lastname],e.message,res.inspect],
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
