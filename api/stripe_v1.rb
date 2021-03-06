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
	class StripeV1 < Grape::API
		version ['v1','v2']
		format :json

		get do
			# DO NOT DELETE used to test the api is live
			return {"api_version"=>"v1"}
		end

		resource :stripe do

			get do
				# DO NOT DELETE used to test the api is live
				return {"api_version"=>"stripe/v1"}
			end

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
						"crowdfunding",
						":thumbsup:",
						"mongodb"
					])
				else # if the donator could not be insert in the db
					notifs.push([
						"Erreur lors de l'enregistrement d'un nouveau donateur: %s ! %s %s (%s, %s) : %s %s\nError trace: %s" % [doc[:email],doc[:firstName],doc[:lastName],doc[:postalCode],doc[:city],doc[:amount].to_s,doc[:currency],insert_res.inspect],
						"errors",
						":scream:",
						"mongodb"
					])
					errors.push('400 Donator could not be registered')
				end
				notifs.push([
					"nouvelle donation de %s de %s (%s) : %s %s" % [name,doc[:city],doc[:postalCode],doc[:amount].to_s,doc[:currency]],
					"crowdfunding",
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
		end
	end
end
