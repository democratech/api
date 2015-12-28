# encoding: utf-8
require 'grape'
require 'json'
require 'mongo'
require 'bson'
require 'time'
require 'net/http'
require 'uri'

module Democratech
	class API < Grape::API
		prefix 'api'
		version 'v1'
		format :json
		class << self
			attr_accessor :db, :mg_client
		end

		helpers do
			def slack_notification(msg,channel="#supporteurs",icon=":ghost:",from="democratech")
				uri = URI.parse(SLCKHOST)
				http = Net::HTTP.new(uri.host, uri.port)
				http.use_ssl = true
				http.verify_mode = OpenSSL::SSL::VERIFY_NONE
				request = Net::HTTP::Post.new(SLCKPATH)
				request.body = "payload="+JSON.dump({
					"channel"=> channel,
					"username"=> from,
					"text"=> msg,
					"icon_emoji"=>icon
				})
				res=http.request(request)
				if not res.kind_of? Net::HTTPSuccess then
					puts "An error occurred trying to send a Slack notification\n"
				end
			end

			def slack_notifications(notifs)
				channels={}
				notifs.each do |n|
					msg=n[0] || ""
					chann=n[1] || "#errors"
					icon=n[2] || ":warning:"
					from=n[3] || "democratech"
					if channels[chann].nil? then
						channels[chann]="%s *%s* %s" % [icon,from,msg]
					else
						channels[chann]+="\n%s *%s* %s" % [icon,from,msg]
					end
				end
				channels.each do |k,v|
					slack_notification(v,k,":bell:","democratech")
				end
			end
		end

		get 'test' do
			# DO NOT DELETE used to test the api is live
		end

		resource :supporteurs do
			get 'total' do
				nb_supporteurs=API.db[:supporteurs].find().count
				return {"total"=>nb_supporteurs}
			end
		end

		resource :stripe do
			get 'total' do
				res=API.db['donateurs'].find.aggregate([{"$group"=>{_id: nil, total: {"$sum"=> "$amount"}}}]).first
				total_amount=res['total'].to_i
				nb_donateurs=API.db['donateurs'].find().count
				return {"total"=>total_amount,"nb_donateurs"=>nb_donateurs}
			end

			post 'donate' do
				errors=[]
				notifs=[]
				# Get the credit card details submitted by the form
				token=params[:stripeToken]
				doc={}
				doc[:email]=params[:stripeEmail].downcase unless params[:stripeEmail].nil?
				doc[:created]=Time.now.utc
				doc[:currency]="eur"
				name=params[:stripeBillingName]
				firstName=name.split(" ")[0] unless name.nil?
				lastName=name.split(" ",2)[1] unless name.nil?
				doc[:firstName]=firstName.capitalize unless firstName.nil?
				doc[:lastName]=lastName.upcase unless lastName.nil?
				doc[:adresse1]=params[:stripeBillingAddressLine1]
				doc[:adresse2]=params[:stripeBillingAddressLine2]
				doc[:city]=params[:stripeBillingAddressCity].upcase unless params[:stripeBillingAddressCity].nil?
				doc[:postalCode]=params[:stripeBillingAddressZip]
				doc[:country]=params[:stripeBillingAddressCountry].upcase unless params[:stripeBillingAddressCountry].nil?
				doc[:tags]=["financeur"]
				doc[:from]="stripe"
				donateur = Stripe::Customer.create(
					:source => token,
					:description => "%s %s - Donateur LaPrimaire.org" % [firstName, lastName],
					:email => doc[:email]
				)
				doc[:donateur_id]=donateur.id
				Stripe::Charge.create(
					:amount => params[:don], # in cents
					:currency => "eur",
					:customer => donateur.id,
					:description => "Don pour LaPrimaire.org. Merci beaucoup !",
					:receipt_email => doc[:email]
				)
				doc[:amount]=params[:don].to_s.insert(-3,".").to_f
				insert_res=API.db[:donateurs].insert_one(doc)
				if insert_res.n==1 then
					notifs.push([
						"Nouveau donateur enregistré ! %s %s (%s, %s) : %s %s" % [doc[:firstName],doc[:lastName],doc[:postalCode],doc[:city],doc[:amount].to_s,doc[:currency]],
						"#crowdfunding",
						":thumbsup:",
						"mongodb"
					])
				else # if the donator could not be insert in the db
					notifs.push([
						"Erreur lors de l'enregistrement d'un nouveau donateur: %s ! %s %s (%s, %s) : %s %s\nError trace: %s" % [doc[:email],doc[:firstName],doc[:lastName],doc[:postalCode],doc[:city],doc[:amount].to_s,doc[:currency],insert_res.inspect],
						"#errors",
						":scream:",
						"mongodb"
					])
					errors.push('400 Donator could not be registered')
				end
				notifs.push([
					"nouvelle donation de %s de %s (%s) : %s %s" % [name,doc[:city],doc[:postalCode],doc[:amount].to_s,doc[:currency]],
					"#crowdfunding",
					":moneybag:",
					"stripe"
				])
				message="Date: %s\nMontant: %s %s\n\n%s %s - %s, %s %s" % [doc[:created],doc[:amount].to_s,doc[:currency],doc[:firstName],doc[:lastName],doc[:adresse1],doc[:postalCode],doc[:city]]
				message_params = {
					:from => doc[:email],
					:to      => 'don@democratech.co',
					:subject => "Nouveau don : %s %s !" % [doc[:amount].to_s,doc[:currency]],
					:text    => message
				}
				API.mg_client.send_message(MGUNDOMAIN, message_params)
				redirect "https://laprimaire.org/merci/"
				if not errors.empty? then
					error!(errors.join("\n"),400)
				end
				slack_notifications(notifs)
			end

			post 'donation' do
				errors=[]
				notifs=[]
				test=false
				event_id=params["id"]
				if event_id=="evt_00000000000000" then # test event
					event=params
					test=true
				else
					event = Stripe::Event.retrieve(event_id) # stripe best practice (for security)
				end
				if not event.nil? then
					old_event=API.db[:donateurs].find({:event=>event_id}).first # stripe best practice (idempotent)
					if (old_event.nil? or test) then # event does not yet exists
							charge=event["data"]["object"]
							amount=charge["amount"].to_s
							amount.insert(-3,".")
							name=charge["source"]["name"]
							firstname=name.split(" ")[0] unless name.nil?
							lastname=name.split(" ",2)[1] unless name.nil?
							curr=charge["currency"]
							zip=charge["source"]["address_zip"]
							adresse=charge["source"]["address_line1"]
							city=charge["source"]["address_city"]
							email=charge["metadata"]["email"]
							email="tfavre@gmail.com" if test
							date=Time.now.utc
							doc={:event=>event_id,:created=>date,:amount=>amount.to_f,:currency=>curr,:firstname=>firstname,:lastname=>lastname,:email=>email,:address=>adresse,:city=>city,:zip=>zip}
							insert_res=API.db[:donateurs].insert_one(doc)
							if insert_res.n==1 then
								notifs.push([
									"Nouveau donateur enregistré ! %s %s (%s, %s) : %s %s" % [doc[:firstname],doc[:lastname],doc[:zip],doc[:city],doc[:amount],doc[:currency]],
									"#crowdfunding",
									":thumbsup:",
									"mongodb"
								])
							else # if the donator could not be insert in the db
								notifs.push([
									"Erreur lors de l'enregistrement d'un nouveau donateur: %s ! %s %s (%s, %s) : %s %s\nError trace: %s" % [doc[:email],doc[:firstname],doc[:lastname],doc[:zip],doc[:city],doc[:amount],doc[:currency],insert_res.inspect],
									"#errors",
									":scream:",
									"mongodb"
								])
								errors.push('400 Donator could not be registered')
							end
							notifs.push([
								"nouvelle donation de %s de %s (%s) : %s %s" % [name,city,zip,amount,curr],
								"#crowdfunding",
								":credit_card:",
								"stripe"
							])
							message="Date: %s\nMontant: %s %s\n\n%s %s - %s, %s %s" % [doc[:created],doc[:amount],doc[:currency],doc[:firstname],doc[:lastname],doc[:address],doc[:zip],doc[:city]]
							message_params = {:from => doc[:email],
								  :to      => 'don@democratech.co',
								  :subject => "Nouveau don : %s %s !" % [doc[:amount],doc[:currency]],
								  :text    => message}
							API.mg_client.send_message(MGUNDOMAIN, message_params)
					end
				else
					errors.push('400 A pb occurred when reading the incoming event')
				end
				if not errors.empty? then
					error!(errors.join("\n"),400)
				end
				slack_notifications(notifs)
			end
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
			end

			post 'presse' do
				error!('401 Unauthorized', 401) unless authorized
				errors=[]
				notifs=[]
				# 1. We read the new supporter info from the parameters
				doc={}
				doc[:firstName]=params["Field1"].capitalize unless params["Field1"].nil?
				doc[:lastName]=params["Field2"].upcase unless params["Field2"].nil?
				doc[:societe]=params["Field11"]
				doc[:email]=params["Field4"].downcase unless params["Field4"].nil?
				doc[:tel]=params["Field114"] unless params["Field114"].nil?
				doc[:msg]=params["Field5"]
				doc[:abo]=params["Field112"]
				notifs.push([
					"Nouveau contact presse reçu !\nPrénom : %s\nNom : %s\nSociété : %s\nEmail : %s\nTel : %s\nAbonnement : %s\nMessage : %s" % [doc[:firstName],doc[:lastName],doc[:societe],doc[:email],doc[:tel],doc[:abo],doc[:msg]],
					"#contact",
					":newspaper:",
					"wufoo"
				])
				slack_notifications(notifs)
				if not errors.empty? then
					error!(errors.join("\n"),400)
				end
			end

			post 'contact' do
				error!('401 Unauthorized', 401) unless authorized
				errors=[]
				notifs=[]
				# 1. We read the new supporter info from the parameters
				doc={}
				doc[:firstName]=params["Field1"].capitalize unless params["Field1"].nil?
				doc[:lastName]=params["Field2"].upcase unless params["Field2"].nil?
				doc[:objet]=params["Field9"]
				doc[:msg]=params["Field5"]
				doc[:type]=params["Field11"]
				notifs.push([
					"Nouveau message reçu (dans Front) via le formulaire de contact !\nPrénom : %s\nNom : %s\nObjet : %s\nType : %s\nMessage : %s" % [doc[:firstName],doc[:lastName],doc[:objet],doc[:type],doc[:msg]],
					"#contact",
					":mailbox:",
					"wufoo"
				])
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
				doc[:created]=Time.now.utc
				if doc[:city].to_s.empty? and not doc[:postalCode].to_s.empty? then
					commune=API.db[:communes].find({:postalCode=>doc[:postalCode]}).first
					doc[:city]=commune['name'] unless commune.nil?
				end

				# 2. we subscribe the new supporter to our mailchimp mailing list
				success,res=add_to_mailing_list(doc)
				if success then
					# we retrieve the subscriber ID from the newly created mailchimp entry
					mailchimp_id=JSON.parse(res.body)["id"]
					notifs.push([
						"Enregistrement du nouveau supporteur (%s %s) OK !" % [doc[:firstName],doc[:lastName]],
						"#supporteurs",
						":monkey_face:",
						"mailchimp"
					])
				else
					notifs.push([
						"Erreur lors de l'enregistrement d'un nouveau supporteur ! [CODE: %s]" % [res.code],
						"#errors",
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
						"#supporteurs",
						":thumbsup:",
						"mongodb"
					])
				else # if the supporter could not be insert in the db
					notifs.push([
						"Erreur lors de l'enregistrement d'un nouveau supporteur: %s ! %s %s (%s, %s, %s) : %s\nError msg: %s\nError trace: %s" % [doc[:email],doc[:firstName],doc[:lastName],doc[:postalCode],doc[:city],doc[:country],doc[:reason],insert_res.inspect],
						"#errors",
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
				tags.push("creatif graphique") unless params["Field415"].empty?
				tags.push("creatif video") unless params["Field416"].empty?
				tags.push("content") unless params["Field417"].empty?
				tags.push("seo") unless params["Field418"].empty?
				tags.push("donateur") unless params["Field516"].empty?
				tags.push("fundraiser") unless params["Field517"].empty?
				tags.push("elu") unless (params["Field617"].empty? and params["Field618"].empty?)
				tags.push("candidat") unless (params["Field10"].empty? and params["Field11"].empty?)
				tags.push("beta-testeur") unless params["Field110"].empty?
				tags.push("designer") unless params["Field111"].empty?
				tags.push("developer") unless (params["Field112"].empty? and params["Field113"].empty?)
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
							"#supporteurs",
							":muscle:",
							"mongodb"
						])
					else
						notifs.push([
							"Erreur lors de l'enregistrement d'un nouveau contributeur !\nEmail: %s\nDispo: %s\nTags: %s\nError msg: %s" % [email,update[:dispo],tags.inspect,insert_res.inspect],
							"#errors",
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
							"#supporteurs",
							":monkey_face:",
							"mailchimp"
						])
					else
						notifs.push([
							"Erreur lors de l'enregistrement d'un nouveau supporteur ! [CODE: %s]" % [res.code],
							"#errors",
							":speak_no_evil:",
							"mailchimp"
						])
						errors.push('400 New supporter could not be subscribed')
					end

				else
					mailchimp_id=supporter['mailchimp_id']
					notifs.push([
						"Nouveau contributeur ! Dispo: %s, Tags: %s, Message: %s" % [update[:dispo],tags.join(","),note],
						"#supporteurs",
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
							"#supporteurs",
							":monkey_face:",
							"mailchimp"
						])
					else
						notifs.push([
							"Erreur lors de la mise a jour du supporter. Tags: %s" % [tags.inspect],
							"#errors",
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
