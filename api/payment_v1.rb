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
					tmp=tmp.sort.to_h
					vads=tmp.values.flatten
					if ::DEBUG then
						vads.push(PZ_TEST_CERT) 
					else
						vads.push(PZ_TEST_CERT) 
					end
					vads_str=vads.join('+')
					return Digest::SHA1.hexdigest(vads_str)
				end

				def get_transaction(transaction_id)
					search_transaction="SELECT * FROM donations WHERE donation_id=$1"
					res=API.pg.exec_params(search_transaction,[transaction_id])
					return res.num_tuples.zero? ? nil : res[0]
				end

				def update_transaction(transaction)
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
UPDATE donations SET status=$1, amount_raw=$2, currency=$3, change_rate=$4, amount=$5, auth_result=$6, threeds=$7, threeds_status=$8, card_brand=$9, card_number=$10, card_expiry_month=$11, card_expiry_year=$12, card_bank_code=$13, card_bank_product=$14, card_country=$15, order_id=$16, email=$17 WHERE donation_id=$18 RETURNING *
END
					res=API.pg.exec_params(upd_transaction,params)
					return res.num_tuples.zero? ? nil : res[0]
				end

				def create_transaction(email)
					order_id=DateTime.parse(Time.now().to_s).strftime("%Y%m%d%H%M%S")+rand(999).to_i.to_s
					new_transaction="INSERT INTO donations (origin,email,order_id) VALUES ('payzen',$1,$2) RETURNING *"
					res=API.pg.exec_params(new_transaction,[email,order_id])
					return res.num_tuples.zero? ? nil : res[0]
				end
			end

			get do
				# DO NOT DELETE used to test the api is live
				return {"api_version"=>"payment/v1"}
			end
			
			#get 'signature' do
			#	return signature()
			#end

			post 'transaction' do
				email=params['email'].downcase
				return JSON.dump({'error'=>'wrong email'}) if !email_valid(email)
				answer={}
				pg_connect()
				begin
					transaction=create_transaction(email)
					raise "cannot create transaction" if transaction.nil?
					params['vads_trans_id']=transaction['donation_id']
					params['vads_order_id']=transaction['order_id']
					params['vads_cust_email']=transaction['email']
					answer={
						'signature'=>signature(params),
						'transaction_id'=>transaction['donation_id'],
						'order_id'=>transaction['order_id'],
						'email'=>transaction['email']
					}
					#answer["transaction_date"]=Date.parse(transaction['created']).strftime("%Y%M%D%H%m%s")
				rescue StandardError=>e #TO_CHECK
					status 500
					API.log.error "POST payment/transaction STD error #{e.message}"
				rescue PG::Error=>e
					status 500
					API.log.error "POST payment/transaction PG error #{e.message}"
				ensure
					pg_close()
				end
				return JSON.dump(answer)
			end

			post 'ipn' do
				sig=signature(params)
				pg_connect()
				begin
					raise "bad signature" if (params['signature']!=sig)
					transaction=get_transaction(params['vads_trans_id'])
					raise "transaction not found" if transaction.nil?
					raise "transaction already processed" if transaction['status']!='CREATED' #CHECK_1
					maj={
						'transaction_id'=>params['vads_trans_id'],
						'status'=>params['vads_trans_status'],
						'amount_raw'=>params['vads_amount'],
						'currency'=>params['vads_currency'],
						'change_rate'=>params['vads_change_rate'],
						'amount'=>params['vads_effective_amount'],
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
						'email'=>params['email']
					}
					update_transaction(maj)
				rescue StandardError=>e #TO_CHECK
					status 403
					API.log.error "POST payment/ipn STD error #{e.message}"
				rescue PG::Error=>e
					status 500
					API.log.error "POST payment/ipn PG error #{e.message}"
				ensure
					pg_close()
				end
			end
		end
	end
end
