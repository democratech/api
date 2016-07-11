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
				return {"api_version"=>"candidat/v1"}
			end

			post 'share' do
				error!('401 Unauthorized', 401) unless authorized
				begin
					pg_connect()
					email=params["Field1"]
					candidate_id=params["Field3"]
					return if email.match(/\A[^@\s]+@([^@\s]+\.)+[^@\s]+\z/).nil?
					notifs=[]
					email=email.downcase
					message= {
						:from_name=> "LaPrimaire.org",
						:subject=> "Pour un vrai choix de candidats en 2017  !",
						:to=>[{ :email=> "email_dest" }],
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
					get_candidate=<<END
SELECT c.candidate_id,c.name, count(*) as nb_soutiens FROM candidates as c INNER JOIN supporters as s ON (s.candidate_id=c.candidate_id) WHERE s.candidate_id=$1 GROUP BY c.candidate_id,c.name
END
					res=API.pg.exec_params(get_candidate,[candidate_id])
				rescue PG::Error=>e
					res=nil
				ensure
					pg_close()
				end
				if not res.nil? and not res.num_tuples.zero? then
					candidate=res[0]
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

			post 'about' do
				error!('401 Unauthorized', 401) unless authorized
				begin
					pg_connect()
					birthday=params["Field8"][0..3]+"-"+params["Field8"][4..5]+"-"+params["Field8"][6..7]
					maj={
						:birthday => strip_tags(birthday), #YYYY-MM-DD
						:departement => strip_tags(params["Field9"]),
						:secteur => strip_tags(params["Field12"]),
						:job => strip_tags(params["Field17"]),
						:key => strip_tags(params["Field15"]),
						:email => strip_tags(params["Field18"])
					}
					update_candidate=<<END
UPDATE candidates SET birthday=$1 ,departement=$2, secteur=$3, job=$4 WHERE candidate_key=$5 RETURNING *
END
					res=API.pg.exec_params(update_candidate,[maj[:birthday],maj[:departement],maj[:secteur],maj[:job],maj[:key]])
					STDERR.puts "candidate info not updated : candidate not found" if res.num_tuples.zero?
				rescue PG::Error=>e
					STDERR.puts "Exception raised : #{e.message}"
					res=nil
				ensure
					pg_close()
				end
			end

			post 'summary' do
				error!('401 Unauthorized', 401) unless authorized
				begin
					pg_connect()
					maj={
						:vision => strip_tags(params["Field1"]),
						:prio1 => strip_tags(params["Field3"]),
						:prio2 => strip_tags(params["Field2"]),
						:prio3 => strip_tags(params["Field4"]),
						:key => strip_tags(params["Field6"]),
						:email => strip_tags(params["Field7"])
					}
					update_candidate=<<END
UPDATE candidates SET vision=$1 ,prio1=$2, prio2=$3, prio3=$4 WHERE candidate_key=$5 RETURNING *
END
					res=API.pg.exec_params(update_candidate,[maj[:vision],maj[:prio1],maj[:prio2],maj[:prio3],maj[:key]])
					STDERR.puts "candidate summary not updated : candidate not found" if res.num_tuples.zero?
				rescue PG::Error=>e
					STDERR.puts "Exception raised : #{e.message}"
					res=nil
				ensure
					pg_close()
				end
			end

			post 'links' do
				error!('401 Unauthorized', 401) unless authorized
				begin
					pg_connect()
					maj={
						:trello => fix_wufoo(strip_tags(params["Field8"])),
						:website => fix_wufoo(strip_tags(params["Field1"])),
						:video => fix_wufoo(strip_tags(params["Field15"])),
						:facebook => fix_wufoo(strip_tags(params["Field2"])),
						:twitter => fix_wufoo(strip_tags(params["Field3"])),
						:linkedin => fix_wufoo(strip_tags(params["Field4"])),
						:blog => fix_wufoo(strip_tags(params["Field5"])),
						:youtube => fix_wufoo(strip_tags(params["Field13"])),
						:instagram => fix_wufoo(strip_tags(params["Field6"])),
						:wikipedia => fix_wufoo(strip_tags(params["Field7"])),
						:key => fix_wufoo(strip_tags(params["Field9"])),
						:email => fix_wufoo(strip_tags(params["Field11"]))
					}
					update_candidate=<<END
UPDATE candidates SET trello=$1 ,website=$2, facebook=$3, twitter=$4, linkedin=$5, blog=$6, instagram=$7, wikipedia=$8, youtube=$9, video=$10 WHERE candidate_key=$11 RETURNING *
END
					res=API.pg.exec_params(update_candidate,[maj[:trello],maj[:website],maj[:facebook],maj[:twitter],maj[:linkedin],maj[:blog],maj[:instagram],maj[:wikipedia],maj[:youtube],maj[:video],maj[:key]])
					STDERR.puts "candidate links not updated : candidate not found" if res.num_tuples.zero?
				rescue PG::Error=>e
					STDERR.puts "Exception raised : #{e.message}"
					res=nil
				ensure
					pg_close()
				end
			end

			post 'photo' do
				error!('401 Unauthorized', 401) unless authorized
				begin
					pg_connect()
					maj={
						:key => strip_tags(params["Field3"]),
						:email => strip_tags(params["Field4"]),
						:photo_key => strip_tags(params["Field1"]),
						:photo_url => strip_tags(params["Field1-url"])
					}
					get_candidate=<<END
SELECT c.candidate_id,c.candidate_key,c.name,c.photo FROM candidates as c WHERE c.candidate_key=$1
END
					res=API.pg.exec_params(get_candidate,[maj[:key]])
					raise "candidate photo not updated: candidate not found" if res.num_tuples.zero?
					candidate=res[0]
					photo=candidate['photo']
					if photo.nil? or photo.empty? then
						photo="#{candidate['candidate_id']}.jpeg"
						update_candidate=<<END
UPDATE candidates SET photo=$1 WHERE candidate_key=$2 RETURNING *
END
						res1=API.pg.exec_params(update_candidate,[photo,maj[:key]])
						raise "candidate photo field not updated: candidate not found" if res1.num_tuples.zero?
					end
					upload_img=MiniMagick::Image.open(maj[:photo_url])
					upload_img.resize "x300"
					photo_path="/tmp/#{photo}"
					upload_img.write(photo_path)
					upload_image(photo_path)
				rescue PG::Error=>e
					STDERR.puts "Exception raised : #{e.message}"
					res=nil
				ensure
					pg_close()
				end
			end
		end
	end
end
