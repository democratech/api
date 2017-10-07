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
	class WufooV3 < Grape::API
		version ['v3']
		format :json

		get do
			# DO NOT DELETE used to test the api is live
			return {"api_version"=>"v3"}
		end

		resource :wufoo do
			helpers do
				def authorized
					params['HandshakeKey']==WUFHS
				end

				def add_to_mailing_list(doc)
					merge_fields={}
					merge_fields['FNAME']=doc[:firstName] unless doc[:firstName].nil?
					merge_fields['LNAME']=doc[:lastName] unless doc[:lastName].nil?
					merge_fields['CITY']=doc[:city] unless doc[:city].nil?
					merge_fields['ZIPCODE']=doc[:postalCode] unless doc[:postalCode].nil?
					merge_fields['COUNTRY']=doc[:country] unless doc[:country].nil?
					uri = URI.parse(MCURL)
					http = Net::HTTP.new(uri.host, uri.port)
					http.use_ssl = true
					http.verify_mode = OpenSSL::SSL::VERIFY_NONE
					request = Net::HTTP::Post.new("/3.0/lists/"+MCLIST+"/members/")
					request.basic_auth 'hello',MCKEY
					request.add_field('Content-Type', 'application/json')
					request.body = JSON.dump({
						'email_address'=>doc[:email],
						'status'=>'subscribed',
						'merge_fields'=>merge_fields
					})
					res=http.request(request)
					return res.kind_of?(Net::HTTPSuccess),res
				end

				def fix_wufoo(url)
					return url if url.nil?
					url.gsub!(':/','://') if url.match(/https?:\/\//).nil?
					return url
				end

				def strip_tags(text)
					return text if text.nil?
					return text.gsub(/<\/?[^>]*>/, "")
				end

				def upload_image(filename)
					bucket=API.aws.bucket(AWS_BUCKET)
					key=File.basename(filename)
					obj=bucket.object("candidats_legislatives/"+key)
					if bucket.object(key).exists? then
						STDERR.puts "#{key} already exists in S3 bucket. deleting previous object."
						obj.delete
					end
					content_type=MimeMagic.by_magic(File.open(filename)).type
					obj.upload_file(filename, acl:'public-read',cache_control:'public, max-age=14400', content_type:content_type)
					return key
				end
			end

			get do
				# DO NOT DELETE used to test the api is live
				return {"api_version"=>"wufoo/v2"}
			end

			post 'preinscription' do
				error!('401 Unauthorized', 401) unless authorized
				errors=[]
				begin
					pg_connect()
					# 1. Enregistrement du candidat
					uuid=((rand()*1000000000000).to_i).to_s
					profile_pic=nil
					if not params["Field44"].nil? and not params["Field44"].empty? then
						profile_pic="#{uuid}"+File.extname(params["Field44"])
						photo=profile_pic
						upload_img=MiniMagick::Image.open(params["Field44-url"])
						upload_img.resize "x300"
						photo_path="/tmp/#{photo}"
						upload_img.write(photo_path)
						upload_image(photo_path)
					end
					maj={
						:candidate_id => uuid,
						:name => fix_wufoo(strip_tags(params["Field3"]+' '+params["Field4"])),
						:gender => params["Field32"]=="Un homme" ? "M" : "F",
						:country => fix_wufoo(strip_tags(UnicodeUtils.upcase(params["Field271"]))),
						:zipcode => fix_wufoo(strip_tags(params["Field270"].gsub(/\s+/,""))),
						:address1 => fix_wufoo(strip_tags(params["Field266"])),
						:address2 => fix_wufoo(strip_tags(params["Field267"])),
						:city => fix_wufoo(strip_tags(UnicodeUtils.upcase(params["Field268"]))),
						:birthday => params["Field272"],
						:birthplace => fix_wufoo(strip_tags(UnicodeUtils.upcase(params["Field273"]))),
						:region=>fix_wufoo(strip_tags(params["Field279"])),
						:suppleant_name=>params["Field258"]=="Oui" ? fix_wufoo(strip_tags(params["Field259"])) : "Aucun",
						:suppleant_email=>params["Field258"]=="Oui" ? fix_wufoo(strip_tags(params["Field260"])) : "Aucun",
						:candidat=>fix_wufoo(strip_tags(params["Field261"])),
						:organization=>fix_wufoo(strip_tags(params["Field25"])),
						:email => fix_wufoo(strip_tags(params["Field12"])),
						:job => fix_wufoo(strip_tags(params["Field252"])),
						:tel => fix_wufoo(strip_tags(params["Field11"])),
						:program_theme => params["Field22"]=="Un programme complet" ? "global" : fix_wufoo(strip_tags(params["Field249"])),
						:political_party => params["Field24"]=="Oui" ? fix_wufoo(strip_tags(params["Field25"].upcase)) : "NON",
						:already_candidate => params["Field26"].match(/Non/).nil? ? fix_wufoo(strip_tags(params["Field35"].upcase)) : "NON",
						:already_elected => params["Field34"]=="Oui" ? fix_wufoo(strip_tags(params["Field36"].upcase)) : "NON",
						:website => fix_wufoo(strip_tags(params["Field13"])),
						:twitter => fix_wufoo(strip_tags(params["Field15"])),
						:facebook => fix_wufoo(strip_tags(params["Field14"])),
						:photo_key => '/laprimaire/candidats_legislatives/'+profile_pic,
						:election_id=>params["Field277"].to_i
					}
					if not params["Field280"].nil? and not params["Field280"].empty? then
						maj[:circonscription]=fix_wufoo(strip_tags(params["Field280"]))
					elsif not params["Field282"].nil? and not params["Field282"].empty? then
						maj[:circonscription]=fix_wufoo(strip_tags(params["Field282"]))
					elsif not params["Field283"].nil? and not params["Field283"].empty? then
						maj[:circonscription]=fix_wufoo(strip_tags(params["Field283"]))
					elsif not params["Field284"].nil? and not params["Field284"].empty? then
						maj[:circonscription]=fix_wufoo(strip_tags(params["Field284"]))
					elsif not params["Field286"].nil? and not params["Field286"].empty? then
						maj[:circonscription]=fix_wufoo(strip_tags(params["Field286"]))
					elsif not params["Field287"].nil? and not params["Field287"].empty? then
						maj[:circonscription]=fix_wufoo(strip_tags(params["Field287"]))
					elsif not params["Field288"].nil? and not params["Field288"].empty? then
						maj[:circonscription]=fix_wufoo(strip_tags(params["Field288"]))
					elsif not params["Field289"].nil? and not params["Field289"].empty? then
						maj[:circonscription]=fix_wufoo(strip_tags(params["Field289"]))
					elsif not params["Field290"].nil? and not params["Field290"].empty? then
						maj[:circonscription]=fix_wufoo(strip_tags(params["Field290"]))
					elsif not params["Field291"].nil? and not params["Field291"].empty? then
						maj[:circonscription]=fix_wufoo(strip_tags(params["Field291"]))
					elsif not params["Field293"].nil? and not params["Field293"].empty? then
						maj[:circonscription]=fix_wufoo(strip_tags(params["Field293"]))
					elsif not params["Field294"].nil? and not params["Field294"].empty? then
						maj[:circonscription]=fix_wufoo(strip_tags(params["Field294"]))
					elsif not params["Field295"].nil? and not params["Field295"].empty? then
						maj[:circonscription]=fix_wufoo(strip_tags(params["Field295"]))
					elsif not params["Field396"].nil? and not params["Field396"].empty? then
						maj[:circonscription]=fix_wufoo(strip_tags(params["Field396"]))
					elsif not params["Field397"].nil? and not params["Field397"].empty? then
						maj[:circonscription]=fix_wufoo(strip_tags(params["Field397"]))
					end
					insert_candidate=<<END
INSERT INTO candidates (candidate_id,name,gender,country,zipcode,address1,address2,city,birthday,birthplace,email,job,tel,program_theme,political_party,already_candidate,already_elected,website,twitter,facebook,photo,candidate_key) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$20,$21,md5(random()::text)) RETURNING *
END
					res=API.pg.exec_params(insert_candidate,[
						maj[:candidate_id],
						maj[:name],
						maj[:gender],
						maj[:country],
						maj[:zipcode],
						maj[:address1],
						maj[:address2],
						maj[:city],
						maj[:birthday],
						maj[:birthplace],
						maj[:email],
						maj[:job],
						maj[:tel],
						maj[:program_theme],
						maj[:political_party],
						maj[:already_candidate],
						maj[:already_elected],
						maj[:website],
						maj[:twitter],
						maj[:facebook],
						maj[:photo_key]
					])
					raise "candidate could not be created" if res.num_tuples.zero?
					candidate_key=res[0]['candidate_key']
					candidate_id=res[0]['candidate_id']
					find_circo="SELECT * FROM circonscriptions as c WHERE c.name_circonscription=$1"
					res=API.pg.exec_params(find_circo,[maj[:circonscription]])
					raise "circonscription could not be found" if res.num_tuples.zero?
					circonscription_id=res[0]['id'].to_i
					insert_candidate_election=<<END
INSERT INTO candidates_elections (candidate_id,election_id,fields) values ($1,$2,$3) RETURNING *
END
					jsonfields={
						'circonscription'=>maj[:circonscription],
						'circonscription_id'=>circonscription_id,
						'suppleant_name'=>maj[:suppleant_name],
						'suppleant_email'=>maj[:suppleant_email],
						'candidate'=>maj[:candidat],
						'organization'=>maj[:organization]
					}
					res=API.pg.exec_params(insert_candidate_election,[
						maj[:candidate_id],
						maj[:election_id],
						jsonfields.to_json
					])
					raise "candidate could not be created (step 2)" if res.num_tuples.zero?

				rescue Exception=>e
					STDERR.puts "Exception raised : #{e.message}"
					res=nil
				ensure
					pg_close()
				end
				# 2. Email notification to the candidate with its admin page and instructions
				begin
					email={
						'to'=>["#{maj[:name]} <#{maj[:email]}>"],
						'from'=>'LaPrimaire.org <contact@laprimaire.org>',
						'subject'=>"Bienvenue !",
						'txt'=>''
					}
					template={
						'name'=>"legislatives-candidats-bienvenue",
						'vars'=>{
							"*|CANDIDATE_KEY|*"=>"#{candidate_key}"
						}
					}
					result=API.mailer.send_email(email,template)
					raise "email could not be sent" if result.nil?
				rescue StandardError=>e
					API.log.error "wufoo/preinscription error #{e.message}"
				end

				# 2. Slack notification
				doc={}
				doc[:firstName]=params["Field3"].capitalize unless params["Field3"].nil?
				doc[:lastName]=params["Field4"].upcase unless params["Field4"].nil?
				doc[:email]=params["Field12"].downcase unless params["Field12"].nil?
				doc[:zip]=params["Field38"]
				doc[:pays]=maj[:country]
				doc[:tel]=params["Field11"]
				doc[:programme]=(params["Field22"].match(/complet/) ? params["Field22"]:params["Field249"]) unless params["Field22"].nil?
				doc[:parti]=(params["Field24"]=="Oui" ? params["Field25"]:params["Field24"])
				doc[:candidat]=(params["Field26"].match(/^Oui/) ? params["Field35"]:params["Field26"]) unless params["Field26"].nil?
				doc[:mandat]=(params["Field34"].match(/^Oui/) ? params["Field36"]:params["Field34"]) unless params["Field34"].nil?
				doc[:siteweb]=params["Field13"]
				doc[:twitter]=params["Field15"]
				doc[:facebook]=params["Field14"]
				doc[:other]=params["Field21"]
				doc[:summary]=params["Field30"]
				doc[:photo_img]=params["Field44"] unless params["Field44"].nil?
				doc[:photo_url]=params["Field44-url"] unless params["Field44"].nil?
				doc[:comment]=params["Field27"]
				attachment=nil
				if doc[:photo_img] then
					attachment={
						"fallback"=>"Photo de %s %s" % [doc[:firstName],doc[:lastName]],
						"color"=>"#527bdd",
						"title"=>doc[:photo_img],
						"title_link"=>doc[:photo_url],
						"image_url"=>doc[:photo_url]
					}
				end
				message=<<END
Nouveau candidat pré-inscrit !
Nom: %s %s
Circonscription: %s
Candidat supporté: %s
Suppleant: %s (%s)
Email: %s / Telephone: %s
Zip: %s (%s)
Type de programme: %s
Adhérent d'un parti: %s
A déjà été candidat: %s
A déjà eu un mandat: %s
Site web: %s
Twitter: %s
Facebook: %s
Autres médias:
%s
Présentation et motivation:
%s
Commentaire libre:
%s
END
				slack_notification(
					message % [
						doc[:firstName],
						doc[:lastName],
						maj[:circonscription],
						maj[:candidat],
						maj[:suppleant_name],
						maj[:suppleant_email],
						doc[:email],
						doc[:tel],
						doc[:zip],
						doc[:pays],
						doc[:programme],
						doc[:parti],
						doc[:candidat],
						doc[:mandat],
						doc[:siteweb],
						doc[:twitter],
						doc[:facebook],
						doc[:other],
						doc[:summary],
						doc[:comment]
					],
					"candidats",
					":fr:",
					"wufoo",
					attachment
				)
				if not errors.empty? then
					error!(errors.join("\n"),400)
				end
			end
		end
	end
end
