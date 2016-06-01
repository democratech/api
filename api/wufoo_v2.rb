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
	class WufooV2 < Grape::API
		version ['v2']
		format :json

		get do
			# DO NOT DELETE used to test the api is live
			return {"api_version"=>"v2"}
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
					url.gsub!(':/','://') if url.match(/https?:\/\//).nil?
					return url
				end

				def strip_tags(text)
					return text.gsub(/<\/?[^>]*>/, "")
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
						:country => params["Field39"]=="Oui" ? "FRANCE" : params["Field42"],
						:zipcode =>  params["Field39"]=="Oui" ? fix_wufoo(strip_tags(params["Field38"])) : nil,
						:email => fix_wufoo(strip_tags(params["Field12"])),
						:job => fix_wufoo(strip_tags(params["Field252"])),
						:tel => fix_wufoo(strip_tags(params["Field11"])),
						:program_theme => params["Field22"]=="Un programme complet" ? "global" : fix_wufoo(strip_tags(params["Field249"])),
						:with_team => params["Field23"].match(/seul/).nil?,
						:political_party => params["Field24"]=="Oui" ? fix_wufoo(strip_tags(params["Field25"].upcase)) : "NON",
						:already_candidate => params["Field26"].match(/Non/).nil? ? fix_wufoo(strip_tags(params["Field35"].upcase)) : "NON",
						:already_elected => params["Field34"]=="Oui" ? fix_wufoo(strip_tags(params["Field36"].upcase)) : "NON",
						:website => fix_wufoo(strip_tags(params["Field13"])),
						:twitter => fix_wufoo(strip_tags(params["Field15"])),
						:facebook => fix_wufoo(strip_tags(params["Field14"])),
						:photo_key => profile_pic,
					}
					insert_candidate=<<END
INSERT INTO candidates (candidate_id,name,gender,country,zipcode,email,job,tel,program_theme,with_team,political_party,already_candidate,already_elected,website,twitter,facebook,photo,candidate_key) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,md5(random()::text)) RETURNING *
END
					res=API.pg.exec_params(insert_candidate,[
						maj[:candidate_id],
						maj[:name],
						maj[:gender],
						maj[:country],
						maj[:zipcode],
						maj[:email],
						maj[:job],
						maj[:tel],
						maj[:program_theme],
						maj[:with_team],
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
				rescue Exception=>e
					STDERR.puts "Exception raised : #{e.message}"
					res=nil
				ensure
					pg_close()
				end
				# 2. Email notification to the candidate with its admin page and instructions
				message= {
					:to=>[{
						:email=> "#{maj[:email]}",
						:name=> "#{maj[:name]}"
					}],
					:merge_vars=>[{
						:rcpt=>"#{maj[:email]}",
						:vars=>[ {:name=>"CANDIDATE_KEY",:content=>"#{candidate_key}"} ]
					}]
				}
				begin
					result=API.mandrill.messages.send_template("laprimaire-org-candidates-bienvenue",[],message)
				rescue Mandrill::Error => e
					msg="A mandrill error occurred: #{e.class} - #{e.message}"
					STDERR.puts msg
				end

				# 2. Slack notification
				doc={}
				doc[:firstName]=params["Field3"].capitalize unless params["Field3"].nil?
				doc[:lastName]=params["Field4"].upcase unless params["Field4"].nil?
				doc[:email]=params["Field12"].downcase unless params["Field12"].nil?
				doc[:zip]=params["Field38"]
				doc[:pays]=params["Field42"].upcase unless params["Field42"].nil?
				doc[:pays]="FRANCE" if doc[:pays].empty?
				doc[:tel]=params["Field11"]
				doc[:programme]=(params["Field22"].match(/complet/) ? params["Field22"]:params["Field249"]) unless params["Field22"].nil?
				doc[:equipe]=params["Field23"]
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
Email: %s / Telephone: %s
Zip: %s (%s)
Type de programme: %s
A une équipe: %s
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
						doc[:email],
						doc[:tel],
						doc[:zip],
						doc[:pays],
						doc[:programme],
						doc[:equipe],
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

			post 'democratol' do
				error!('401 Unauthorized', 401) unless authorized
				errors=[]
				notifs=[]
				doc={}
				doc[:firstName]=params["Field19"].strip.capitalize unless params["Field19"].nil?
				doc[:lastName]=params["Field20"].strip.upcase unless params["Field20"].nil?
				doc[:qty]=params["Field9"].match(/^[0-9]+/)[0].to_i() unless params["Field9"].nil?
				doc[:adresse]=params["Field123"]
				doc[:adresse2]=params["Field124"]
				doc[:zip]=params["Field127"]
				doc[:ville]=params["Field125"].strip.capitalize unless params["Field125"].nil?
				doc[:etat]=params["Field126"]
				doc[:pays]=params["Field128"].strip.capitalize unless params["Field128"].nil?
				doc[:store]=params["Field13"]
				doc[:email]=params["Field14"].strip.downcase unless params["Field14"].nil?
				doc[:telephone]=params["Field15"]
				doc[:message]=params["Field17"]
				doc[:price]=params["PurchaseTotal"].to_f
				doc[:created]=Time.now.utc
				body=<<END
Distributeur : %s %s
Adresse : %s %s, %s %s (%s)
Quantité : %s
Prix : %s euros
Commerçant ? %s
Email : %s
Téléphone : %s
Message : %s
END
				message="Nouveau distributeur de Democratol !\n"+body % [
					doc[:firstName],
					doc[:lastName],
					doc[:adresse],
					doc[:adresse2],
					doc[:zip],
					doc[:ville],
					doc[:pays],
					doc[:qty].to_s,
					doc[:price].to_s,
					doc[:store],
					doc[:email],
					doc[:telephone],
					doc[:message]
				]
				notifs.push([message,"democratol",":pill:","wufoo"])
				insert_res=API.db[:democratol].insert_one(doc)
				if insert_res.n!=1 then
					error_msg="Erreur lors de l'enregistrement d'un distributeur de Democratol !\n"+body+"Error : %s\n"
					message=error_msg % [
						doc[:firstName],
						doc[:lastName],
						doc[:adresse],
						doc[:adresse2],
						doc[:zip],
						doc[:ville],
						doc[:pays],
						doc[:qty].to_s,
						doc[:price].to_s,
						doc[:store],
						doc[:email],
						doc[:telephone],
						doc[:message],
						insert_res.inspect
					]
					notifs.push([
						message,
						"errors",
						":scream:",
						"mongodb"
					])
					errors.push('400 Distributor could not be registered')
				end

				# 4. We send the notifications and return
				slack_notifications(notifs)
				if not errors.empty? then
					error!(errors.join("\n"),400)
				end
			end

			post 'supporter' do
				error!('401 Unauthorized', 401) unless authorized
				errors=[]
				notifs=[]

				# 1. We read the new supporter info from the parameters
				doc={}
				doc[:firstName]=params["Field9"].capitalize unless params["Field9"].nil?
				doc[:lastName]=params["Field10"].upcase unless params["Field10"].nil?
				doc[:email]=params["Field1"].downcase unless params["Field1"].nil?
				doc[:country]=params["Field127"].upcase unless params["Field127"].nil?
				doc[:postalCode]=params["Field118"].strip.gsub(/\s+/,"") unless params["Field118"].nil?
				doc[:city]=params["Field130"].upcase unless params["Field130"].nil?
				doc[:reason]=params["Field119"] unless params["Field119"].nil?
				doc[:cmp]=params["Field132"] unless params["Field132"].nil?
				doc[:created]=Time.now.utc
				if doc[:city].to_s.empty? and not doc[:postalCode].to_s.empty? then
					commune=API.db[:communes].find({:postalCode=>doc[:postalCode]}).first
					doc[:city]=commune['name'] unless commune.nil?
				end

				# 2. we subscribe the new supporter to our mailchimp mailing list
				success,res=add_to_mailing_list(doc)
				if success then
					# we retrieve the subscriber ID from the newly created mailchimp entry
					slack_msg="Enregistrement du nouveau supporteur (%s %s) OK !" % [doc[:firstName],doc[:lastName]]
					slack_msg+=" (source: %s)" % [doc[:cmp]] if not doc[:cmp].empty?
					mailchimp_id=JSON.parse(res.body)["id"]
					notifs.push([
						slack_msg,
						"supporteurs",
						":monkey_face:",
						"mailchimp"
					])
				else
					notifs.push([
						"Erreur lors de l'enregistrement d'un nouveau supporteur ! [CODE: %s]" % [res.code],
						"errors",
						":speak_no_evil:",
						"mailchimp"
					])
					errors.push('400 Supporter could not be subscribed')
				end

				# 3. We register the new supporter into the DB (with his mailchimp id if subscription was successful)
				doc[:mailchimp_id]=mailchimp_id unless mailchimp_id.nil?
				insert_res=API.db[:supporteurs].insert_one(doc)
				if insert_res.n==1 then
					notifs.push([
						"Nouveau supporteur ! %s %s (%s, %s, %s) : %s" % [doc[:firstName],doc[:lastName],doc[:postalCode],doc[:city],doc[:country],doc[:reason]],
						"supporteurs",
						":thumbsup:",
						"mongodb"
					])
				else # if the supporter could not be insert in the db
					notifs.push([
						"Erreur lors de l'enregistrement d'un nouveau supporteur: %s ! %s %s (%s, %s, %s) : %s\nError msg: %s\nError trace: %s" % [doc[:email],doc[:firstName],doc[:lastName],doc[:postalCode],doc[:city],doc[:country],doc[:reason],insert_res.inspect],
						"errors",
						":scream:",
						"mongodb"
					])
					errors.push('400 Supporter could not be registered')
				end

				# 4. We send the notifications and return
				slack_notifications(notifs)
				if not errors.empty? then
					error!(errors.join("\n"),400)
				end
			end

			post 'contributor' do
				error!('401 Unauthorized', 401) unless authorized
				errors=[]
				notifs=[]

				# 1. We read the contributor info from the parameters
				email=params["Field2"].downcase
				note=params["Field211"]
				tags=[]
				tags.push("ambassadeur") unless params["Field213"].empty?
				tags.push("event") unless params["Field214"].empty?
				tags.push("visibility") unless params["Field215"].empty?
				tags.push("presse") unless (params["Field314"].empty? and params["Field315"].empty?)
				tags.push("journaliste") unless params["Field314"].empty?
				tags.push("relations presse") unless params["Field315"].empty?
				tags.push("creatif graphique") unless params["Field415"].empty?
				tags.push("creatif video") unless params["Field416"].empty?
				tags.push("content") unless params["Field417"].empty?
				tags.push("seo") unless params["Field418"].empty?
				tags.push("donateur") unless params["Field516"].empty?
				tags.push("fundraiser") unless params["Field517"].empty?
				tags.push("elu") unless (params["Field617"].empty? and params["Field618"].empty?)
				tags.push("je suis un elu") unless params["Field617"].empty?
				tags.push("je connais un elu") unless params["Field618"].empty?
				tags.push("candidat") unless (params["Field10"].empty? and params["Field11"].empty?)
				tags.push("je suis candidat") unless params["Field10"].empty?
				tags.push("je connais un candidat") unless params["Field11"].empty?
				tags.push("beta-testeur") unless params["Field110"].empty?
				tags.push("designer") unless params["Field111"].empty?
				tags.push("developer") unless (params["Field112"].empty? and params["Field113"].empty?)
				tags.push("frontend") unless params["Field112"].empty?
				tags.push("backend") unless params["Field113"].empty?
				tags.push("android") unless params["Field114"].empty?
				tags.push("ios") unless params["Field115"].empty?

				# 2. we update the subscriber record with the contributor's tags
				update={
					:contributeur=>1,
					:dispo=>params["Field3"],
					:tags=>tags,
					:lastUpdated=>Time.now.utc
				}
				supporter=API.db[:supporteurs].find({:email=>email}).find_one_and_update({'$set'=>update}) # returns the document found

				# 3. if no supporter was found then we register him (can be the case if the contributor did not sign the initial form)
				if supporter.nil? then
					update[:email]=email
					update[:created]=Time.now.utc
					insert_res=API.db[:supporteurs].insert_one(update)
					if insert_res.n==1 then
						notifs.push([
							"Nouveau supporteur ET contributeur ! Dispo: %s, Tags: %s, Message: %s" % [update[:dispo],tags.inspect,note],
							"supporteurs",
							":muscle:",
							"mongodb"
						])
					else
						notifs.push([
							"Erreur lors de l'enregistrement d'un nouveau contributeur !\nEmail: %s\nDispo: %s\nTags: %s\nError msg: %s" % [email,update[:dispo],tags.inspect,insert_res.inspect],
							"errors",
							":fearful:",
							"mongodb"
						])
						errors.push('400 Contributor not registered and cannot be registered')
					end

					# 4. If no supporter was found then we subscribe him on our mailchimp mailing list
					success,res=add_to_mailing_list(update)
					if success then
						# we retrieve the subscriber ID from the newly created mailchimp entry
						mailchimp_id=JSON.parse(res.body)["id"]
						notifs.push([
							"Enregistrement d'un nouveau supporteur !",
							"supporteurs",
							":monkey_face:",
							"mailchimp"
						])
					else
						notifs.push([
							"Erreur lors de l'enregistrement d'un nouveau supporteur ! [CODE: %s]" % [res.code],
							"errors",
							":speak_no_evil:",
							"mailchimp"
						])
						errors.push('400 New supporter could not be subscribed')
					end

				else
					mailchimp_id=supporter['mailchimp_id']
					notifs.push([
						"Nouveau contributeur ! Dispo: %s, Tags: %s, Message: %s" % [update[:dispo],tags.join(","),note],
						"supporteurs",
						":muscle:",
						"mongodb"
					])
				end

				# 5. We retrieve the groups of the mailchimp mailing list and match them to the tags of the contributor
				if not mailchimp_id.to_s.empty? then
					uri = URI.parse(MCURL)
					http = Net::HTTP.new(uri.host, uri.port)
					http.use_ssl = true
					http.verify_mode = OpenSSL::SSL::VERIFY_NONE
					request = Net::HTTP::Get.new("/3.0/lists/"+MCLIST+"/interest-categories/"+MCGROUPCAT+"/interests?count=100&offset=0")
					request.basic_auth 'hello',MCKEY
					res=http.request(request)
					response=JSON.parse(res.body)["interests"]
					groups={}
					response.each do |i|
						if (tags.include? i["name"].downcase) then
							groups[i["id"]]=true
						else
							groups[i["id"]]=false
						end
					end

					# 6. We update the subscriber on mailchimp to reflect the tags of the contributor
					uri = URI.parse(MCURL)
					http = Net::HTTP.new(uri.host, uri.port)
					http.use_ssl = true
					http.verify_mode = OpenSSL::SSL::VERIFY_NONE
					request = Net::HTTP::Patch.new("/3.0/lists/"+MCLIST+"/members/"+mailchimp_id)
					request.basic_auth 'hello',MCKEY
					request.add_field('Content-Type', 'application/json')
					request.body = JSON.dump({
						'interests'=>groups
					})
					res=http.request(request)
					if res.kind_of? Net::HTTPSuccess then
						notifs.push([
							"Supporter mis a jour. Tags: %s" % [tags.join(",")],
							"supporteurs",
							":monkey_face:",
							"mailchimp"
						])
					else
						notifs.push([
							"Erreur lors de la mise a jour du supporter. Tags: %s" % [tags.inspect],
							"errors",
							":speak_no_evil:",
							"mailchimp"
						])
						errors.push('400 Supporter could not be updated in mailchimp')
					end
				end

				# 4. We send the notifications and return
				slack_notifications(notifs)
				if not errors.empty? then
					error!(errors.join("\n"),400)
				end
			end

			post 'signature' do
				error!('401 Unauthorized', 401) unless authorized
				errors=[]
				notifs=[]

				# 1. We read the new supporter info from the parameters
				doc={}
				doc[:firstname]=params["Field9"].capitalize unless params["Field9"].nil?
				doc[:lastname]=params["Field10"].upcase unless params["Field10"].nil?
				doc[:email]=params["Field1"].downcase unless params["Field1"].nil?
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
					else # if the supporter could not be insert in the db
						notifs.push([
							"Erreur lors de l'enregistrement d'une signature pour l'appel aux maires: %s (%s, %s) : %s\nError trace: %s" % [doc[:email],doc[:firstname],doc[:lastname],doc[:comment],res.inspect],
							"errors",
							":scream:",
							"pg"
						])
						errors.push('400 Supporter could not be registered')
					end
				rescue
					notifs.push([
						"Erreur lors de l'enregistrement d'une signature pour l'appel aux maires: %s (%s, %s) : %s\nError trace: %s" % [doc[:email],doc[:firstname],doc[:lastname],doc[:comment],res.inspect],
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
		end
	end
end
