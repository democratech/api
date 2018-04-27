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

require 'digest'
require 'date'

module Democratech
	class PaymentV1 < Grape::API
		version ['v1']
		format :json

		get do
			# DO NOT DELETE used to test the api is live
			return {"api_version"=>"v1"}
		end

		resource :payment do
			helpers do
				def authorized
					params['HandshakeKey']==WUFHS
				end

				def email_valid(email)
					return !email.match(/\A[^@\s]+@([^@\s]+\.)+[^@\s]+\z/).nil?	
				end

				def signature(params)
					tmp=params.select {|k,v| k.match(/vads_/) }	
					tmp=Hash[tmp.sort]
					vads=tmp.values.flatten
					if ::DEBUG then
						vads.push(PZ_TEST_CERT) 
					else
						vads.push(PZ_PROD_CERT)
					end
					vads_str=vads.join('+')
					return Digest::SHA1.hexdigest(vads_str)
				end

				def search_opened_transaction(email)
					search_transaction="SELECT * FROM donations WHERE email=$1 AND status='CREATED' AND created>'2016-11-28' LIMIT 1"
					res=API.pg.exec_params(search_transaction,[email])
					return res.num_tuples.zero? ? nil : res[0]
				end

				def get_transaction(transaction_id)
					search_transaction="SELECT d.*,c.name,c.slug FROM donations as d LEFT JOIN candidates as c ON (c.candidate_id=d.candidate_id) WHERE donation_id=$1"
					res=API.pg.exec_params(search_transaction,[transaction_id])
					return res.num_tuples.zero? ? nil : res[0]
				end

				def update_transaction(transaction)
					transaction['status']='AUTHORISED' if transaction['status']=='CAPTURED'
					params=[transaction['status'],
						transaction['amount_raw'],
						transaction['currency'],
						transaction['change_rate'],
						transaction['amount'],
						transaction['auth_result'],
						transaction['threeds'],
						transaction['threeds_status'],
						transaction['card_brand'],
						transaction['card_number'],
						transaction['card_expiry_month'],
						transaction['card_expiry_year'],
						transaction['card_bank_code'],
						transaction['card_bank_product'],
						transaction['card_country'],
						transaction['order_id'],
						transaction['email'],
						transaction['transaction_id']
					]
					upd_transaction=<<END
UPDATE donations SET status=$1, amount_raw=$2, currency=$3, change_rate=$4, amount=$5, auth_result=$6, threeds=$7, threeds_status=$8, card_brand=$9, card_number=$10, card_expiry_month=$11, card_expiry_year=$12, card_bank_code=$13, card_bank_product=$14, card_country=$15, order_id=$16, email=$17, finished=CURRENT_TIMESTAMP WHERE donation_id=$18 RETURNING *
END
					res=API.pg.exec_params(upd_transaction,params)
					return res.num_tuples.zero? ? nil : res[0]
				end

				def create_transaction(infos)
					order_id=DateTime.parse(Time.now().to_s).strftime("%Y%m%d%H%M%S")+rand(999).to_i.to_s
					new_transaction="INSERT INTO donations (origin,email,order_id,firstname,lastname,adresse,zipcode,city,state,country,adhesion,recipient,candidate_id) VALUES ('payzen',$1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12) RETURNING *"
					res=API.pg.exec_params(new_transaction,[
						infos['email'],
						order_id,
						infos['firstname'],
						infos['lastname'],
						infos['adresse'],
						infos['zipcode'],
						infos['city'],
						infos['state'],
						infos['country'],
						infos['adhesion'],
						'PARTI',
						infos['candidate_id']
					])
					return res.num_tuples.zero? ? nil : res[0]
				end
			end

			get do
				# DO NOT DELETE used to test the api is live
				return {"api_version"=>"payment/v1"}
			end

			get 'candidate/:candidate_id' do
				candidate_id=params['candidate_id'].to_i
				pg_connect()
				begin
					search_transaction="SELECT count(*) as nb_adherents, sum(amount) as total FROM donations WHERE candidate_id=$1 AND recipient='PARTI' and (origin='chèque' OR (origin='payzen' AND status='AUTHORISED'))"
					res=API.pg.exec_params(search_transaction,[candidate_id])
					raise "0 member found" if res.num_tuples.zero?
				rescue PG::Error=>e
					status 500
					API.log.error "GET payment/total PG error #{e.message}"
				ensure
					pg_close()
				end
				return {"total"=>res[0]['total'],"nb_adherents"=>res[0]['nb_adherents']}
			end

			get 'total' do
				pg_connect()
				begin
					search_transaction="SELECT count(*) as nb_adherents, case when sum(amount) is null then 0 else sum(amount) end as total FROM donations WHERE created>'2017-09-15' AND candidate_id is null AND recipient='PARTI' and (origin='chèque' OR (origin='payzen' AND status='AUTHORISED'))"
					res=API.pg.exec(search_transaction)
					raise "0 member found" if res.num_tuples.zero?
				rescue PG::Error=>e
					status 500
					API.log.error "GET payment/total PG error #{e.message}"
				ensure
					pg_close()
				end
				return {"total"=>res[0]['total'],"nb_adherents"=>res[0]['nb_adherents']}
			end

			post 'transaction' do
				return JSON.dump({'error'=>'missing email'}) if params['vads_cust_email'].nil?
				candidate_id= params['candidate_id']=='' ? nil : params['candidate_id'].to_i
				donateur={
					'email'=>params['vads_cust_email'].downcase.gsub(/\A\p{Space}*|\p{Space}*\z/, ''),
					'firstname'=>params['vads_cust_first_name'].gsub(/"/,''),
					'lastname'=>params['vads_cust_last_name'].gsub(/"/,''),
					'adresse'=>params['vads_cust_address'].gsub(/"/,''),
					'city'=>params['vads_cust_city'].gsub(/"/,''),
					'zipcode'=>params['vads_cust_zip'].gsub(/"/,''),
					'state'=>params['vads_cust_state'].gsub(/"/,''),
					'country'=>params['vads_cust_country'].gsub(/"/,''),
					'adhesion'=>params['adhesion'].to_i,
					'candidate_id'=>candidate_id
				}
				return JSON.dump({'error'=>'wrong email'}) if !email_valid(donateur['email'])
				answer={}
				pg_connect()
				begin
					#transaction=search_opened_transaction(donateur['email'])
					transaction=create_transaction(donateur) if transaction.nil?
					raise "cannot create transaction" if transaction.nil?
					params['vads_trans_id']=transaction['donation_id']
					params['vads_order_id']=transaction['order_id']
					answer={
						'signature'=>signature(params),
						'transaction_id'=>transaction['donation_id'],
						'order_id'=>transaction['order_id'],
						'email'=>transaction['email']
					}
					#answer["transaction_date"]=Date.parse(transaction['created']).strftime("%Y%M%D%H%m%s")
				rescue StandardError=>e
					status 500
					API.log.error "POST payment/transaction STD error #{e.message} #{answer}"
				rescue PG::Error=>e
					status 500
					API.log.error "POST payment/transaction PG error #{e.message} #{answer}"
				ensure
					pg_close()
				end
				return JSON.dump(answer)
			end

			post 'ipn' do
				notifs=[]
				sig=signature(params)
				pg_connect()
				begin
					raise "bad signature" if (params['signature']!=sig)
					transaction=get_transaction(params['vads_trans_id'])
					raise "transaction not found" if transaction.nil?
					# raise "transaction already processed" if transaction['status']=='AUTHORISED' # I dont see why we should do that
					maj={
						'transaction_id'=>params['vads_trans_id'],
						'status'=>params['vads_trans_status'],
						'amount_raw'=>(params['vads_amount'].to_i)/100,
						'currency'=>params['vads_currency'],
						'change_rate'=>params['vads_change_rate'],
						'amount'=>(params['vads_effective_amount'].to_i)/100,
						'auth_result'=>params['vads_auth_result'],
						'threeds'=>params['vads_threeds_enrolled'],
						'threeds_status'=>params['vads_threeds_status'],
						'card_brand'=>params['vads_card_brand'],
						'card_number'=>params['vads_card_number'],
						'card_expiry_month'=>params['vads_card_expiry_month'],
						'card_expiry_year'=>params['vads_card_expiry_year'],
						'card_bank_code'=>params['vads_bank_code'],
						'card_bank_product'=>params['vads_bank_product'],
						'card_country'=>params['vads_card_country'],
						'order_id'=>params['vads_order_id'],
						'email'=>params['vads_cust_email']
					}
					update_transaction(maj)
					texte=maj['amount']>=30 ? "Nouvelle adhésion enregistrée" : "Nouveau don enregistré"
					recipient=transaction['candidate_id'].nil? ? "LaPrimaire.org" : transaction['name']
					notifs.push([
						"%s ! %s %s (%s, %s) : %s€ [TO:%s][%s]" % [texte,transaction['firstname'],transaction['lastname'],transaction['zipcode'],transaction['city'],maj['amount'].to_s,recipient,maj['status']],
						"crowdfunding",
						":moneybag:",
						"Payzen"
					])
				rescue StandardError=>e
					status 403
					API.log.error "POST payment/ipn STD error #{e.message}"
				rescue PG::Error=>e
					status 500
					API.log.error "POST payment/ipn PG error #{e.message}"
				ensure
					pg_close()
				end
				slack_notifications(notifs)
			end
		end
	end
end
