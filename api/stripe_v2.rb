# encoding: utf-8
require 'digest/md5'

module Democratech
	class StripeV2 < Grape::API
		prefix 'api'
		version ['v2']
		format :json

		get do
			# DO NOT DELETE used to test the api is live
			return {"api_version"=>"v2"}
		end

		resource :stripe do

			get do
				# DO NOT DELETE used to test the api is live
				return {"api_version"=>"stripe/v2"}
			end

			post 'democratol' do
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
					old_event=API.db[:democratol].find({:event=>event_id}).first # stripe best practice (idempotent)
					if (old_event.nil? or test) then # event does not yet exists
						charge=event["data"]["object"]
						return if charge["description"].match(/democratol/).nil?
						amount=charge["amount"].to_s
						amount.insert(-3,".")
						name=charge["source"]["name"]
						firstname=name.split(" ")[0].capitalize unless name.nil?
						lastname=name.split(" ",2)[1].upcase unless name.nil?
						curr=charge["currency"]
						zip=charge["source"]["address_zip"]
						adresse=charge["source"]["address_line1"]
						city=charge["source"]["address_city"].upcase unless charge["source"]["address_city"].nil?
						email=charge["metadata"]["email"].downcase unless charge["metadata"]["email"].nil?
						email="tfavre@gmail.com" if test
						date=Time.now.utc
						update={
							:event=>event_id,
							:lastUpdated=>date,
							:paid=>amount.to_f,
							:currency=>curr,
						}
						doc=API.db[:democratol].find({:firstName=>firstname,:lastName=>lastname}).sort(:created=>-1).limit(1).find_one_and_update({'$set'=>update})
						if doc.nil? then
							notifs.push([
								"paiement reçu mais acheteur de democratol non trouvé en base :\n%s (%s) de %s (%s) : %s %s" % [name,email,city,zip,amount,curr],
								"errors",
								":question:",
								"mongodb"
							])
							errors.push('400 Distributor could not be found in database')
						else
							notifs.push([
								"paiement reçu de %s (%s) de %s (%s) : %s %s" % [name,doc[:email],city,zip,amount,curr],
								"democratol",
								":credit_card:",
								"stripe"
							])
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
							message_params = {
								:from => doc[:email],
								:to      => 'democratol@democratech.co',
								:subject => "Nouvelle commande de %s Democratol !" % [doc[:qty].to_s],
								:text    => message
							}
							API.mg_client.send_message(MGUNDOMAIN, message_params)

							email_hash=Digest::MD5.hexdigest(doc[:email])
							uri = URI.parse(MCURL)
							http = Net::HTTP.new(uri.host, uri.port)
							http.use_ssl = true
							http.verify_mode = OpenSSL::SSL::VERIFY_NONE
							request = Net::HTTP::Patch.new("/3.0/lists/"+MCLIST_DEMOCRATOL+"/members/"+email_hash)
							request.basic_auth 'hello',MCKEY
							request.add_field('Content-Type', 'application/json')
							request.body = JSON.dump({ 'merge_fields'=>{"PAID"=>"Oui"}})
							res=http.request(request)
							if res.kind_of? Net::HTTPSuccess then
								notifs.push([
									"Distributeur %s mis a jour. Payé : *Oui*" % [doc[:email]],
									"democratol",
									":monkey_face:",
									"mailchimp"
								])
							else
								notifs.push([
									"Erreur lors de la mise a jour du distributeur %s\nErreur code: %s\nErreur msg: %s" % [doc[:email],res.code,res.body],
									"errors",
									":speak_no_evil:",
									"mailchimp"
								])
								errors.push('400 Distributor could not be updated in mailchimp')
							end
						end
					end
				else
					errors.push('400 A pb occurred when reading the incoming event')
				end
				slack_notifications(notifs)
				if not errors.empty? then
					error!(errors.join("\n"),400)
				end
			end
		end
	end
end
