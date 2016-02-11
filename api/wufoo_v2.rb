# encoding: utf-8

module Democratech
	class WufooV2 < Grape::API
		prefix 'api'
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
			end

			get do
				# DO NOT DELETE used to test the api is live
				return {"api_version"=>"wufoo/v2"}
			end

			post 'preinscription' do
				error!('401 Unauthorized', 401) unless authorized
				errors=[]
				# 1. We read the new supporter info from the parameters
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
				doc[:firstName]=params["Field19"].capitalize unless params["Field19"].nil?
				doc[:lastName]=params["Field20"].upcase unless params["Field20"].nil?
				doc[:qty]=params["Field9"].match(/^[0-9]+/)[0].to_i() unless params["Field9"].nil?
				doc[:adresse]=params["Field123"]
				doc[:adresse2]=params["Field124"]
				doc[:zip]=params["Field127"]
				doc[:ville]=params["Field125"].capitalize unless params["Field125"].nil?
				doc[:etat]=params["Field126"]
				doc[:pays]=params["Field128"].capitalize unless params["Field128"].nil?
				doc[:store]=params["Field13"]
				doc[:email]=params["Field14"].downcase unless params["Field14"].nil?
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
		end
	end
end
