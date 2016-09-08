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

				def fix_wufoo(url,remove_params=true)
					url.gsub!(':/','://') if url.match(/https?:\/\//).nil?
					url=url.split('?')[0] if remove_params
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
					phase=params["Field5"]
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
									{
										:name=>"SLUG",
										:content=>"doe"
									}
								]
							}
						]
					}
					get_candidate=<<END
SELECT c.candidate_id,c.name,c.slug,count(*) as nb_soutiens FROM candidates as c INNER JOIN supporters as s ON (s.candidate_id=c.candidate_id) WHERE s.candidate_id=$1 GROUP BY c.candidate_id,c.name,c.slug
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
					msg[:merge_vars][0][:vars][3][:content]=candidate["slug"]
					begin
						if phase=="1" then
							result=API.mandrill.messages.send_template("laprimaire-org-support-candidate",[],msg)
						else
							result=API.mandrill.messages.send_template("laprimaire-org-support-candidate-phase-2",[],msg)
						end
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
						:bio => strip_tags(params["Field20"]),
						:key => strip_tags(params["Field15"]),
						:email => strip_tags(params["Field18"])
					}
					update_candidate=<<END
UPDATE candidates SET birthday=$1 ,departement=$2, secteur=$3, job=$4, bio=$5 WHERE candidate_key=$6 RETURNING *
END
					res=API.pg.exec_params(update_candidate,[maj[:birthday],maj[:departement],maj[:secteur],maj[:job],maj[:bio],maj[:key]])
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
						:video => fix_wufoo(strip_tags(params["Field15"]),false),
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
					maj[:video]=maj[:video].gsub('watch?v=','embed/') unless maj[:video].nil?
					maj[:video]=maj[:video].gsub('youtu.be/','www.youtube.com/embed/') unless maj[:video].nil?
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

			delete 'article/:id' do
				begin
					pg_connect()
					candidate_id=params['cid']
					raise "key parameter missing" if candidate_id.nil? 
					delete_article=<<END
DELETE FROM articles WHERE article_id=$1 AND candidate_id=$2 RETURNING *
END
					res=API.pg.exec_params(delete_article,[params[:id],candidate_id])
					raise "article not created : candidate not found" if res.num_tuples.zero?
				rescue PG::Error=>e
					STDERR.puts "DB Exception raised : #{e.message}"
					status 400
				rescue StandardError =>e
					STDERR.puts "STD Exception raised : #{e.message}"
					status 400
				ensure
					pg_close()
				end
				return {}
			end

			post 'article' do
				error!('401 Unauthorized', 401) unless authorized
				begin
					pg_connect()
					date_published=params["Field113"][0..3]+"-"+params["Field113"][4..5]+"-"+params["Field113"][6..7]
					maj={
						:title => fix_wufoo(strip_tags(params["Field120"])),
						:summary => fix_wufoo(strip_tags(params["Field122"])),
						:source_url => fix_wufoo(strip_tags(params["Field112"])),
						:theme => fix_wufoo(strip_tags(params["Field1"])),
						:subtheme_planete => fix_wufoo(strip_tags(params["Field5"])),
						:subtheme_societe => fix_wufoo(strip_tags(params["Field4"])),
						:subtheme_economie => fix_wufoo(strip_tags(params["Field6"])),
						:subtheme_institutions => fix_wufoo(strip_tags(params["Field7"])),
						:date_published => date_published,
						:key => fix_wufoo(strip_tags(params["Field115"])),
						:email => fix_wufoo(strip_tags(params["Field118"]))
					}
					maj[:subtheme]=maj[:theme] if maj[:theme]=='Biographie'
					maj[:subtheme]=maj[:subtheme_planete] unless maj[:subtheme_planete].nil?
					maj[:subtheme]=maj[:subtheme_societe] unless maj[:subtheme_societe].nil?
					maj[:subtheme]=maj[:subtheme_economie] unless maj[:subtheme_economie].nil?
					maj[:subtheme]=maj[:subtheme_institutions] unless maj[:subtheme_institutions].nil?
					insert_article=<<END
INSERT INTO articles (title,summary,candidate_id,source_url,published_url,theme_id,date_published) SELECT $1,$2,c.candidate_id,$3,$3,t.theme_id,$4 FROM (SELECT ca.candidate_id FROM candidates as ca WHERE ca.candidate_key=$6) as c, (SELECT theme_id FROM articles_themes WHERE name=$5) as t RETURNING *
END
					res=API.pg.exec_params(insert_article,[maj[:title],maj[:summary],maj[:source_url],maj[:date_published],maj[:subtheme],maj[:key]])
					raise "article not created : candidate not found" if res.num_tuples.zero?
				rescue PG::Error=>e
					STDERR.puts "Exception raised : #{e.message}\n#{params.inspect}"
					status 400
				rescue StandardError =>e
					STDERR.puts "STD Exception raised : #{e.message}\n#{params.inspect}"
					status 400
				ensure
					pg_close()
				end
			end
		end
	end
end
